#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  echo "Usage: $0 <repository-url> <branch-or-tag>"
}

[[ $# -eq 2 ]] || {
  usage >&2
  exit 2
}
REPOSITORY_URL="$1"
REVISION="$2"

load_config
validate_config
require_commands docker ssh
assert_default_context_is_local
assert_remote_context
assert_project_stopped

if [[ "$REPOSITORY_URL" =~ ^https://[A-Za-z0-9._-]+(:[0-9]+)?/[A-Za-z0-9._~/-]+$ ]]; then
  :
elif [[ "$REPOSITORY_URL" =~ ^ssh://[A-Za-z0-9._-]+@[A-Za-z0-9._-]+(:[0-9]+)?/[A-Za-z0-9._~/-]+$ ]]; then
  :
elif [[ "$REPOSITORY_URL" =~ ^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+:[A-Za-z0-9._~/-]+$ ]]; then
  :
else
  die "Repository URL must be credential-free HTTPS or a strict SSH URL"
fi
[[ "$REVISION" =~ ^[A-Za-z0-9._/-]+$ && "$REVISION" != -* && "$REVISION" != *..* ]] ||
  die "Unsafe branch or tag: ${REVISION}"

TOKEN="$(date -u +%Y%m%dT%H%M%SZ)-$$"
STAGE="${GCU3_REMOTE_ROOT}/src.stage-${TOKEN}"

log_step "Cloning requested revision into an isolated remote staging directory"
ssh "$GCU3_AZURE_SSH_ALIAS" bash -s -- \
  "$GCU3_REMOTE_ROOT" "$STAGE" "$REPOSITORY_URL" "$REVISION" <<'REMOTE'
set -Eeuo pipefail
root="$1"
stage="$2"
repository_url="$3"
revision="$4"

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
command -v git >/dev/null 2>&1 || {
  echo "[ERR] git is not installed on the remote host" >&2
  exit 1
}
cleanup() {
  [[ -d "$stage" && ! -L "$stage" ]] && rm -rf -- "$stage"
}
trap cleanup ERR
git clone --single-branch --branch "$revision" -- "$repository_url" "$stage"
trap - ERR
REMOTE

atomic_replace_remote_source "$STAGE"
assert_default_context_is_local
log_ok "Remote clone complete; credentials were not persisted by this script"
