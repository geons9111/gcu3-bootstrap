#!/usr/bin/env bash
# =====================================================================
# GCU3 Bootstrap - WSL2 systemd 有効化 (07) v1.01
# 方針(レビュー反映):
#   - 既に systemd 稼働なら何もしない（冪等）
#   - /etc/wsl.conf に [boot] systemd=true を設定
#   - 反映は Windows で `wsl --shutdown` → 再起動が必要
# =====================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/detect.sh"
warn_if_root

# v1.02: ネイティブLinux(Azure Ubuntu VM等)では wsl.conf 不要
if ! is_wsl; then
  log_ok "ネイティブLinux環境のため systemd 設定は不要（WSL専用処理をスキップ）"
  is_systemd && log_ok "systemd は稼働中" || log_warn "systemd が PID1 ではありません（環境要確認）"
  exit 0
fi

# 既に systemd が PID1 なら終了
if is_systemd; then
  log_ok "systemd は既に稼働中（変更不要）"
  exit 0
fi

WSLCONF=/etc/wsl.conf
log_step "現在の $WSLCONF"
srun test -f "$WSLCONF" && srun cat "$WSLCONF" || echo "  (未作成)"

if srun grep -qE '^\s*systemd\s*=\s*true' "$WSLCONF" 2>/dev/null; then
  log_warn "wsl.conf に systemd=true は設定済（未反映の可能性）"
else
  log_step "$WSLCONF に systemd=true を設定"
  if srun grep -q '^\[boot\]' "$WSLCONF" 2>/dev/null; then
    srun sed -i '/^\[boot\]/a systemd=true' "$WSLCONF"
  else
    { echo ""; echo "[boot]"; echo "systemd=true"; } | srun tee -a "$WSLCONF" >/dev/null
  fi
  log_ok "systemd=true を書き込み"
fi

echo ""
log_warn "反映手順（Windows PowerShell）:  wsl --shutdown"
log_warn "その後 Ubuntu を再起動してください。"
log_ok "07_enable_systemd.sh 完了"
