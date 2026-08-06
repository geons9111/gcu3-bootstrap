#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

load_config
validate_config
require_commands awk docker install mktemp realpath ssh
assert_default_context_is_local

: "${GCU3_AZURE_HOST:?Set GCU3_AZURE_HOST in azure/.env}"
: "${GCU3_AZURE_SSH_USER:?Set GCU3_AZURE_SSH_USER in azure/.env}"
: "${GCU3_AZURE_SSH_KEY:?Set GCU3_AZURE_SSH_KEY in azure/.env}"

[[ "$GCU3_AZURE_HOST" =~ ^[A-Za-z0-9._:-]+$ ]] ||
  die "GCU3_AZURE_HOST contains unsafe characters"
[[ "$GCU3_AZURE_SSH_USER" =~ ^[A-Za-z0-9._-]+$ ]] ||
  die "GCU3_AZURE_SSH_USER contains unsafe characters"

if [[ "${GCU3_AZURE_SSH_KEY:0:2}" == \~/ ]]; then
  GCU3_AZURE_SSH_KEY="${HOME}/${GCU3_AZURE_SSH_KEY#~/}"
fi
[[ -f "$GCU3_AZURE_SSH_KEY" ]] ||
  die "SSH private key not found: ${GCU3_AZURE_SSH_KEY}"
GCU3_AZURE_SSH_KEY="$(realpath "$GCU3_AZURE_SSH_KEY")"

SSH_DIR="${HOME}/.ssh"
SSH_CONFIG="${SSH_DIR}/config"
BLOCK_START="# >>> gcu3-platform-azure >>>"
BLOCK_END="# <<< gcu3-platform-azure <<<"
TEMP_CONFIG="$(mktemp)"
trap 'rm -f "$TEMP_CONFIG"' EXIT

install -d -m 0700 "$SSH_DIR"
touch "$SSH_CONFIG"
chmod 0600 "$SSH_CONFIG"

{
  echo "$BLOCK_START"
  printf 'Host %s\n' "$GCU3_AZURE_SSH_ALIAS"
  printf '  HostName %s\n' "$GCU3_AZURE_HOST"
  printf '  User %s\n' "$GCU3_AZURE_SSH_USER"
  printf '  Port %s\n' "$GCU3_AZURE_SSH_PORT"
  printf '  IdentityFile "%s"\n' "$GCU3_AZURE_SSH_KEY"
  echo "  IdentitiesOnly yes"
  echo "  BatchMode yes"
  echo "$BLOCK_END"
  awk -v start="$BLOCK_START" -v end="$BLOCK_END" '
    $0 == start { managed = 1; next }
    $0 == end { managed = 0; next }
    !managed { print }
  ' "$SSH_CONFIG"
} > "$TEMP_CONFIG"
install -m 0600 "$TEMP_CONFIG" "$SSH_CONFIG"

EXPECTED_ENDPOINT="ssh://${GCU3_AZURE_SSH_ALIAS}"
if docker context inspect "$GCU3_DOCKER_CONTEXT" >/dev/null 2>&1; then
  docker context update "$GCU3_DOCKER_CONTEXT" \
    --description "GCU3 Platform Azure Docker over SSH" \
    --docker "host=${EXPECTED_ENDPOINT}" >/dev/null
  log_ok "Updated Docker context: ${GCU3_DOCKER_CONTEXT}"
else
  docker context create "$GCU3_DOCKER_CONTEXT" \
    --description "GCU3 Platform Azure Docker over SSH" \
    --docker "host=${EXPECTED_ENDPOINT}" >/dev/null
  log_ok "Created Docker context: ${GCU3_DOCKER_CONTEXT}"
fi

assert_remote_context
assert_default_context_is_local
log_ok "Default context remains local; remote access requires --context ${GCU3_DOCKER_CONTEXT}"
