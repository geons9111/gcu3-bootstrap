#!/usr/bin/env bash
# =====================================================================
# GCU3 Bootstrap - Python (04) v1.01
# 方針(レビュー反映):
#   - 既定は Ubuntu 24.04 標準 Python3.12（system）= 第三者PPA不要
#   - 3.11 が必須の場合のみ PIN_PYTHON=deadsnakes-3.11（社内承認前提）
#   - 開発ツール(ruff/mypy/pre-commit/yamllint)は pipx で latest 管理
#   - プロジェクト依存は各自 venv（システムに入れない）
# =====================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/versions.sh"
warn_if_root

log_step "Python ポリシー: PIN_PYTHON=${PIN_PYTHON}"

if [[ "$PIN_PYTHON" == "system" ]]; then
  log_step "Ubuntu標準 Python3(3.12) と venv/pip/pipx（latest）"
  apt_install python3 python3-venv python3-dev python3-pip \
              python3-setuptools python3-wheel pipx
  PYBIN="python3"
elif [[ "$PIN_PYTHON" == "deadsnakes-3.11" ]]; then
  log_warn "deadsnakes PPA で Python3.11 を導入（社内セキュリティ承認前提）"
  srun add-apt-repository -y ppa:deadsnakes/ppa
  srun apt-get update -y
  apt_install python3.11 python3.11-venv python3.11-dev pipx
  PYBIN="python3.11"
  log_warn "システムの python3 は切り替えません（/usr/bin/python3 は 3.12 のまま）"
else
  log_err "未知の PIN_PYTHON=$PIN_PYTHON （system|deadsnakes-3.11）"; exit 10
fi

log_step "使用Python: $($PYBIN --version 2>&1)"

log_step "pipx パス整備"
run "$PYBIN" -m pipx ensurepath || true

log_step "開発ツールを pipx で導入（latest / 自動更新対象）"
# PIPX_TOOLS は versions.sh 定義（ruff/mypy/pre-commit/yamllint）
for t in "${PIPX_TOOLS[@]}"; do
  if has_cmd "$t"; then
    log_warn "$t 既存（pipx upgrade で最新化可）"
  else
    run pipx install "$t" || run "$PYBIN" -m pip install --user "$t"
  fi
done

log_ok "04_setup_python.sh 完了（PIN_PYTHON=${PIN_PYTHON} / tools=latest）"
cat <<EON
  プロジェクトは venv 利用を推奨:
    ${PYBIN} -m venv .venv && source .venv/bin/activate
    python -m pip install --upgrade pip setuptools wheel
    pip install -e .
EON
