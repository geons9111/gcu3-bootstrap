#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

load_config
validate_config
require_commands docker ssh
assert_default_context_is_local
assert_remote_context
docker_remote info >/dev/null 2>&1 ||
  die "Azure context cannot access the remote Docker daemon"

log_step "Preparing only ${GCU3_REMOTE_ROOT} on ${GCU3_AZURE_SSH_ALIAS}"
ssh "$GCU3_AZURE_SSH_ALIAS" bash -s -- \
  "$GCU3_REMOTE_ROOT" "$GCU3_MIN_DATA_DISK_GB" "$GCU3_MIN_FREE_DISK_GB" \
  "$GCU3_UID" "$GCU3_GID" <<'REMOTE'
set -Eeuo pipefail

root="$1"
minimum_gb="$2"
minimum_free_gb="$3"
expected_uid="$4"
expected_gid="$5"

fail() {
  printf '[ERR] %s\n' "$*" >&2
  exit 1
}

[[ "$root" == "/opt/data/gcu3-platform" ]] ||
  fail "Refusing unsafe remote root: ${root}"
[[ ! -L /opt/data && ! -L "$root" ]] ||
  fail "Symlinks are not allowed for /opt/data or the dedicated root"
[[ "$(realpath -m "$root")" == "$root" ]] ||
  fail "Remote root does not resolve to the approved path"

for command_name in findmnt df install realpath stat sudo; do
  command -v "$command_name" >/dev/null 2>&1 ||
    fail "Required remote command not found: ${command_name}"
done

mount_target="$(findmnt -T /opt/data -n -o TARGET)"
filesystem="$(findmnt -T /opt/data -n -o FSTYPE)"
[[ "$mount_target" == "/opt/data" ]] ||
  fail "/opt/data is not a dedicated mount (resolved mount: ${mount_target})"
[[ "$filesystem" == "ext4" ]] ||
  fail "/opt/data must be ext4 (found: ${filesystem})"

size_gb="$(df -BG --output=size /opt/data | awk 'NR == 2 { gsub(/G/, ""); print $1 }')"
available_gb="$(df -BG --output=avail /opt/data | awk 'NR == 2 { gsub(/G/, ""); print $1 }')"
[[ "$size_gb" =~ ^[0-9]+$ && "$size_gb" -ge "$minimum_gb" ]] ||
  fail "/opt/data is ${size_gb:-unknown} GB; require at least ${minimum_gb} GB"
[[ "$available_gb" =~ ^[0-9]+$ && "$available_gb" -ge "$minimum_free_gb" ]] ||
  printf '[WARN] /opt/data has %s GB free; routine-build target is %s GB\n' \
    "${available_gb:-unknown}" "$minimum_free_gb" >&2

actual_uid="$(id -u)"
actual_gid="$(id -g)"
[[ "$actual_uid" == "$expected_uid" && "$actual_gid" == "$expected_gid" ]] ||
  fail "Configured UID:GID ${expected_uid}:${expected_gid} does not match SSH user ${actual_uid}:${actual_gid}"

for path in "$root" src downloads sstate-cache build artifacts; do
  if [[ "$path" == "$root" ]]; then
    target="$root"
  else
    target="$root/$path"
  fi
  if [[ -e "$target" || -L "$target" ]]; then
    [[ -d "$target" && ! -L "$target" ]] ||
      fail "Existing managed path must be a real directory: ${target}"
  fi
done

sudo install -d -m 0750 -o "$expected_uid" -g "$expected_gid" \
  "$root" \
  "$root/src" \
  "$root/downloads" \
  "$root/sstate-cache" \
  "$root/build" \
  "$root/artifacts"

for path in src downloads sstate-cache build artifacts; do
  owner="$(stat -c '%u:%g' "$root/$path")"
  [[ "$owner" == "${expected_uid}:${expected_gid}" ]] ||
    fail "Unexpected owner for ${root}/${path}: ${owner}"
  [[ -w "$root/$path" ]] ||
    fail "SSH user cannot write ${root}/${path}"
done

printf '[OK] data disk: ext4, %s GB total, %s GB available\n' "$size_gb" "$available_gb"
printf '[OK] dedicated directories prepared with owner %s:%s\n' "$expected_uid" "$expected_gid"
printf '[OK] Docker access verified; no daemon settings or existing objects changed\n'
REMOTE

assert_default_context_is_local
log_ok "Remote preparation complete"
