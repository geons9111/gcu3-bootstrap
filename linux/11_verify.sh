#!/usr/bin/env bash
# =====================================================================
# GCU3 Bootstrap - 環境検証 (11) v1.01
# 方針(レビュー反映):
#   - docker は docker→sudo docker の順で判定（グループ未反映を吸収）
#   - JSON証跡を出力（logs/verify-*.json）
#   - 非破壊（読み取りのみ）
# =====================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

PASS=0; FAIL=0; WARN=0
JSON="${BOOTSTRAP_LOG_DIR}/verify-$(date +%Y%m%d-%H%M%S).json"
declare -A RESULT

ok(){ echo -e "  [PASS] $1"; PASS=$((PASS+1)); RESULT["$2"]="pass"; }
ng(){ echo -e "  [FAIL] $1"; FAIL=$((FAIL+1)); RESULT["$2"]="fail"; }
wn(){ echo -e "  [WARN] $1"; WARN=$((WARN+1)); RESULT["$2"]="warn"; }

log_step "コマンド存在チェック"
has_cmd git        && ok "git"        git        || ng "git"        git
has_cmd tree       && ok "tree"       tree       || ng "tree"       tree
has_cmd rsync      && ok "rsync"      rsync      || ng "rsync"      rsync
has_cmd cmake      && ok "cmake"      cmake      || wn "cmake"       cmake
has_cmd docker     && ok "docker"     docker     || ng "docker"     docker
has_cmd python3    && ok "python3"    python3    || ng "python3"    python3
has_cmd shellcheck && ok "shellcheck" shellcheck || wn "shellcheck" shellcheck

log_step "バージョン一覧"
for c in git tree cmake python3 docker; do
  has_cmd "$c" && echo "  - $c: $($c --version 2>&1 | head -1)"
done
has_cmd docker && echo "  - compose: $(docker compose version 2>&1 | head -1)"

log_step "Docker 稼働チェック（docker→sudo docker）"
if has_cmd docker; then
  if docker info >/dev/null 2>&1; then
    docker run --rm hello-world >/dev/null 2>&1 && ok "docker run hello-world" docker_run || wn "docker hello-world取得失敗(Proxy/NW)" docker_run
  elif sudo docker info >/dev/null 2>&1; then
    wn "Engine OK。グループ未反映(再ログイン/newgrp docker が必要)" docker_group
  else
    ng "docker デーモン未接続(systemd/07 と再起動を確認)" docker_daemon
  fi
fi

log_step "自動更新 timer 確認"
if pidof systemd >/dev/null 2>&1; then
  systemctl is-enabled gcu3-update.timer >/dev/null 2>&1 && ok "gcu3-update.timer(週次)" autoupdate || wn "gcu3-update.timer 未有効" autoupdate
  systemctl is-enabled unattended-upgrades >/dev/null 2>&1 && ok "unattended-upgrades" unattended || wn "unattended-upgrades 未有効" unattended
else
  wn "systemd 無効のため timer 未確認" systemd
fi

log_step "Proxy 反映確認（認証なし設定時のみ）"
grep -E 'HTTP_PROXY|NO_PROXY' /etc/environment 2>/dev/null | sed 's/^/  /' || echo "  (Proxy未設定/認証付きは非永続)"

# JSON証跡
if [[ "${DRY_RUN:-0}" -ne 1 ]]; then
  {
    echo "{"
    echo "  \"timestamp\": \"$(date -Is)\","
    echo "  \"pass\": ${PASS}, \"fail\": ${FAIL}, \"warn\": ${WARN},"
    echo "  \"results\": {"
    local_first=1
    for k in "${!RESULT[@]}"; do
      [[ $local_first -eq 1 ]] && local_first=0 || echo ","
      printf '    "%s": "%s"' "$k" "${RESULT[$k]}"
    done
    echo ""
    echo "  }"
    echo "}"
  } > "$JSON" 2>/dev/null || true
  echo ""
  log_step "証跡: $JSON"
fi

echo ""
log_step "検証サマリ: PASS=${PASS} / WARN=${WARN} / FAIL=${FAIL}"
[[ "$FAIL" -gt 0 ]] && { log_warn "FAIL あり。GUIDELINE のトラブルシュート参照"; exit 1; }
log_ok "検証完了（FAILなし）"
