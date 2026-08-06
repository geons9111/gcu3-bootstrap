#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

load_config
validate_config
require_commands docker rsync ssh realpath
assert_default_context_is_local
assert_remote_context
assert_project_stopped

: "${GCU3_LOCAL_SOURCE:?Set GCU3_LOCAL_SOURCE in azure/.env}"
LOCAL_SOURCE="$(resolve_local_path "$GCU3_LOCAL_SOURCE")"
[[ -d "$LOCAL_SOURCE" ]] || die "Local source directory not found: ${LOCAL_SOURCE}"
[[ -f "${LOCAL_SOURCE}/.git/HEAD" ]] ||
  log_warn "${LOCAL_SOURCE} is not a Git worktree; syncing its current files anyway"

TOKEN="$(date -u +%Y%m%dT%H%M%SZ)-$$"
STAGE="${GCU3_REMOTE_ROOT}/src.stage-${TOKEN}"

ssh "$GCU3_AZURE_SSH_ALIAS" bash -s -- "$GCU3_REMOTE_ROOT" "$STAGE" <<'REMOTE'
set -Eeuo pipefail
root="$1"
stage="$2"
[[ "$root" == "/opt/data/gcu3-platform" && "$stage" == "${root}/src.stage-"* ]] || {
  echo "[ERR] Refusing unsafe staging path" >&2
  exit 1
}
[[ -d "$root" && ! -L /opt/data && ! -L "$root" ]] || {
  echo "[ERR] Dedicated root must be a real directory" >&2
  exit 1
}
[[ "$(realpath -e "$root")" == "$root" ]] || {
  echo "[ERR] Dedicated root does not resolve to itself" >&2
  exit 1
}
[[ "$(findmnt -T "$root" -n -o TARGET)" == "/opt/data" ]] || {
  echo "[ERR] Dedicated root is not on the /opt/data mount" >&2
  exit 1
}
[[ ! -e "$stage" ]] || {
  echo "[ERR] Staging path already exists: ${stage}" >&2
  exit 1
}
install -d -m 0750 "$stage"
REMOTE

cleanup_stage() {
  ssh "$GCU3_AZURE_SSH_ALIAS" bash -s -- "$GCU3_REMOTE_ROOT" "$STAGE" <<'REMOTE' || true
set -Eeuo pipefail
root="$1"
stage="$2"
[[ "$root" == "/opt/data/gcu3-platform" && "$stage" == "${root}/src.stage-"* ]] || exit 1
[[ -d "$root" && ! -L /opt/data && ! -L "$root" ]] || exit 1
[[ "$(realpath -e "$root")" == "$root" ]] || exit 1
[[ "$(findmnt -T "$root" -n -o TARGET)" == "/opt/data" ]] || exit 1
[[ -d "$stage" && ! -L "$stage" ]] && rm -rf -- "$stage"
REMOTE
}
trap cleanup_stage EXIT

log_step "Syncing ${LOCAL_SOURCE} to an isolated remote staging directory"
rsync --archive --compress --safe-links --human-readable \
  --exclude-from="${SCRIPT_DIR}/rsync-excludes.txt" \
  "${LOCAL_SOURCE}/" "${GCU3_AZURE_SSH_ALIAS}:${STAGE}/"

atomic_replace_remote_source "$STAGE"
trap - EXIT
assert_default_context_is_local
log_ok "Source sync complete; no --delete operation was used"
