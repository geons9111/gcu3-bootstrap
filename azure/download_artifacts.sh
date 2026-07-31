#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

[[ $# -eq 1 ]] || {
  echo "Usage: $0 <relative-artifact-path>" >&2
  exit 2
}
ARTIFACT_PATH="$1"

load_config
validate_config
require_commands docker rsync ssh realpath
assert_default_context_is_local
assert_remote_context
assert_project_stopped
validate_relative_path "$ARTIFACT_PATH"
[[ "$ARTIFACT_PATH" =~ ^[A-Za-z0-9._/-]+$ ]] ||
  die "Artifact path contains unsupported characters"
: "${GCU3_LOCAL_ARTIFACTS:?Set GCU3_LOCAL_ARTIFACTS in azure/.env}"

LOCAL_ARTIFACTS="$(resolve_local_path "$GCU3_LOCAL_ARTIFACTS")"
REMOTE_ARTIFACT="${GCU3_REMOTE_ROOT}/artifacts/${ARTIFACT_PATH}"

ssh "$GCU3_AZURE_SSH_ALIAS" bash -s -- \
  "${GCU3_REMOTE_ROOT}/artifacts" "$REMOTE_ARTIFACT" <<'REMOTE'
set -Eeuo pipefail
artifacts_root="$1"
requested="$2"
[[ "$artifacts_root" == "/opt/data/gcu3-platform/artifacts" ]] || exit 1
root="${artifacts_root%/artifacts}"
[[ -d "$root" && ! -L /opt/data && ! -L "$root" && ! -L "$artifacts_root" ]] || {
  echo "[ERR] Dedicated artifact root must be a real directory" >&2
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
resolved="$(realpath -e "$requested")"
[[ "$resolved" == "${artifacts_root}/"* ]] || {
  echo "[ERR] Requested artifact escapes the dedicated artifact directory" >&2
  exit 1
}
[[ "$resolved" == "$requested" ]] || {
  echo "[ERR] Symlinks are not accepted for artifact downloads" >&2
  exit 1
}
[[ -f "$resolved" || -d "$resolved" ]] || {
  echo "[ERR] Requested artifact is not a regular file or directory" >&2
  exit 1
}
REMOTE

LOCAL_PARENT="${LOCAL_ARTIFACTS}/$(dirname "$ARTIFACT_PATH")"
mkdir -p "$LOCAL_PARENT"
rsync --archive --compress --safe-links --human-readable \
  "${GCU3_AZURE_SSH_ALIAS}:${REMOTE_ARTIFACT}" "${LOCAL_PARENT}/"
assert_default_context_is_local
log_ok "Downloaded only '${ARTIFACT_PATH}' to ${LOCAL_PARENT}"
