#!/usr/bin/env bash
# =====================================================================
# GCU3 Integration - Docker 管理ヘルパー (21) v1.1
# 目的: WSL2/Ubuntu/Azure Ubuntu VM 上の Docker Engine を簡単管理
# 方針: docker→sudo docker を自動判定（グループ未反映を吸収）
# 注意: Docker "install" は bootstrap(03) 側。ここは "manage" のみ（重複排除）
# 使い方: ./21_docker_manage.sh <command>
#   status | test | ps | images | df | prune | clean-all
#   compose-up [dir] | compose-down [dir] | logs <name> | restart-daemon
# =====================================================================
set -Eeuo pipefail
DOCKER="docker"
docker info >/dev/null 2>&1 || { sudo docker info >/dev/null 2>&1 && DOCKER="sudo docker"; }
c_cyan='\033[0;36m'; c_green='\033[0;32m'; c_yellow='\033[0;33m'; c_off='\033[0m'
step(){ echo -e "${c_cyan}==> $*${c_off}"; }; ok(){ echo -e "${c_green}[OK] $*${c_off}"; }; warn(){ echo -e "${c_yellow}[WARN] $*${c_off}"; }
require(){ command -v docker >/dev/null 2>&1 || { echo "docker未導入。bootstrap 03_setup_docker.sh を実行"; exit 1; }; }

cmd="${1:-status}"; shift || true
case "$cmd" in
  status)
    require; step "Docker 状態"
    echo "  docker : $(docker --version 2>/dev/null || echo 未導入)"
    echo "  compose: $(docker compose version 2>/dev/null | head -1 || echo 未導入)"
    echo "  buildx : $(docker buildx version 2>/dev/null | head -1 || echo 未導入)"
    if docker info >/dev/null 2>&1; then ok "権限: sudoなしOK"
    elif sudo docker info >/dev/null 2>&1; then warn "Engine OK。グループ未反映→'newgrp docker'/再ログイン"
    else warn "daemon未接続。systemd(07)と 'wsl --shutdown'→再起動を確認"; fi
    echo "  PID1   : $(ps -p 1 -o comm= 2>/dev/null)"
    ;;
  test)   require; step "hello-world"; $DOCKER run --rm hello-world && ok "疎通OK" || warn "取得失敗(Proxy/NW)";;
  ps)     require; $DOCKER ps ;;
  images) require; $DOCKER images ;;
  df)     require; $DOCKER system df ;;
  prune)  require; step "不要リソース削除(volume除く)"; $DOCKER system prune -f; $DOCKER builder prune -f 2>/dev/null || true; ok "prune完了";;
  clean-all)
    require; warn "未使用volumeも削除（データ消去注意）"
    read -r -p "続行しますか? [y/N]: " a; [[ "$a" == "y" || "$a" == "Y" ]] || { echo "中止"; exit 0; }
    $DOCKER system prune -af --volumes; ok "clean-all完了";;
  compose-up)   require; dir="${1:-./docker}"; step "compose up -d ($dir)"; ( cd "$dir" && $DOCKER compose up -d ) && ok "起動" || warn "失敗";;
  compose-down) require; dir="${1:-./docker}"; step "compose down ($dir)"; ( cd "$dir" && $DOCKER compose down ) && ok "停止" || warn "失敗";;
  logs)   require; n="${1:-}"; [[ -z "$n" ]] && { echo "使い方: logs <container>"; exit 10; }; $DOCKER logs -f "$n";;
  restart-daemon) step "dockerd再起動"; if pidof systemd >/dev/null 2>&1; then sudo systemctl restart docker; else sudo service docker restart; fi; ok "再起動完了";;
  *) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
