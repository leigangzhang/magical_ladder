#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# server/uninstall.sh - 全量卸载 WireGuard 服务端
#
# 用法（在 VPS 上以 root 运行）：
#   ./server/uninstall.sh --yes        # 全量卸载
#   ./server/uninstall.sh --yes --dry-run   # 预览将执行的动作
#
# 会：停用 wg0 与开机自启 → 备份 /etc/wireguard 后删除 → 删除 WG 端口 ufw 放行
#     （保留 OpenSSH）→ 本地 secrets/、peers.map 改名备份。
# 注意：net.ipv4.ip_forward 保持原样，如需关闭请手动处理。
# ============================================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ "$(id -u)" -eq 0 ] || { echo "[错误] 请以 root 运行：sudo ./server/uninstall.sh --yes"; exit 1; }

YES=0
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --yes|-y) YES=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "[错误] 未知参数：$1"; exit 2 ;;
  esac
done

[ "$YES" -eq 1 ] || { echo "[提示] 全量卸载会停用 wg0、删除 /etc/wireguard 并备份本地 secrets/。确认请加 --yes"; exit 1; }

TS="$(date +%Y%m%d-%H%M%S)"

if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] 将执行："
  echo "[dry-run]   wg-quick down wg0 && systemctl disable wg-quick@wg0"
  echo "[dry-run]   备份 /etc/wireguard -> /root/wireguard-backup-${TS}.tar.gz 后删除"
  echo "[dry-run]   删除 ufw 的 WG 端口放行（保留 OpenSSH）"
  echo "[dry-run]   本地 secrets/ -> secrets.bak-${TS}，peers.map -> peers.map.bak-${TS}"
  exit 0
fi

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
