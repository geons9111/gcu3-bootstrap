#!/usr/bin/env bash
# =====================================================================
# GCU3 Bootstrap - 統括 (00) v1.02
# 対象: WSL2 Ubuntu 24.04 / Azure Ubuntu VM(ネイティブ) 両対応
# 4段階構成:
#   [必須] Base / Git / Docker / Python / Proxy / AutoUpdate
#   [任意] Yocto(--enable-yocto) / Embedded(--enable-embedded-tools)
#          / Optional(--enable-optional-tools)
# 使い方:
#   # WSL2（既定/自動判定）
#   ./00_bootstrap.sh --profile office-osaka
#   # Azure Ubuntu VM（ネイティブ・CI/Build）
#   ./00_bootstrap.sh --profile azure-vm --target native
# 主なオプション:
#   --target <t>            wsl | native | auto(既定)。autoはWSL検出で自動振分
#   --profile <name>        Proxy profile (office-osaka|home-squid|azure-vm|direct)
#   --python-version <v>    system(既定,3.12) | deadsnakes-3.11
#   --upgrade-system        apt-get upgrade も実行（既定は行わない）
#   --no-autoupdate         自動更新(06)を入れない
#   --auto-update-scope <s> security(既定) | all
#   --enable-yocto          Yoctoホスト依存(08)
#   --enable-embedded-tools M7/M33ツール(09)
#   --enable-optional-tools 運用/利便ツール(10)
#   --skip-docker / --skip-python
#   --dry-run               実行せずコマンド表示
# =====================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/versions.sh"
source "${SCRIPT_DIR}/lib/detect.sh"

PROFILE=""
USER_TARGET="auto"
ENABLE_YOCTO=0; ENABLE_EMB=0; ENABLE_OPT=0
SKIP_DOCKER=0; SKIP_PYTHON=0
export DRY_RUN=0 UPGRADE_SYSTEM=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) USER_TARGET="${2:-}"; shift 2 ;;
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --python-version) export PIN_PYTHON="${2:-}"; shift 2 ;;
    --upgrade-system) export UPGRADE_SYSTEM=1; shift ;;
    --no-autoupdate) export AUTO_UPDATE=0; shift ;;
    --auto-update-scope) export AUTO_UPDATE_SCOPE="${2:-}"; shift 2 ;;
    --enable-yocto) ENABLE_YOCTO=1; shift ;;
    --enable-embedded-tools) ENABLE_EMB=1; shift ;;
    --enable-optional-tools) ENABLE_OPT=1; shift ;;
    --skip-docker) SKIP_DOCKER=1; shift ;;
    --skip-python) SKIP_PYTHON=1; shift ;;
    --dry-run) export DRY_RUN=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_err "不明な引数: $1"; exit 10 ;;
  esac
done

# target 解決（auto は WSL検出で native/wsl に振分）
TARGET="$(resolve_target "$USER_TARGET")"
if [[ "$TARGET" == "auto_invalid" ]]; then
  log_err "不正な --target: $USER_TARGET （wsl|native|auto）"; exit 10
fi
export TARGET

LOG="$(log_file)"
log_step "GCU3 Bootstrap v1.02 開始 (profile=${PROFILE:-未指定} / target=${TARGET}) → log: $LOG"
print_version_policy | tee -a "$LOG"
print_env_summary 2>&1 | tee -a "$LOG"
require_ubuntu_env "$TARGET" 2>&1 | tee -a "$LOG"
warn_if_windows_mount

# Azure VM 検出時の案内（profile未指定なら azure-vm を推奨）
if is_azure_vm; then
  log_step "Azure VM を検出（vmSize=$(azure_vm_size)）"
  if [[ -z "$PROFILE" ]]; then
    log_warn "profile未指定。Azure VMでは --profile azure-vm を推奨します。"
  fi
fi

# --- 0) systemd 前提（target別） ---
if [[ "$TARGET" == "wsl" ]]; then
  if ! is_systemd; then
    log_warn "WSLでsystemd未稼働。Docker/自動更新のため 07_enable_systemd.sh → 'wsl --shutdown' → 再起動 を先に実施してください。"
  fi
else
  # native(Azure Ubuntu VM等)は最初からsystemd想定
  is_systemd || log_warn "native環境ですが systemd が PID1 ではありません（環境要確認）"
fi

# --- 0) Proxy（profile指定時） ---
if [[ -n "$PROFILE" ]]; then
  log_step "[Proxy] profile=${PROFILE}"
  bash "${SCRIPT_DIR}/05_setup_proxy.sh" --profile "$PROFILE" 2>&1 | tee -a "$LOG"
else
  log_warn "profile未指定: Proxy設定なし（直結想定）"
fi

# --- 1) Base（必須） ---
bash "${SCRIPT_DIR}/01_setup_base.sh" 2>&1 | tee -a "$LOG"

# --- 2) Git（必須） ---
bash "${SCRIPT_DIR}/02_setup_git.sh" 2>&1 | tee -a "$LOG"

# --- 3) Docker（必須・skip可） ---
if [[ "$SKIP_DOCKER" -eq 0 ]]; then
  bash "${SCRIPT_DIR}/03_setup_docker.sh" 2>&1 | tee -a "$LOG"
else
  log_warn "Docker導入をスキップ"
fi

# --- 4) Python（必須・skip可） ---
if [[ "$SKIP_PYTHON" -eq 0 ]]; then
  bash "${SCRIPT_DIR}/04_setup_python.sh" 2>&1 | tee -a "$LOG"
else
  log_warn "Python導入をスキップ"
fi

# --- 6) 自動更新（既定ON） ---
bash "${SCRIPT_DIR}/06_setup_autoupdate.sh" 2>&1 | tee -a "$LOG"

# --- 8) Yocto（任意） ---
if [[ "$ENABLE_YOCTO" -eq 1 ]]; then
  bash "${SCRIPT_DIR}/08_setup_yocto_host.sh" 2>&1 | tee -a "$LOG"
fi

# --- 9) Embedded（任意） ---
if [[ "$ENABLE_EMB" -eq 1 ]]; then
  bash "${SCRIPT_DIR}/09_setup_embedded_tools.sh" 2>&1 | tee -a "$LOG"
fi

# --- 10) Optional（任意） ---
if [[ "$ENABLE_OPT" -eq 1 ]]; then
  bash "${SCRIPT_DIR}/10_setup_optional_tools.sh" 2>&1 | tee -a "$LOG"
fi

# --- 11) 検証 ---
bash "${SCRIPT_DIR}/11_verify.sh" 2>&1 | tee -a "$LOG" || true

log_ok "Bootstrap 完了 (target=${TARGET} / log: $LOG)"
echo ""
echo "====================================================================="
echo " 次の手順 (target=${TARGET})"
echo "====================================================================="
echo " 1) docker グループ反映（再ログイン相当）:  newgrp docker"
echo " 2) 動作確認: docker run --rm hello-world / python3 --version / git --version"
if [[ "$TARGET" == "wsl" ]]; then
  echo "    ※ docker/timer が動かない場合: 07_enable_systemd.sh → 'wsl --shutdown' → 再起動"
else
  echo "    ※ native(Azure VM等): systemd は既定稼働。07は不要"
fi
echo " 3) GCU3 Orchestrator:"
echo "      git clone <repo-url> gcu3-devplat && cd gcu3-devplat"
echo "      python3 -m venv .venv && source .venv/bin/activate"
echo "      python -m pip install --upgrade pip setuptools wheel"
echo "      pip install -e . && orc --help"
echo " 4) 自動更新は週次で稼働（手動: sudo /usr/local/bin/gcu3-selfupdate）"
echo "====================================================================="
