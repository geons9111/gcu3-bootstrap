#!/usr/bin/env bash
# =====================================================================
# GCU3 DevPlatform Bootstrap - 共通ライブラリ (v1.01)
# 全セットアップスクリプトから source して使用する
# =====================================================================

# ---- ログ ----
_c_cyan='\033[0;36m'; _c_green='\033[0;32m'; _c_yellow='\033[0;33m'; _c_red='\033[0;31m'; _c_off='\033[0m'
log_step() { echo -e "${_c_cyan}==> $*${_c_off}"; }
log_ok()   { echo -e "${_c_green}[OK] $*${_c_off}"; }
log_warn() { echo -e "${_c_yellow}[WARN] $*${_c_off}"; }
log_err()  { echo -e "${_c_red}[ERR] $*${_c_off}" >&2; }

# ---- ログファイル（証跡） ----
BOOTSTRAP_LOG_DIR="${BOOTSTRAP_LOG_DIR:-${HOME}/.gcu3-bootstrap/logs}"
mkdir -p "$BOOTSTRAP_LOG_DIR" 2>/dev/null || true
log_file() { echo "${BOOTSTRAP_LOG_DIR}/bootstrap-$(date +%Y%m%d-%H%M%S).log"; }

# ---- 実行ヘルパ（--dry-run 対応） ----
run() {
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then echo "  (dry-run) $*"; else "$@"; fi
}
srun() {
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then echo "  (dry-run) sudo $*"; else sudo "$@"; fi
}

# ---- 冪等ヘルパ ----
has_cmd() { command -v "$1" >/dev/null 2>&1; }
append_once() { local line="$1" file="$2"; grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"; }

# ---- apt 導入（存在チェック＋一括） ----
apt_install() {
  # 使い方: apt_install "${PKGS[@]}"
  local pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  srun apt-get install -y --no-install-recommends "${pkgs[@]}"
}

# ---- 環境前提チェック ----
# v1.02: target(native|wsl) を受け取り、native時はWSL警告を出さない
require_ubuntu_env() {
  local target="${1:-auto}"
  log_step "実行環境を確認 (target=${target})"
  local is_wsl=0
  grep -qiE "microsoft|wsl" /proc/version 2>/dev/null && is_wsl=1

  case "$target" in
    wsl)
      [[ "$is_wsl" -eq 1 ]] || log_warn "target=wsl ですが WSL として検出できません。" ;;
    native)
      [[ "$is_wsl" -eq 1 ]] && log_warn "target=native ですが WSL 上で実行中のようです。" \
        || echo "  ネイティブLinux(Azure VM等)として実行" ;;
    *)
      [[ "$is_wsl" -eq 1 ]] && echo "  WSL を検出" || echo "  ネイティブLinuxを検出" ;;
  esac

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "  Distro : ${PRETTY_NAME:-unknown}"
    UBUNTU_CODENAME_DETECTED="${VERSION_CODENAME:-noble}"
    if [[ "${ID:-}" != "ubuntu" ]]; then
      log_warn "Ubuntu以外を検出（${ID:-unknown}）。本ツールはUbuntu 24.04(noble)想定です。"
    fi
    if [[ "${VERSION_ID:-}" != "24.04" ]]; then
      log_warn "Ubuntu 24.04 以外（${VERSION_ID:-unknown}）を検出。動作は自己責任で。"
    fi
  fi
  echo "  Kernel : $(uname -r)"
}
# 後方互換
require_wsl2_ubuntu() { require_ubuntu_env "wsl"; }

warn_if_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    log_warn "root で実行中です。一般ユーザー + sudo を推奨します。"
  fi
}

warn_if_windows_mount() {
  # WSLで /mnt/c 配下に置くとI/Oが遅くYocto等で不利
  case "$(pwd)" in
    /mnt/*)
      log_warn "現在のディレクトリが Windows マウント($(pwd)) 上です。"
      log_warn "性能のため作業は /home/\$USER 配下を推奨します（Yocto/Docker で顕著）。"
      ;;
  esac
}

export DEBIAN_FRONTEND=noninteractive
