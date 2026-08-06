#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

OFFLINE=0
if [[ "${1:-}" == "--offline" ]]; then
  OFFLINE=1
  shift
fi
[[ $# -eq 0 ]] || {
  echo "Usage: $0 [--offline]" >&2
  exit 2
}

PASS=0
WARN=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  printf '[PASS] %s\n' "$*"
}
warn() {
  WARN=$((WARN + 1))
  printf '[WARN] %s\n' "$*"
}
fail() {
  FAIL=$((FAIL + 1))
  printf '[FAIL] %s\n' "$*" >&2
}

load_config
validate_config
validate_builder_image

for command_name in docker ssh rsync jq; do
  if has_cmd "$command_name"; then
    pass "Required local command: ${command_name}"
  else
    fail "Required local command missing: ${command_name}"
  fi
done

if [[ "$FAIL" -eq 0 ]]; then
  if assert_default_context_is_local; then
    pass "Active default Docker context is local"
  else
    fail "Default Docker context isolation check failed"
  fi

  CONFIG_JSON="$(docker compose \
    --env-file "$ENV_FILE" \
    --project-name "$GCU3_COMPOSE_PROJECT" \
    --file "$COMPOSE_FILE" config --format json)"

  if jq -e '.name == "gcu3-platform"' <<< "$CONFIG_JSON" >/dev/null; then
    pass "Compose project name is fixed to gcu3-platform"
  else
    fail "Compose project name is not scoped correctly"
  fi
  if jq -e '(.services.builder.privileged // false) == false' <<< "$CONFIG_JSON" >/dev/null; then
    pass "Builder is not privileged"
  else
    fail "Builder privileged mode is not explicitly disabled"
  fi
  if jq -e '
    .services.builder.volumes as $volumes |
    ($volumes | length) == 5 and
    all($volumes[];
      .type == "bind" and
      .bind.create_host_path == false and
      (.source | startswith("/opt/data/gcu3-platform/"))
    )
  ' <<< "$CONFIG_JSON" >/dev/null; then
    pass "All persistent mounts use guarded dedicated-root bind sources"
  else
    fail "Compose has an unsafe or missing bind mount"
  fi
fi

if [[ "$OFFLINE" -eq 1 ]]; then
  if docker context inspect "$GCU3_DOCKER_CONTEXT" >/dev/null 2>&1; then
    OFFLINE_ENDPOINT="$(docker context inspect "$GCU3_DOCKER_CONTEXT" \
      --format '{{ (index .Endpoints "docker").Host }}')"
    if [[ "$OFFLINE_ENDPOINT" == "ssh://${GCU3_AZURE_SSH_ALIAS}" ]]; then
      pass "Remote context endpoint is isolated"
    else
      warn "Existing remote context endpoint differs from this configuration: ${OFFLINE_ENDPOINT}"
    fi
  else
    warn "Remote context is not configured; remote checks skipped"
  fi
else
  if assert_remote_context; then
    pass "Remote context endpoint is isolated"
  else
    fail "Remote context is unavailable or incorrect"
  fi

  if [[ "$FAIL" -eq 0 ]]; then
    read -r REMOTE_CPUS REMOTE_MEMORY_BYTES DOCKER_ROOT < <(
      docker_remote info --format '{{.NCPU}} {{.MemTotal}} {{.DockerRootDir}}'
    )
    REMOTE_MEMORY_GB=$((REMOTE_MEMORY_BYTES / 1024 / 1024 / 1024))
    if [[ "$DOCKER_ROOT" == "/var/lib/docker" ]]; then
      pass "Docker data-root remains /var/lib/docker"
    else
      warn "Docker data-root is ${DOCKER_ROOT}; this workflow did not change it"
    fi
    if [[ "$REMOTE_CPUS" -ge "$GCU3_MIN_CPUS" ]]; then
      pass "Remote CPU capacity: ${REMOTE_CPUS}"
    else
      warn "Remote CPU capacity is ${REMOTE_CPUS}; target is ${GCU3_MIN_CPUS}+"
    fi
    if [[ "$REMOTE_MEMORY_GB" -ge "$GCU3_MIN_MEMORY_GB" ]]; then
      pass "Remote memory capacity: ${REMOTE_MEMORY_GB} GB"
    else
      warn "Remote memory is ${REMOTE_MEMORY_GB} GB; target is ${GCU3_MIN_MEMORY_GB}+ GB"
    fi

    if REMOTE_DISK_RESULT="$(ssh "$GCU3_AZURE_SSH_ALIAS" bash -s -- \
      "$GCU3_REMOTE_ROOT" "$GCU3_MIN_DATA_DISK_GB" <<'REMOTE'
set -Eeuo pipefail
root="$1"
minimum_gb="$2"
[[ "$root" == "/opt/data/gcu3-platform" && -d "$root" && ! -L "$root" ]] || exit 10
[[ "$(findmnt -T /opt/data -n -o TARGET,FSTYPE)" == "/opt/data ext4" ]] || exit 11
for path in src downloads sstate-cache build artifacts; do
  [[ -d "$root/$path" && ! -L "$root/$path" ]] || exit 12
done
size_gb="$(df -BG --output=size /opt/data | awk 'NR == 2 { gsub(/G/, ""); print $1 }')"
free_gb="$(df -BG --output=avail /opt/data | awk 'NR == 2 { gsub(/G/, ""); print $1 }')"
[[ "$size_gb" -ge "$minimum_gb" ]] || exit 13
printf '%s %s\n' "$size_gb" "$free_gb"
REMOTE
    )"; then
      read -r REMOTE_DISK_GB REMOTE_FREE_GB <<< "$REMOTE_DISK_RESULT"
      pass "Dedicated ext4 path and data-disk size verified: ${REMOTE_DISK_GB} GB"
      if [[ "$REMOTE_FREE_GB" -ge "$GCU3_MIN_FREE_DISK_GB" ]]; then
        pass "Remote data-disk free capacity: ${REMOTE_FREE_GB} GB"
      else
        warn "Remote data disk has ${REMOTE_FREE_GB} GB free; routine-build target is ${GCU3_MIN_FREE_DISK_GB}+ GB"
      fi
    else
      fail "Dedicated remote path or data-disk validation failed"
    fi

    if compose_remote config --quiet; then
      pass "Compose renders with the explicit remote context"
    else
      fail "Compose rendering failed"
    fi
    PROJECT_CONTAINERS="$(docker_remote ps --all --quiet \
      --filter "label=com.docker.compose.project=${GCU3_COMPOSE_PROJECT}")"
    if [[ -n "$PROJECT_CONTAINERS" ]]; then
      pass "Status query remained scoped to existing ${GCU3_COMPOSE_PROJECT} containers"
    else
      pass "No ${GCU3_COMPOSE_PROJECT} containers exist; other projects were not queried"
    fi
  fi
fi

printf '\nVerification summary: PASS=%d WARN=%d FAIL=%d\n' "$PASS" "$WARN" "$FAIL"
[[ "$FAIL" -eq 0 ]]
