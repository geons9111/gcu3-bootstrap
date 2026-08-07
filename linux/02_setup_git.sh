#!/usr/bin/env bash
# =====================================================================
# GCU3 Bootstrap - Git 設定 (02) v1.01
# 変更点(レビュー反映):
#   - 対話入力を廃止し、引数/環境変数で非対話に
#   - SSH鍵生成は --generate-ssh-key 指定時のみ（既定は生成しない）
#   - credential.helper は明示指定時のみ
# 使い方:
#   ./02_setup_git.sh --name "Gunhwa Geon" --email "gunhwa_geon@kubota.com" \
#                     [--auth-mode ssh|https] [--generate-ssh-key]
# =====================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
warn_if_root

GIT_NAME="${GIT_USER_NAME:-}"
GIT_EMAIL="${GIT_USER_EMAIL:-}"
AUTH_MODE="${GIT_AUTH_MODE:-}"
GEN_SSH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) GIT_NAME="${2:-}"; shift 2 ;;
    --email) GIT_EMAIL="${2:-}"; shift 2 ;;
    --auth-mode) AUTH_MODE="${2:-}"; shift 2 ;;
    --generate-ssh-key) GEN_SSH=1; shift ;;
    *) log_err "不明な引数: $1"; exit 10 ;;
  esac
done

has_cmd git || { srun apt-get update -y && apt_install git git-lfs; }
log_step "git: $(git --version)（latest 運用）"

# name/email は非対話。未指定なら既存設定を尊重し、無ければ警告のみ
[[ -n "$GIT_NAME"  ]] && run git config --global user.name  "$GIT_NAME"
[[ -n "$GIT_EMAIL" ]] && run git config --global user.email "$GIT_EMAIL"
if [[ -z "$(git config --global user.name || true)" ]]; then
  log_warn "git user.name 未設定（--name で指定可）"
fi
if [[ -z "$(git config --global user.email || true)" ]]; then
  log_warn "git user.email 未設定（--email で指定可）"
fi

log_step "git 推奨既定（冪等）"
run git config --global init.defaultBranch main
run git config --global pull.rebase false
run git config --global core.autocrlf input
run git config --global core.editor "vim"
run git config --global color.ui auto
run git config --global fetch.prune true
run git config --global core.fileMode false
run git lfs install || true

# 認証ヘルパは明示時のみ
case "$AUTH_MODE" in
  https)
    run git config --global credential.helper "cache --timeout=3600"
    log_ok "auth-mode=https: credential.helper=cache を設定" ;;
  ssh|"")
    log_warn "credential.helper は設定しません（SSH鍵または各自設定を利用）" ;;
  *) log_warn "未知の --auth-mode=$AUTH_MODE（無視）" ;;
esac

# SSH鍵は明示時のみ生成（パスフレーズは対話で促す）
if [[ "$GEN_SSH" -eq 1 ]]; then
  SSH_DIR="${HOME}/.ssh"; KEY="${SSH_DIR}/id_ed25519"
  mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"
  if [[ -f "$KEY" ]]; then
    log_warn "SSH鍵は既に存在: $KEY（生成スキップ）"
  else
    log_step "SSH鍵(ed25519)を生成（パスフレーズ入力を推奨）"
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
      echo "  (dry-run) ssh-keygen -t ed25519 -C \"${GIT_EMAIL:-gcu3}\" -f $KEY"
    else
      ssh-keygen -t ed25519 -C "${GIT_EMAIL:-gcu3}" -f "$KEY"
      chmod 600 "$KEY"; chmod 644 "$KEY.pub"
    fi
  fi
  [[ -f "$KEY.pub" ]] && { echo "----- 公開鍵（社内Git/GitHubへ登録） -----"; cat "$KEY.pub"; echo "-----------------------------------------"; }
else
  log_warn "SSH鍵は生成しません（必要時 --generate-ssh-key）"
fi

log_ok "02_setup_git.sh 完了"
