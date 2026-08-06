#!/usr/bin/env bash

AZURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${AZURE_DIR}/.." && pwd)"
COMPOSE_FILE="${AZURE_DIR}/compose.yaml"
ENV_FILE="${GCU3_ENV_FILE:-${AZURE_DIR}/.env}"

# shellcheck disable=SC1091
source "${REPO_ROOT}/linux/lib/common.sh"

die() {
  log_err "$*"
  exit 1
}

require_commands() {
  local command_name
  for command_name in "$@"; do
    has_cmd "$command_name" || die "Required command not found: ${command_name}"
  done
}

is_allowed_config_key() {
  case "$1" in
    GCU3_AZURE_HOST | GCU3_AZURE_SSH_USER | GCU3_AZURE_SSH_PORT | \
      GCU3_AZURE_SSH_KEY | GCU3_AZURE_SSH_ALIAS | \
      GCU3_DOCKER_CONTEXT | GCU3_COMPOSE_PROJECT | GCU3_REMOTE_ROOT | \
      GCU3_LOCAL_SOURCE | GCU3_LOCAL_ARTIFACTS | GCU3_YOCTO_IMAGE | \
      GCU3_UID | GCU3_GID | GCU3_CONTAINER_CPUS | GCU3_CONTAINER_MEMORY | \
      GCU3_BB_NUMBER_THREADS | GCU3_PARALLEL_MAKE | \
      GCU3_MIN_DATA_DISK_GB | GCU3_MIN_FREE_DISK_GB | \
      GCU3_MIN_CPUS | GCU3_MIN_MEMORY_GB)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

load_config() {
  local line key value line_number=0

  [[ -f "$ENV_FILE" ]] || die "Configuration not found: ${ENV_FILE}. Copy azure/.env.example to azure/.env."
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] ||
      die "Invalid configuration syntax at ${ENV_FILE}:${line_number}"
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    is_allowed_config_key "$key" ||
      die "Unsupported configuration key '${key}' at ${ENV_FILE}:${line_number}"
    if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi
    # shellcheck disable=SC2016
    [[ "$value" != *'$('* && "$value" != *'`'* ]] ||
      die "Command substitution is not allowed in ${ENV_FILE}:${line_number}"
    printf -v "$key" '%s' "$value"
    export "${key?}"
  done < "$ENV_FILE"

  : "${GCU3_AZURE_SSH_ALIAS:=gcu3-platform-azure}"
  : "${GCU3_DOCKER_CONTEXT:=gcu3-platform-azure}"
  : "${GCU3_COMPOSE_PROJECT:=gcu3-platform}"
  : "${GCU3_REMOTE_ROOT:=/opt/data/gcu3-platform}"
  : "${GCU3_AZURE_SSH_PORT:=22}"
  : "${GCU3_UID:=1000}"
  : "${GCU3_GID:=1000}"
  : "${GCU3_CONTAINER_CPUS:=2}"
  : "${GCU3_CONTAINER_MEMORY:=6g}"
  : "${GCU3_BB_NUMBER_THREADS:=2}"
  : "${GCU3_PARALLEL_MAKE:=-j 2}"
  : "${GCU3_MIN_DATA_DISK_GB:=400}"
  : "${GCU3_MIN_FREE_DISK_GB:=200}"
  : "${GCU3_MIN_CPUS:=4}"
  : "${GCU3_MIN_MEMORY_GB:=16}"
}

validate_config() {
  [[ "$GCU3_DOCKER_CONTEXT" == "gcu3-platform-azure" ]] ||
    die "GCU3_DOCKER_CONTEXT must be gcu3-platform-azure"
  [[ "$GCU3_COMPOSE_PROJECT" == "gcu3-platform" ]] ||
    die "GCU3_COMPOSE_PROJECT must be gcu3-platform"
  [[ "$GCU3_REMOTE_ROOT" == "/opt/data/gcu3-platform" ]] ||
    die "GCU3_REMOTE_ROOT must be /opt/data/gcu3-platform"
  [[ "$GCU3_AZURE_SSH_ALIAS" =~ ^[A-Za-z0-9._-]+$ ]] ||
    die "GCU3_AZURE_SSH_ALIAS contains unsafe characters"
  [[ "$GCU3_AZURE_SSH_PORT" =~ ^[0-9]+$ ]] ||
    die "GCU3_AZURE_SSH_PORT must be numeric"
  [[ "$GCU3_UID" =~ ^[0-9]+$ && "$GCU3_GID" =~ ^[0-9]+$ ]] ||
    die "GCU3_UID and GCU3_GID must be numeric"
  [[ "$GCU3_UID" -gt 0 && "$GCU3_GID" -gt 0 ]] ||
    die "GCU3_UID and GCU3_GID must be non-root"
  [[ "$GCU3_MIN_DATA_DISK_GB" =~ ^[0-9]+$ ]] ||
    die "GCU3_MIN_DATA_DISK_GB must be numeric"
  [[ "$GCU3_MIN_FREE_DISK_GB" =~ ^[0-9]+$ ]] ||
    die "GCU3_MIN_FREE_DISK_GB must be numeric"
}

validate_builder_image() {
  [[ -n "${GCU3_YOCTO_IMAGE:-}" ]] ||
    die "GCU3_YOCTO_IMAGE is required"
  [[ "$GCU3_YOCTO_IMAGE" =~ @sha256:[0-9a-f]{64}$ ]] ||
    die "GCU3_YOCTO_IMAGE must use an immutable sha256 digest"
}

assert_default_context_is_local() {
  local current_context default_endpoint
  [[ -z "${DOCKER_HOST:-}" ]] ||
    die "DOCKER_HOST must be unset; use explicit --context selection"
  [[ -z "${DOCKER_CONTEXT:-}" || "$DOCKER_CONTEXT" == "default" ]] ||
    die "DOCKER_CONTEXT must be unset or default"
  current_context="$(docker context show)"
  [[ "$current_context" == "default" ]] ||
    die "Active Docker context is '${current_context}', expected 'default'. Do not use docker context use."
  default_endpoint="$(docker context inspect default --format '{{ (index .Endpoints "docker").Host }}')"
  [[ "$default_endpoint" == unix://* || "$default_endpoint" == npipe://* ]] ||
    die "Docker default context is not a recognized local endpoint: ${default_endpoint}"
}

assert_remote_context() {
  local endpoint
  docker context inspect "$GCU3_DOCKER_CONTEXT" >/dev/null 2>&1 ||
    die "Docker context '${GCU3_DOCKER_CONTEXT}' does not exist; run azure/setup_context.sh"
  endpoint="$(docker context inspect "$GCU3_DOCKER_CONTEXT" \
    --format '{{ (index .Endpoints "docker").Host }}')"
  [[ "$endpoint" == "ssh://${GCU3_AZURE_SSH_ALIAS}" ]] ||
    die "Context '${GCU3_DOCKER_CONTEXT}' has unexpected endpoint: ${endpoint}"
}

docker_remote() {
  docker --context "$GCU3_DOCKER_CONTEXT" "$@"
}

compose_remote() {
  docker --context "$GCU3_DOCKER_CONTEXT" compose \
    --env-file "$ENV_FILE" \
    --project-name "$GCU3_COMPOSE_PROJECT" \
    --file "$COMPOSE_FILE" "$@"
}

assert_project_stopped() {
  local state states
  states="$(docker_remote ps --all \
    --filter "label=com.docker.compose.project=${GCU3_COMPOSE_PROJECT}" \
    --format '{{.State}}')"
  while IFS= read -r state; do
    case "$state" in
      "" | exited | dead) ;;
      *) die "Stop the ${GCU3_COMPOSE_PROJECT} Compose project before replacing remote source (state=${state})" ;;
    esac
  done <<< "$states"
}

assert_remote_storage_ready() {
  ssh "$GCU3_AZURE_SSH_ALIAS" bash -s -- "$GCU3_REMOTE_ROOT" <<'REMOTE'
set -Eeuo pipefail
root="$1"

fail() {
  printf '[ERR] %s\n' "$*" >&2
  exit 1
}

[[ "$root" == "/opt/data/gcu3-platform" ]] ||
  fail "Refusing unsafe remote root: ${root}"
[[ -d "$root" && ! -L /opt/data && ! -L "$root" ]] ||
  fail "Dedicated root must be a real directory: ${root}"
[[ "$(realpath -e "$root")" == "$root" ]] ||
  fail "Dedicated root does not resolve to itself: ${root}"
[[ "$(findmnt -T "$root" -n -o TARGET,FSTYPE)" == "/opt/data ext4" ]] ||
  fail "Dedicated root is not on the expected /opt/data ext4 mount"
for path in src downloads sstate-cache build artifacts; do
  target="${root}/${path}"
  [[ -d "$target" && ! -L "$target" && "$(realpath -e "$target")" == "$target" ]] ||
    fail "Managed bind source must be a real directory: ${target}"
done
REMOTE
}

validate_relative_path() {
  local value="$1"
  [[ -n "$value" && "$value" != /* && "$value" != "." && "$value" != ".." ]] ||
    die "Path must be a non-empty relative path: ${value}"
  [[ "/$value/" != *"/../"* && "/$value/" != *"/./"* ]] ||
    die "Path traversal is not allowed: ${value}"
}

resolve_local_path() {
  local value="$1"
  if [[ "${value:0:2}" == \~/ ]]; then
    value="${HOME}/${value#~/}"
  elif [[ "$value" != /* ]]; then
    value="${REPO_ROOT}/${value}"
  fi
  realpath -m "$value"
}

atomic_replace_remote_source() {
  local stage="$1"
  ssh "$GCU3_AZURE_SSH_ALIAS" bash -s -- "$GCU3_REMOTE_ROOT" "$stage" <<'REMOTE'
set -Eeuo pipefail

root="$1"
stage="$2"
source_path="${root}/src"
backup="${root}/src.previous-${stage##*.stage-}"

fail() {
  printf '[ERR] %s\n' "$*" >&2
  exit 1
}

[[ "$root" == "/opt/data/gcu3-platform" ]] ||
  fail "Refusing unsafe remote root: ${root}"
[[ -d "$root" && ! -L /opt/data && ! -L "$root" ]] ||
  fail "Dedicated root must be a real directory: ${root}"
[[ "$(realpath -e "$root")" == "$root" ]] ||
  fail "Dedicated root does not resolve to itself: ${root}"
[[ "$(findmnt -T "$root" -n -o TARGET)" == "/opt/data" ]] ||
  fail "Dedicated root is not on the /opt/data mount"
[[ "$stage" == "${root}/src.stage-"* && -d "$stage" && ! -L "$stage" ]] ||
  fail "Refusing unsafe or missing staging path: ${stage}"
[[ "$backup" == "${root}/src.previous-"* ]] ||
  fail "Refusing unsafe backup path: ${backup}"
[[ ! -e "$backup" ]] ||
  fail "Backup path already exists: ${backup}"
if [[ -e "$source_path" || -L "$source_path" ]]; then
  [[ -d "$source_path" && ! -L "$source_path" ]] ||
    fail "Existing source path must be a real directory: ${source_path}"
fi

if [[ -d "$source_path" ]]; then
  mv -- "$source_path" "$backup"
fi

if mv -- "$stage" "$source_path"; then
  if [[ -d "$backup" ]]; then
    rm -rf -- "$backup"
  fi
  printf '[OK] Remote source replaced atomically: %s\n' "$source_path"
else
  [[ -d "$backup" ]] && mv -- "$backup" "$source_path"
  fail "Failed to activate staged source"
fi
REMOTE
}
