#!/usr/bin/env bash
# =====================================================================
# GCU3 Bootstrap - Docker Engine (03) v1.01
# 方針:
#   - Docker公式aptリポジトリから latest を導入（Desktop非依存）
#   - ログローテーション(local, max-size/max-file)を daemon.json に設定
#   - グループ反映後の hello-world は本スクリプトでは実行しない
#     （再ログイン/newgrp が必要なため 11_verify.sh で判定）
# 参考: Docker公式 install / post-install 手順に準拠
# =====================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
warn_if_root

log_step "既存Docker確認"
has_cmd docker && log_warn "docker 既存: $(docker --version 2>/dev/null || true)"

log_step "競合パッケージ除去（存在時のみ）"
for p in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  dpkg -l "$p" >/dev/null 2>&1 && srun apt-get remove -y "$p" || true
done

log_step "Docker公式GPG鍵を登録"
srun install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
  run bash -c 'curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null'
  srun chmod a+r /etc/apt/keyrings/docker.asc
fi

log_step "Dockerリポジトリ追加"
ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-noble}")"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
  | srun tee /etc/apt/sources.list.d/docker.list >/dev/null

log_step "Docker Engine + Compose + Buildx 導入（latest）"
srun apt-get update -y
apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log_step "daemon.json: ログローテーション設定"
srun mkdir -p /etc/docker
DAEMON=/etc/docker/daemon.json
if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
  echo "  (dry-run) write $DAEMON (log-driver=local, max-size=10m, max-file=3)"
else
  sudo tee "$DAEMON" >/dev/null <<'JSON'
{
  "log-driver": "local",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
JSON
fi

log_step "docker グループへユーザー追加"
getent group docker >/dev/null || srun groupadd docker || true
srun usermod -aG docker "$USER" || true

# dockerd 用 Proxy（systemd 稼働かつ Proxy 環境変数がある場合のみ）
if pidof systemd >/dev/null 2>&1; then
  if [[ -n "${HTTP_PROXY:-${http_proxy:-}}" ]]; then
    log_step "dockerd Proxy drop-in 作成"
    DROPIN=/etc/systemd/system/docker.service.d
    srun mkdir -p "$DROPIN"
    NP="${NO_PROXY:-localhost,127.0.0.1,::1,.kubota.co.jp,172.17.0.0/16}"
    {
      echo "[Service]"
      echo "Environment=\"HTTP_PROXY=${HTTP_PROXY:-$http_proxy}\""
      [[ -n "${HTTPS_PROXY:-${https_proxy:-}}" ]] && echo "Environment=\"HTTPS_PROXY=${HTTPS_PROXY:-$https_proxy}\""
      echo "Environment=\"NO_PROXY=${NP}\""
    } | srun tee "${DROPIN}/http-proxy.conf" >/dev/null
    srun systemctl daemon-reload || true
  fi
  log_step "docker 有効化/再起動"
  srun systemctl enable docker || true
  srun systemctl restart docker || true
else
  log_warn "systemd 無効。07_enable_systemd.sh 実行 → wsl --shutdown 後に再起動してください。"
  srun service docker start || true
fi

log_ok "03_setup_docker.sh 完了（latest）"
log_warn "docker グループ反映には 再ログイン または 'newgrp docker' が必要（検証は 11_verify.sh）"
