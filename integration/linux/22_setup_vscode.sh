#!/usr/bin/env bash
# =====================================================================
# GCU3 Integration - VS Code 連携 (22) v1.1
# 目的: 拡張一括導入 + .vscode/.devcontainer テンプレ配置
# MECE是正:
#   - Azure Ubuntu VM(native)は Remote-SSH 経路を案内（WSLはRemote-WSL）
# 前提: Windowsに VS Code + 拡張 "WSL"(ローカル) / "Remote-SSH"(Azure)
# 使い方: ./22_setup_vscode.sh [--project <dir>] [--no-extensions] [--mode wsl|ssh|auto]
# =====================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then source "${SCRIPT_DIR}/lib/common.sh"; else
  log_step(){ echo "==> $*"; }; log_ok(){ echo "[OK] $*"; }; log_warn(){ echo "[WARN] $*"; }; log_err(){ echo "[ERR] $*" >&2; }
  has_cmd(){ command -v "$1" >/dev/null 2>&1; }
fi

PROJECT="."; DO_EXT=1; MODE="auto"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:-.}"; shift 2 ;;
    --no-extensions) DO_EXT=0; shift ;;
    --mode) MODE="${2:-auto}"; shift 2 ;;
    *) log_err "不明な引数: $1"; exit 10 ;;
  esac
done

# 接続モード判定（MECE是正: WSL=Remote-WSL / native=Remote-SSH）
if [[ "$MODE" == "auto" ]]; then
  if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then MODE="wsl"; else MODE="ssh"; fi
fi
log_step "VS Code 接続モード: ${MODE}  (wsl=Remote-WSL / ssh=Remote-SSH)"
if [[ "$MODE" == "ssh" ]]; then
  log_warn "Azure Ubuntu VM等はローカルWindows VS Codeから Remote-SSH で接続します。"
  log_warn "  Windows側: 拡張 'Remote - SSH'。~/.ssh/config にVMを登録し、"
  log_warn "  コマンドパレット → 'Remote-SSH: Connect to Host' で接続してください。"
fi

# --- 1) code CLI 確認 ---
if ! has_cmd code; then
  log_warn "WSL/VM内で 'code' が見つかりません。"
  log_warn "  WSL: Windowsに拡張'WSL'導入→WSLで一度 'code .'（Server自動配置）"
  log_warn "  SSH: Remote-SSH接続後、VM内で 'code' が使えるようになります"
else
  log_ok "code CLI: $(code --version | head -1)"
fi

# --- 2) 拡張一括導入 ---
EXTENSIONS=(
  ms-vscode-remote.remote-wsl ms-vscode-remote.remote-containers ms-vscode-remote.remote-ssh
  ms-azuretools.vscode-docker
  github.vscode-pull-request-github eamodio.gitlens
  ms-python.python ms-python.vscode-pylance charliermarsh.ruff
  redhat.vscode-yaml tamasfe.even-better-toml editorconfig.editorconfig
  ms-vscode.cpptools
)
if [[ "$DO_EXT" -eq 1 && $(command -v code || true) ]]; then
  log_step "VS Code 拡張を導入（latest）"
  for e in "${EXTENSIONS[@]}"; do code --install-extension "$e" --force >/dev/null 2>&1 && echo "  + $e" || echo "  ! $e (skip)"; done
  log_ok "拡張導入完了"
else
  log_warn "拡張導入スキップ（code未検出 or --no-extensions）"
fi

# --- 3) テンプレ配置 ---
TPL="${SCRIPT_DIR}/../vscode"; DC="${SCRIPT_DIR}/../devcontainer"
if [[ -d "$PROJECT" ]]; then
  log_step "テンプレ配置: $PROJECT"
  mkdir -p "${PROJECT}/.vscode" "${PROJECT}/.devcontainer"
  for f in settings.json extensions.json tasks.json launch.json; do
    if [[ -f "${TPL}/${f}" ]]; then
      if [[ -f "${PROJECT}/.vscode/${f}" ]]; then cp "${TPL}/${f}" "${PROJECT}/.vscode/${f}.sample"; echo "  = ${f} 既存→.sample";
      else cp "${TPL}/${f}" "${PROJECT}/.vscode/${f}"; echo "  + .vscode/${f}"; fi
    fi
  done
  if [[ -f "${DC}/devcontainer.json" ]]; then
    if [[ -f "${PROJECT}/.devcontainer/devcontainer.json" ]]; then cp "${DC}/devcontainer.json" "${PROJECT}/.devcontainer/devcontainer.json.sample"; echo "  = devcontainer.json→.sample";
    else cp "${DC}/devcontainer.json" "${PROJECT}/.devcontainer/devcontainer.json"; echo "  + .devcontainer/devcontainer.json"; fi
  fi
else
  log_warn "プロジェクト不在: $PROJECT"
fi

log_ok "22_setup_vscode.sh 完了 (mode=${MODE})"
[[ "$MODE" == "wsl" ]] && echo "  起動: cd ${PROJECT} && code ." || echo "  起動: Windows VS Code → Remote-SSH で接続後に開く"
