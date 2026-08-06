#!/usr/bin/env bash
# =====================================================================
# GCU3 Integration - 統括 (00) v1.1
# 目的: VS Code × GitHub × Docker 連携を一括セットアップ
# 前提: bootstrap(git/docker/python) 済み
# 配置: gcu3-bootstrap/integration/ 配下（README §9 から参照）
# MECE是正:
#   - gh手順は 20_setup_github_cli.sh に一本化（本統括は呼び出すだけ）
#   - target(wsl/native) を VS Code 連携へ引き渡す
# 使い方:
#   ./00_integration.sh --email you@kubota.com --project ~/work/gcu3-devplat [--target wsl|native|auto]
# =====================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
c_cyan='\033[0;36m'; c_green='\033[0;32m'; c_yellow='\033[0;33m'; c_off='\033[0m'
step(){ echo -e "${c_cyan}==> $*${c_off}"; }; ok(){ echo -e "${c_green}[OK] $*${c_off}"; }; warn(){ echo -e "${c_yellow}[WARN] $*${c_off}"; }

EMAIL=""; PROJECT="."; HOST="github.com"; TARGET="auto"; GH_AUTH=1; EXT=1; export DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --email) EMAIL="${2:-}"; shift 2 ;;
    --project) PROJECT="${2:-.}"; shift 2 ;;
    --host) HOST="${2:-github.com}"; shift 2 ;;
    --target) TARGET="${2:-auto}"; shift 2 ;;
    --no-github-auth) GH_AUTH=0; shift ;;
    --no-extensions) EXT=0; shift ;;
    --dry-run) export DRY_RUN=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "不明な引数: $1"; exit 10 ;;
  esac
done

# target auto解決（VS Codeモードにも使用）
if [[ "$TARGET" == "auto" ]]; then
  grep -qiE "microsoft|wsl" /proc/version 2>/dev/null && TARGET="wsl" || TARGET="native"
fi
VS_MODE=$([[ "$TARGET" == "wsl" ]] && echo "wsl" || echo "ssh")

step "GCU3 Integration 開始 (project=${PROJECT} / target=${TARGET})"

# 1) GitHub CLI + SSH（gh手順はここに一本化）
GH_ARGS=(--host "$HOST"); [[ -n "$EMAIL" ]] && GH_ARGS+=(--email "$EMAIL"); [[ "$GH_AUTH" -eq 0 ]] && GH_ARGS+=(--no-auth)
bash "${SCRIPT_DIR}/20_setup_github_cli.sh" "${GH_ARGS[@]}"

# 2) Docker 状態確認
bash "${SCRIPT_DIR}/21_docker_manage.sh" status || true

# 3) VS Code 拡張 + テンプレ（target→mode引き渡し）
VS_ARGS=(--project "$PROJECT" --mode "$VS_MODE"); [[ "$EXT" -eq 0 ]] && VS_ARGS+=(--no-extensions)
bash "${SCRIPT_DIR}/22_setup_vscode.sh" "${VS_ARGS[@]}"

ok "Integration 完了 (target=${TARGET})"
echo ""
echo "====================================================================="
echo " 次の手順"
echo "====================================================================="
echo " 1) GitHub 接続確認:   ssh -T git@${HOST}"
if [[ "$TARGET" == "wsl" ]]; then
  echo " 2) VS Code 起動:      cd ${PROJECT} && code ."
else
  echo " 2) VS Code 起動:      Windows VS Code → Remote-SSH で ${PROJECT} を開く"
fi
echo " 3) Dev Container:     コマンドパレット → Dev Containers: Reopen in Container"
echo " 4) Docker 管理:       bash integration/linux/21_docker_manage.sh status"
echo " 5) 詳細:              docs/GUIDE_VSCode_GitHub_Docker.md"
echo "====================================================================="
