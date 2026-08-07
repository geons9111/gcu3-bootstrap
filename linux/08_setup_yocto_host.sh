#!/usr/bin/env bash
# =====================================================================
# GCU3 Bootstrap - Yocto ホスト依存 (08) v1.01  ※A55 Yoctoビルド時
# 方針:
#   - Yocto公式のホスト必須パッケージ + i.MX BSP補助ツール（latest）
#   - --enable-yocto 指定時のみ実行（00_bootstrap 経由）
#   - ディスク/RAM 目安を警告（Yoctoは大容量が必要）
# =====================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
warn_if_root
warn_if_windows_mount

log_step "Yocto ホスト必須パッケージ（latest）"
YOCTO_PKGS=(
  build-essential chrpath cpio debianutils diffstat file gawk gcc git
  iputils-ping libacl1 locales make
  python3 python3-git python3-jinja2 python3-pexpect python3-pip python3-subunit
  socat texinfo unzip wget xz-utils zstd lz4 liblz4-tool
)
apt_install "${YOCTO_PKGS[@]}"

log_step "i.MX BSP 補助ツール（latest / 任意）"
YOCTO_EXTRA=(
  u-boot-tools device-tree-compiler bmap-tools
  qemu-user-static binfmt-support ccache
)
apt_install "${YOCTO_EXTRA[@]}" || log_warn "一部BSP補助ツールの導入に失敗（後で個別導入可）"

log_step "locale(en_US.UTF-8) 確認"
if ! locale -a 2>/dev/null | grep -qi 'en_US.utf8'; then
  echo "en_US.UTF-8 UTF-8" | srun tee -a /etc/locale.gen >/dev/null
  srun locale-gen || true
fi

log_warn "Yoctoフルビルドの目安: 空きディスク 140GB以上 / RAM 32GB級 / 多コア推奨"
log_warn "作業ディレクトリは /home/\$USER 配下（/mnt/c は非推奨）"
log_ok "08_setup_yocto_host.sh 完了（latest）"
