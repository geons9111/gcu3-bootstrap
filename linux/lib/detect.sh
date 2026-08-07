#!/usr/bin/env bash
# =====================================================================
# GCU3 Bootstrap - 環境検出ライブラリ (v1.02) ★新規
# 目的:
#   - WSL2 か ネイティブLinux(Azure VM等) かを自動判定
#   - Azure VM か（IMDS応答）を判定し、VMサイズ等を取得
#   - target(native|wsl|auto) の解決
# 使い方:
#   source lib/detect.sh
#   TARGET="$(resolve_target "$USER_TARGET")"   # native|wsl
# =====================================================================

# WSLか？（/proc/version に microsoft/WSL）
is_wsl() { grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; }

# systemd が PID1 か？
is_systemd() { [[ "$(ps -p 1 -o comm= 2>/dev/null)" == "systemd" ]]; }

# Azure VM か？（IMDS: 169.254.169.254 が Metadata応答するか）
# 失敗しても即NGにしない（Proxy/遮断環境を考慮し短いtimeout）
IMDS_BASE="http://169.254.169.254/metadata/instance"
IMDS_HDR="Metadata:true"
imds_get() {
  local path="$1"
  # no_proxy を強制してメタデータ直取得（Proxy経由を避ける）
  NO_PROXY="169.254.169.254" no_proxy="169.254.169.254" \
    curl -fsS -m 2 -H "$IMDS_HDR" \
    "${IMDS_BASE}${path}?api-version=2021-02-01&format=text" 2>/dev/null || true
}
is_azure_vm() {
  local v; v="$(imds_get "/compute/vmId")"
  [[ -n "$v" ]]
}
azure_vm_size() { imds_get "/compute/vmSize"; }
azure_location() { imds_get "/compute/location"; }

# target 解決: auto の場合は WSL検出で自動振り分け
#   is_wsl=yes -> wsl / no -> native
resolve_target() {
  local want="${1:-auto}"
  case "$want" in
    wsl|native) echo "$want"; return ;;
    auto|"")
      if is_wsl; then echo "wsl"; else echo "native"; fi ;;
    *) echo "auto_invalid"; return 1 ;;
  esac
}

# 環境サマリ表示
print_env_summary() {
  echo "---- Environment Detection (v1.02) ----"
  echo "  WSL           : $(is_wsl && echo yes || echo no)"
  echo "  systemd(PID1) : $(is_systemd && echo yes || echo no)"
  if is_azure_vm; then
    echo "  Azure VM      : yes"
    echo "    vmSize      : $(azure_vm_size)"
    echo "    location    : $(azure_location)"
  else
    echo "  Azure VM      : no (or IMDS unreachable)"
  fi
  echo "---------------------------------------"
}
