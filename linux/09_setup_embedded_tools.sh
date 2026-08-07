#!/usr/bin/env bash
# =====================================================================
# GCU3 Bootstrap - 組込み(M7/M33)ツール (09) v1.01  ※条件付き
# 方針:
#   - 汎用のクロス開発/デバッグ/実機接続ツールのみ apt latest で導入
#   - ベンダーSDK(MCUXpresso/NXP SDK/J-Link/TRACE32等)は本スクリプト対象外
#     （ライセンス/USBドライバ/配布元が個別のため別インストーラ化）
#   - --enable-embedded-tools 指定時のみ実行
# =====================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
warn_if_root

log_step "M7/M33 クロス開発・デバッグ（latest）"
EMB_PKGS=(
  gcc-arm-none-eabi gdb-multiarch openocd
  cmake ninja-build
)
apt_install "${EMB_PKGS[@]}" || log_warn "一部クロスツール導入失敗（後で個別導入可）"

log_step "実機接続 / UART 確認（latest）"
HW_PKGS=(
  usbutils pciutils minicom picocom screen
)
apt_install "${HW_PKGS[@]}" || true

log_warn "ベンダーツールは別管理: MCUXpresso / NXP SDK / J-Link / TRACE32 等"
log_warn "  → ライセンス・対応Ubuntu・USBドライバ・社内配布元を確認して個別導入"
log_ok "09_setup_embedded_tools.sh 完了（latest）"
