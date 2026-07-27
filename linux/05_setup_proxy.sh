#!/usr/bin/env bash
# =====================================================================
# GCU3 Bootstrap - Proxy (05) v1.01  ※Phase1固定・簡素化
# 方針(レビュー反映 + Phase1固定):
#   - セキュリティは Phase1 レベルで固定（過剰実装しない）
#   - プロファイルは安全な行パーサで読む（source しない）
#   - 認証情報付きProxyは永続ファイルへ保存しない
#     * 認証なし(host:port) → apt/environment へ設定
#     * 認証あり(user:pass@) → 現在shell(export)のみ。永続化しない
#   - NO_PROXY は COMMON+PROFILE+RUNTIME の3層合成
# 使い方:
#   ./05_setup_proxy.sh --profile office-osaka
# Secret:
#   export SECRET_PROXY_URL=http://proxy.kubota.local:8080
# =====================================================================
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

PROFILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    *) log_err "不明な引数: $1"; exit 10 ;;
  esac
done
[[ -z "$PROFILE" ]] && { log_err "--profile が必要です"; exit 10; }

PROFILE_DIR="${GCU3_PROFILE_DIR:-${SCRIPT_DIR}/../config/profiles}"
PROFILE_FILE="${PROFILE_DIR}/${PROFILE}.env"
[[ -f "$PROFILE_FILE" ]] || { log_err "プロファイル無し: $PROFILE_FILE"; exit 10; }

# ---- 安全な行パーサ（source しない＝任意コード実行を防ぐ） ----
PROFILE_NAME=""; HTTP_PROXY_REF=""; HTTPS_PROXY_REF=""; NO_PROXY_PROFILE=""
while IFS='=' read -r key value; do
  key="$(echo "$key" | tr -d ' ')"
  case "$key" in
    PROFILE_NAME) PROFILE_NAME="$value" ;;
    HTTP_PROXY_REF) HTTP_PROXY_REF="$value" ;;
    HTTPS_PROXY_REF) HTTPS_PROXY_REF="$value" ;;
    NO_PROXY_PROFILE) NO_PROXY_PROFILE="$value" ;;
    ""|\#*) ;;  # 空行/コメント
    *) log_warn "未対応キーを無視: $key" ;;
  esac
done < "$PROFILE_FILE"
log_step "プロファイル: ${PROFILE_NAME:-$PROFILE}"

# ---- Secret参照解決（値はプロファイルに持たない） ----
resolve_ref() { local ref="$1"; [[ -z "$ref" || "$ref" == "none" ]] && { echo ""; return; }; echo "${!ref:-}"; }
HTTP_VAL="$(resolve_ref "$HTTP_PROXY_REF")"
HTTPS_VAL="$(resolve_ref "$HTTPS_PROXY_REF")"

if [[ -z "$HTTP_VAL" && -z "$HTTPS_VAL" ]]; then
  log_warn "Secret(${HTTP_PROXY_REF:-}/${HTTPS_PROXY_REF:-})未設定。直結想定で続行。"
fi

# ---- 認証情報の有無を判定（user:pass@ を含むか） ----
has_credentials() { [[ "$1" =~ ^https?://[^/]*:[^/]*@ ]]; }
CRED_PRESENT=0
{ has_credentials "$HTTP_VAL" || has_credentials "$HTTPS_VAL"; } && CRED_PRESENT=1

# ---- NO_PROXY 3層合成 ----
COMMON_NO_PROXY="localhost,127.0.0.1,::1,.kubota.co.jp"
RUNTIME_NO_PROXY=""
if has_cmd ip; then
  gw="$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')"
  [[ -n "${gw:-}" ]] && RUNTIME_NO_PROXY="$gw"
fi
RUNTIME_NO_PROXY="${RUNTIME_NO_PROXY:+${RUNTIME_NO_PROXY},}172.17.0.0/16"
NO_PROXY_ALL="$(echo "${COMMON_NO_PROXY},${NO_PROXY_PROFILE},${RUNTIME_NO_PROXY}" \
  | tr ',' '\n' | awk 'NF' | awk '!seen[$0]++' | paste -sd, -)"
log_step "NO_PROXY(3層) = ${NO_PROXY_ALL}"

# ---- 永続化の可否をセキュリティ方針で分岐 ----
if [[ "$CRED_PRESENT" -eq 1 ]]; then
  log_warn "認証情報付きProxyを検出 → 永続ファイルへ保存しません（現在shellのみ）。"
  export http_proxy="$HTTP_VAL" HTTP_PROXY="$HTTP_VAL"
  export https_proxy="${HTTPS_VAL:-$HTTP_VAL}" HTTPS_PROXY="${HTTPS_VAL:-$HTTP_VAL}"
  export no_proxy="$NO_PROXY_ALL" NO_PROXY="$NO_PROXY_ALL"
  log_warn "apt を通す場合は本shellから apt を実行してください（永続設定は作成しません）。"
else
  # 認証なし host:port のみ → 永続化を許容
  ENVFILE=/etc/environment
  log_step "/etc/environment に反映（認証なしのみ・冪等）"
  srun sed -i '/^# >>> GCU3 proxy >>>/,/^# <<< GCU3 proxy <<</d' "$ENVFILE" 2>/dev/null || true
  {
    echo "# >>> GCU3 proxy >>>"
    [[ -n "$HTTP_VAL"  ]] && { echo "http_proxy=$HTTP_VAL";  echo "HTTP_PROXY=$HTTP_VAL"; }
    [[ -n "$HTTPS_VAL" ]] && { echo "https_proxy=$HTTPS_VAL"; echo "HTTPS_PROXY=$HTTPS_VAL"; }
    echo "no_proxy=$NO_PROXY_ALL"; echo "NO_PROXY=$NO_PROXY_ALL"
    echo "# <<< GCU3 proxy <<<"
  } | srun tee -a "$ENVFILE" >/dev/null

  APTCONF=/etc/apt/apt.conf.d/95gcu3-proxy
  if [[ -n "$HTTP_VAL" || -n "$HTTPS_VAL" ]]; then
    {
      [[ -n "$HTTP_VAL"  ]] && echo "Acquire::http::Proxy  \"$HTTP_VAL\";"
      [[ -n "$HTTPS_VAL" ]] && echo "Acquire::https::Proxy \"$HTTPS_VAL\";"
    } | srun tee "$APTCONF" >/dev/null
    log_ok "apt Proxy設定を書き込み"
  else
    srun rm -f "$APTCONF" 2>/dev/null || true
  fi
fi

log_ok "05_setup_proxy.sh 完了 (profile=$PROFILE / Phase1固定)"
