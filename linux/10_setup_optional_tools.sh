#!/usr/bin/env bash
# =====================================================================
# GCU3 Bootstrap - 開発利便/運用ツール (10) v1.01  ※任意
# 方針:
#   - ビルド監視/容量調査/検索/セッション維持などの便利ツール（latest）
#   - --enable-optional-tools 指定時のみ実行
# =====================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
warn_if_root

log_step "運用・調査・利便ツール（latest）"
OPT_PKGS=(
  htop ncdu iotop lsof strace tmux
  ripgrep fd-find bat
)
apt_install "${OPT_PKGS[@]}" || log_warn "一部ツール導入失敗（環境により未提供の場合あり）"

# Ubuntu では bat/fd はコマンド名が batcat/fdfind。エイリアス補助（任意）
BASHRC="${HOME}/.bashrc"
if [[ -f "$BASHRC" ]]; then
  append_once "alias bat='batcat'" "$BASHRC" 2>/dev/null || true
  append_once "alias fd='fdfind'"  "$BASHRC" 2>/dev/null || true
fi

log_ok "10_setup_optional_tools.sh 完了（latest）"
