#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# uninstall.sh - 全局清理 / 移除设备
#
# 用法（在 VPS 上以 root 运行）：
#   ./server/uninstall.sh                  # 全量卸载服务端（需 --yes）
#   ./server/uninstall.sh --yes            # 全量卸载（跳过确认）
#   ./server/uninstall.sh alice bob        # 移除一个或多个设备（名字/隧道IP/公钥）
#   ./server/uninstall.sh alice --dry-run  # 预览将执行的动作
#
# 说明：
#   - 按“名字/隧道IP”解析依赖项目根目录的 peers.map（由 add-client.sh 维护）；
#   - 公钥可直接给完整值或唯一前缀；
#   - 移除设备会同步清理 wg0.conf、peers.map 与 secrets/<名字>.conf/.png。
# ============================================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ "$(id -u)" -eq 0 ] || { echo "[错误] 请以 root 运行：sudo ./server/uninstall.sh ..."; exit 1; }

WG_CONF=/etc/wireguard/wg0.conf
PEERS=()
DRY=0
YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --yes|-y) YES=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    -*) echo "[错误] 未知选项：$1"; exit 2 ;;
    *) PEERS+=("$1"); shift ;;
  esac
done

# ---- 解析设备标识 -> 公钥 + 名字 ----
resolver() {
  local arg="$1"
  PK=""; NAME=""
  # 1) 完整公钥
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

# ============================================================================
# 全量卸载
# ============================================================================
if [ ${#PEERS[@]} -eq 0 ]; then
  [ "$YES" -eq 1 ] || { echo "[提示] 全量卸载会停用 wg0、删除 /etc/wireguard 并备份本地 secrets/。确认请加 --yes"; exit 1; }

  TS="$(date +%Y%m%d-%H%M%S)"
  echo "== 全量卸载 WireGuard 服务端 =="
  wg-quick down wg0 2>/dev/null || true
  systemctl disable wg-quick@wg0 2>/dev/null || true

  if [ -d /etc/wireguard ]; then
    tar czf "/root/wireguard-backup-${TS}.tar.gz" -C /etc wireguard
    echo "      已备份 /etc/wireguard -> /root/wireguard-backup-${TS}.tar.gz"
    rm -rf /etc/wireguard
  fi

  # 防火墙：仅删 WG 端口放行（OpenSSH 保留）
  . ./config.env 2>/dev/null || true
  ufw delete allow "${WG_PORT:-51820}/udp" 2>/dev/null || true

  # 本地 secrets / peers.map 备份后清理
  [ -d secrets ] && mv secrets "secrets.bak-${TS}"
  [ -f peers.map ] && mv peers.map "peers.map.bak-${TS}"

  echo "完成。注意：OpenSSH 防火墙规则与 net.ipv4.ip_forward 保持不变（如需还原请手动处理）。"
  exit 0
fi

# ============================================================================
# 移除指定设备
# ============================================================================
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
