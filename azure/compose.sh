#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: azure/compose.sh <command> [arguments]

Commands:
  config              Render and validate Compose configuration
  status              Show only gcu3-platform project containers
  pull                Pull the pinned builder image
  start               Start the long-lived builder (does not run a build)
  stop                Stop only the gcu3-platform project
  down                Remove only gcu3-platform containers and network
  shell               Open bash in the running builder
  logs [lines]        Show a bounded builder log tail (default: 200)
  run <command...>    Run an explicit command in a project-scoped container
USAGE
}

[[ $# -ge 1 ]] || {
  usage >&2
  exit 2
}
ACTION="$1"
shift

load_config
validate_config
validate_builder_image
require_commands docker
assert_default_context_is_local
assert_remote_context

case "$ACTION" in
  config)
    [[ $# -eq 0 ]] || die "config takes no arguments"
    compose_remote config
    ;;
  status)
    [[ $# -eq 0 ]] || die "status takes no arguments"
    compose_remote ps --all
    ;;
  pull)
    [[ $# -eq 0 ]] || die "pull takes no arguments"
    compose_remote pull builder
    ;;
  start)
    [[ $# -eq 0 ]] || die "start takes no arguments"
    assert_remote_storage_ready
    compose_remote up --detach --no-build builder
    ;;
  stop)
    [[ $# -eq 0 ]] || die "stop takes no arguments"
    compose_remote stop builder
    ;;
  down)
    [[ $# -eq 0 ]] || die "down takes no arguments"
    compose_remote down
    ;;
  shell)
    [[ $# -eq 0 ]] || die "shell takes no arguments"
    compose_remote exec builder bash
    ;;
  logs)
    LINES="${1:-200}"
    [[ $# -le 1 && "$LINES" =~ ^[0-9]+$ && "$LINES" -le 5000 ]] ||
      die "logs accepts one numeric line count up to 5000"
    compose_remote logs --tail "$LINES" builder
    ;;
  run)
    [[ $# -gt 0 ]] || die "run requires an explicit command"
    assert_remote_storage_ready
    compose_remote run --rm --no-deps builder "$@"
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    usage >&2
    die "Unknown command: ${ACTION}"
    ;;
esac

assert_default_context_is_local
