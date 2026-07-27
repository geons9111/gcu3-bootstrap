#!/usr/bin/env bash
# =====================================================================
# GCU3 Bootstrap - Base 層 (01) v1.01
# 目的: 常時必須の Linux基本 / ファイル操作 / 調査 / 圧縮 / ビルド基礎ツール
# 方針:
#   - すべて apt latest（PINしない=自動更新可）
#   - apt-get upgrade は既定で行わない（--upgrade-system 指定時のみ）
# =====================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
warn_if_root

UPGRADE_SYSTEM="${UPGRADE_SYSTEM:-0}"

log_step "apt インデックス更新"
srun apt-get update -y

if [[ "$UPGRADE_SYSTEM" -eq 1 ]]; then
  log_step "システム全体アップグレード（--upgrade-system 指定）"
  srun apt-get upgrade -y
else
  log_warn "apt upgrade はスキップ（必要なら --upgrade-system）"
fi

log_step "Base 層パッケージ導入（latest）"
BASE_PKGS=(
  # --- 証明書 / 取得 / リポジトリ管理 ---
  ca-certificates curl wget gnupg lsb-release
  software-properties-common apt-transport-https
  # --- VCS ---
  git git-lfs openssh-client
  # --- ビルド基礎 ---
  build-essential pkg-config make cmake ninja-build patch
  # --- ファイル操作 / 調査（★tree 追加） ---
  tree file rsync dos2unix vim less jq
  # --- 圧縮 / 展開 ---
  unzip zip tar gzip bzip2 xz-utils p7zip-full zstd lz4
  # --- coreutils系（明示） ---
  findutils coreutils diffutils
  # --- ネットワーク調査 ---
  net-tools iproute2 iputils-ping dnsutils
  # --- 静的解析 / ロケール ---
  shellcheck locales tzdata
)
apt_install "${BASE_PKGS[@]}"

log_step "git-lfs 初期化"
run git lfs install || true

log_step "ロケール(en_US/ja_JP UTF-8) と TZ(Asia/Tokyo=大阪) 設定"
srun locale-gen en_US.UTF-8 ja_JP.UTF-8 || true
srun update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 || true
srun ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime || true
echo "Asia/Tokyo" | srun tee /etc/timezone >/dev/null || true

log_ok "01_setup_base.sh 完了（全て latest / 自動更新可）"
