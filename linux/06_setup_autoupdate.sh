#!/usr/bin/env bash
# =====================================================================
# GCU3 Bootstrap - OSS/バージョン 自動更新 (06) v1.01  ★新規
# 目的（新要件）:
#   - OSS/ツールを「最初から自動更新できる」状態にする
#   - Phase1既定: セキュリティ更新を自動（unattended-upgrades）
#   - apt / pipx / Docker を週次で更新する systemd timer を設置
# 方針:
#   - PIN しないもの（latest運用）は自動更新対象
#   - Python(system=3.12) の system 更新は Ubuntu 管理に委ねる
# 制御:
#   AUTO_UPDATE=1(既定) / AUTO_UPDATE_SCOPE=security|all (versions.sh)
# =====================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/versions.sh"
warn_if_root

if [[ "${AUTO_UPDATE}" != "1" ]]; then
  log_warn "AUTO_UPDATE=0 のため自動更新は設定しません"
  exit 0
fi

# ---------------------------------------------------------------------
# 1) unattended-upgrades（apt セキュリティ自動更新）
# ---------------------------------------------------------------------
log_step "unattended-upgrades / update-notifier-common 導入（latest）"
apt_install unattended-upgrades apt-listchanges update-notifier-common

log_step "自動更新スコープ設定: ${AUTO_UPDATE_SCOPE}"
AUTO50=/etc/apt/apt.conf.d/50unattended-upgrades
AUTO20=/etc/apt/apt.conf.d/20auto-upgrades

if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
  echo "  (dry-run) configure ${AUTO50} / ${AUTO20} (scope=${AUTO_UPDATE_SCOPE})"
else
  # 20auto-upgrades: 定期実行を有効化
  sudo tee "$AUTO20" >/dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF

  # 50unattended-upgrades: 許可originを設定
  if [[ "$AUTO_UPDATE_SCOPE" == "all" ]]; then
    ORIGINS='        "${distro_id}:${distro_codename}";
        "${distro_id}:${distro_codename}-updates";
        "${distro_id}:${distro_codename}-security";
        "${distro_id}ESMApps:${distro_codename}-apps-security";
        "${distro_id}ESM:${distro_codename}-infra-security";'
  else
    # security 既定
    ORIGINS='        "${distro_id}:${distro_codename}-security";
        "${distro_id}ESMApps:${distro_codename}-apps-security";
        "${distro_id}ESM:${distro_codename}-infra-security";'
  fi

  sudo tee "$AUTO50" >/dev/null <<EOF
Unattended-Upgrade::Allowed-Origins {
${ORIGINS}
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
fi

# WSLではsystemd有効時に apt-daily.timer が有効化される
if pidof systemd >/dev/null 2>&1; then
  srun systemctl enable --now unattended-upgrades.service 2>/dev/null || true
  srun systemctl enable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
fi

# ---------------------------------------------------------------------
# 2) GCU3 週次更新（apt/pipx/docker prune）を systemd timer で設置
# ---------------------------------------------------------------------
log_step "週次更新スクリプトと systemd timer を設置"
UPDATER=/usr/local/bin/gcu3-selfupdate
if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
  echo "  (dry-run) install ${UPDATER} + gcu3-update.service/.timer"
else
  sudo tee "$UPDATER" >/dev/null <<'EOF'
#!/usr/bin/env bash
# GCU3 週次更新: apt(更新一覧/自動更新は unattended 側) + pipx + docker prune
set -Eeuo pipefail
LOG="${HOME:-/root}/.gcu3-bootstrap/logs/selfupdate-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
{
  echo "== gcu3-selfupdate $(date -Is) =="
  echo "-- apt update --"
  sudo apt-get update -y || true
  echo "-- pipx upgrade-all (ruff/mypy/pre-commit/yamllint 等) --"
  if command -v pipx >/dev/null 2>&1; then pipx upgrade-all || true; fi
  echo "-- docker system prune (dangling) --"
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    docker image prune -f || true
  fi
  echo "== done =="
} | tee -a "$LOG"
EOF
  sudo chmod +x "$UPDATER"

  sudo tee /etc/systemd/system/gcu3-update.service >/dev/null <<EOF
[Unit]
Description=GCU3 weekly OSS/tools self-update
[Service]
Type=oneshot
User=${USER}
ExecStart=${UPDATER}
EOF

  sudo tee /etc/systemd/system/gcu3-update.timer >/dev/null <<'EOF'
[Unit]
Description=Run GCU3 self-update weekly
[Timer]
OnCalendar=weekly
Persistent=true
[Install]
WantedBy=timers.target
EOF
fi

if pidof systemd >/dev/null 2>&1; then
  srun systemctl daemon-reload || true
  srun systemctl enable --now gcu3-update.timer 2>/dev/null || true
  log_ok "gcu3-update.timer 有効化（週次）"
else
  log_warn "systemd 無効のため timer は未起動。07_enable_systemd.sh 後に有効化されます。"
  log_warn "手動更新は: ${UPDATER}"
fi

log_ok "06_setup_autoupdate.sh 完了（scope=${AUTO_UPDATE_SCOPE} / OSS=latest自動更新）"
