#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# clients/remove-client.sh - 移除一个或多个设备（客户端）
#
# 用法（在 VPS 上以 root 运行）：
#   ./clients/remove-client.sh alice bob          # 按名字/隧道IP/公钥移除多个
#   ./clients/remove-client.sh 10.8.0.3 --dry-run # 预览
#
# 说明：
#   - 按“名字/隧道IP”解析依赖项目根目录的 peers.map（由 add-client.sh 维护）；
#   - 公钥可直接给完整值或唯一前缀；
#   - 会同步清理 wg0.conf、peers.map 与 secrets/<名字>.conf/.png，并 wg syncconf 热应用。
# ============================================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ "$(id -u)" -eq 0 ] || { echo "[错误] 请以 root 运行：sudo ./clients/remove-client.sh ..."; exit 1; }

WG_CONF=/etc/wireguard/wg0.conf
PEERS=()
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    -*) echo "[错误] 未知选项：$1"; exit 2 ;;
    *) PEERS+=("$1"); shift ;;
  esac
done

[ ${#PEERS[@]} -gt 0 ] || { echo "[错误] 请指定要移除的设备（名字/隧道IP/公钥，可多个）"; exit 2; }

# ---- 解析设备标识 -> 公钥 + 名字 ----
resolver() {
  local arg="$1"
  PK=""; NAME=""
  # 1) 完整公钥（精确整行匹配）
  if grep -qFx "PublicKey = ${arg}" "$WG_CONF" 2>/dev/null; then PK="$arg"; return 0; fi
  # 2) 公钥唯一前缀
  local cnt=0 p
  while read -r p; do
    case "$p" in "$arg"*) PK="$p"; cnt=$((cnt+1));; esac
  done < <(grep -oE '^PublicKey = [A-Za-z0-9+/]+={0,2}' "$WG_CONF" 2>/dev/null | awk '{print $3}')
  if [ "$cnt" -eq 1 ]; then return 0; fi
  [ "$cnt" -gt 1 ] && { echo "[错误] 前缀 '$arg' 匹配多个公钥，请给完整公钥"; return 1; }
  # 3) peers.map 中的名字或隧道 IP
  if [ -f peers.map ]; then
    local name ip pk
    while IFS=$'\t' read -r name ip pk; do
      case "$name" in ''|'#'*) continue ;; esac
      if [ "$name" = "$arg" ] || [ "$ip" = "$arg" ]; then PK="$pk"; NAME="$name"; return 0; fi
    done < peers.map
  fi
  echo "[错误] 找不到设备 '$arg'（可用名字/隧道IP/公钥）"; return 1
}

remove_peer_block() {
  local pk="$1"
  awk -v pk="$pk" '
    function flush(){ if(inpeer && !skip) printf "%s", buf; inpeer=0; skip=0; buf="" }
    /^\[Peer\]/ { flush(); inpeer=1; skip=0; buf=$0 ORS; next }
    inpeer {
      if ($0 ~ /^PublicKey[[:space:]]*=/ && index($0, pk)) skip=1
      buf=buf $0 ORS
      next
    }
    { flush(); print }
    END { flush() }
  ' "$WG_CONF" > "$WG_CONF.tmp" && mv "$WG_CONF.tmp" "$WG_CONF"
}

for arg in "${PEERS[@]}"; do
  PK=""; NAME=""
  resolver "$arg" || exit 1
  label="${NAME:-$PK}"
  echo "将移除设备：${label}（${PK}）"
  if [ "$DRY" -eq 0 ]; then
    remove_peer_block "$PK"
    # 清理 peers.map
    if [ -f peers.map ]; then
      grep -vF "$PK" peers.map > peers.map.tmp && mv peers.map.tmp peers.map
      if [ -n "$NAME" ]; then grep -vF "$NAME" peers.map > peers.map.tmp && mv peers.map.tmp peers.map; fi
    fi
    # 清理 secrets
    if [ -n "$NAME" ]; then
      rm -f "secrets/${NAME}.conf" "secrets/${NAME}.png"
    fi
  fi
done

if [ "$DRY" -eq 0 ]; then
  wg-quick strip wg0 | wg syncconf wg0 /dev/stdin
  echo "已移除 ${#PEERS[@]} 台设备并热应用（在线会话未受影响）。"
else
  echo "[dry-run] 未做任何修改。"
fi
