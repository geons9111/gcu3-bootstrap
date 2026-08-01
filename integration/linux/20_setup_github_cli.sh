#!/usr/bin/env bash
# =====================================================================
# GCU3 Integration - GitHub CLI + SSH連携 (20) v1.1
# 目的: gh 導入 → ed25519鍵 → gh認証(SSH) → 公開鍵登録 → 接続確認
# MECE是正:
#   - gh手順はここに一本化（統括/別ガイドからは本スクリプトを参照）
#   - Proxy環境の事前設定を明記
# 使い方:
#   ./20_setup_github_cli.sh [--email you@kubota.com] [--host github.com] [--no-auth]
# =====================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then source "${SCRIPT_DIR}/lib/common.sh"; else
  log_step(){ echo "==> $*"; }; log_ok(){ echo "[OK] $*"; }; log_warn(){ echo "[WARN] $*"; }; log_err(){ echo "[ERR] $*" >&2; }
  run(){ if [[ "${DRY_RUN:-0}" -eq 1 ]]; then echo "  (dry-run) $*"; else "$@"; fi; }
  srun(){ if [[ "${DRY_RUN:-0}" -eq 1 ]]; then echo "  (dry-run) sudo $*"; else sudo "$@"; fi; }
  has_cmd(){ command -v "$1" >/dev/null 2>&1; }
fi

EMAIL="${GITHUB_EMAIL:-}"; HOST="github.com"; DO_AUTH=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --email) EMAIL="${2:-}"; shift 2 ;;
    --host)  HOST="${2:-github.com}"; shift 2 ;;
    --no-auth) DO_AUTH=0; shift ;;
    *) log_err "不明な引数: $1"; exit 10 ;;
  esac
done

# Proxy環境ヒント（漏れ是正）
if [[ -n "${HTTP_PROXY:-${http_proxy:-}}" ]]; then
  log_step "Proxy検出: ${HTTP_PROXY:-$http_proxy}（gh/git はこのProxyを使用）"
else
  log_warn "Proxy未設定。社内環境では 'export HTTPS_PROXY=...' を先に設定してください。"
fi

# --- 1) gh 導入（公式apt / latest） ---
if has_cmd gh; then
  log_warn "gh 既存: $(gh --version | head -1)"
else
  log_step "GitHub CLI 公式リポジトリ登録"
  srun install -m 0755 -d /etc/apt/keyrings
  run bash -c 'curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null'
  srun chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  ARCH="$(dpkg --print-architecture)"
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | srun tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  srun apt-get update -y
  srun apt-get install -y gh
  log_ok "gh 導入: $(gh --version | head -1)"
fi

# --- 2) SSH鍵(ed25519) ---
SSH_DIR="${HOME}/.ssh"; KEY="${SSH_DIR}/id_ed25519"
mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"
if [[ -f "$KEY" ]]; then log_warn "SSH鍵 既存: $KEY"; else
  log_step "SSH鍵(ed25519)生成（パスフレーズ推奨）"
  run ssh-keygen -t ed25519 -C "${EMAIL:-gcu3-dev}" -f "$KEY"
  chmod 600 "$KEY" 2>/dev/null || true; chmod 644 "$KEY.pub" 2>/dev/null || true
fi

# --- 3) known_hosts 登録 ---
log_step "known_hosts に ${HOST} 登録"
if ! ssh-keygen -F "$HOST" >/dev/null 2>&1; then
  run bash -c "ssh-keyscan -t ed25519 ${HOST} >> ${SSH_DIR}/known_hosts 2>/dev/null"
fi

# --- 4) ssh-agent（現shell） ---
if [[ "${DRY_RUN:-0}" -ne 1 ]]; then
  eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
  ssh-add "$KEY" 2>/dev/null || log_warn "ssh-add はパスフレーズ入力が必要な場合があります"
fi

# --- 5) gh 認証 + 鍵登録 ---
if [[ "$DO_AUTH" -eq 1 ]]; then
  log_step "gh 認証(SSH/web) + 公開鍵登録（host=${HOST}）"
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    echo "  (dry-run) gh auth login -p ssh -h ${HOST} -w"
    echo "  (dry-run) gh ssh-key add ${KEY}.pub -t gcu3-wsl"
  else
    gh auth login -p ssh -h "$HOST" -w || log_warn "gh auth login 失敗/スキップ（後で手動可）"
    if gh auth status >/dev/null 2>&1; then
      gh ssh-key add "${KEY}.pub" -t "gcu3-$(hostname)" 2>/dev/null || log_warn "鍵登録は既存/権限により省略"
      gh config set git_protocol ssh 2>/dev/null || true
    fi
  fi
else
  log_warn "--no-auth: gh認証スキップ（公開鍵を手動登録してください）"
fi

echo ""
[[ -f "$KEY.pub" ]] && { echo "----- 公開鍵（手動登録時: GitHub Settings>SSH keys） -----"; cat "$KEY.pub"; echo "----------------------------------------------------------"; }
log_ok "20_setup_github_cli.sh 完了"
echo "  接続確認: ssh -T git@${HOST}"
