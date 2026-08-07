#!/usr/bin/env bash
# =====================================================================
# GCU3 DevPlatform Bootstrap - バージョン定義 / 管理 (v1.01)
# 方針:
#   - OSS・開発ツールは「原則 latest（自動更新可）」を既定とする
#   - 互換要件があるものだけ PIN（固定）する
#   - Phase1 では固定ポリシーを最小限にし、更新を止めない
# 使い方:
#   source lib/versions.sh
#   echo "$PIN_PYTHON"   # 例: system (=Ubuntu標準3.12)
# =====================================================================

# ---------------------------------------------------------------------
# [1] PIN が必要な要素（互換性のため固定/範囲指定）
# ---------------------------------------------------------------------
# Python: Ubuntu 24.04 標準の system(3.12) を既定。
#   GCU3 Orchestrator は pyproject.toml で ">=3.12,<3.13" を要求する想定。
#   3.11 が絶対要件の場合のみ PIN_PYTHON=deadsnakes-3.11 を選択（社内承認前提）。
PIN_PYTHON="${PIN_PYTHON:-system}"     # system | deadsnakes-3.11

# Ubuntu ディストロ: bootstrap は 24.04(noble) 前提
PIN_UBUNTU_CODENAME="${PIN_UBUNTU_CODENAME:-noble}"

# ---------------------------------------------------------------------
# [2] latest で問題ない要素（自動更新対象・PIN しない）
#   下記は「apt / 公式リポジトリの最新」を使う。バージョン固定しない。
#   → OSS/ツールのセキュリティ更新を最初から自動で受けられる。
# ---------------------------------------------------------------------
# 参考: これらは latest 運用（記録目的の一覧。実際の固定はしない）
LATEST_OK_TOOLS=(
  "git"            # latest
  "git-lfs"        # latest
  "docker-ce"      # latest (Docker公式repo)
  "docker-compose-plugin" # latest
  "docker-buildx-plugin"  # latest
  "cmake"          # latest
  "ninja-build"    # latest
  "ruff"           # latest (pipx)
  "mypy"           # latest (pipx)
  "pytest"         # latest (venv)
  "pre-commit"     # latest (pipx)
  "yamllint"       # latest (pipx)
  "tree" "jq" "rsync" "shellcheck"  # latest
)

# ---------------------------------------------------------------------
# [3] pipx で管理する「常に最新へ更新」対象ツール
#   06_setup_autoupdate.sh から定期更新できるように一覧化。
# ---------------------------------------------------------------------
PIPX_TOOLS=(
  "ruff"
  "mypy"
  "pre-commit"
  "yamllint"
)

# ---------------------------------------------------------------------
# [4] 自動更新ポリシー
#   AUTO_UPDATE=1: unattended-upgrades + 週次 apt/pipx 更新を有効化（既定）
#   AUTO_UPDATE=0: 自動更新を入れない
# ---------------------------------------------------------------------
AUTO_UPDATE="${AUTO_UPDATE:-1}"

# 自動更新の対象範囲（Phase1既定）
#   security : セキュリティ更新のみ自動（推奨・既定）
#   all      : 通常更新も自動（検証環境向け）
AUTO_UPDATE_SCOPE="${AUTO_UPDATE_SCOPE:-security}"

print_version_policy() {
  echo "---- Version / Update Policy (v1.01) ----"
  echo "  Python           : ${PIN_PYTHON}  (system=Ubuntu24.04標準3.12)"
  echo "  Ubuntu codename  : ${PIN_UBUNTU_CODENAME}"
  echo "  OSS/tools        : latest (PINしない=自動更新可)"
  echo "  pipx auto-update : ${PIPX_TOOLS[*]}"
  echo "  AUTO_UPDATE      : ${AUTO_UPDATE} (scope=${AUTO_UPDATE_SCOPE})"
  echo "-----------------------------------------"
}
