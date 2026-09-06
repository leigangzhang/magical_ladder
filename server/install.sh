#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# 一键初始化 WireGuard 服务端（在 VPS 上以 root 运行，幂等可重复执行）
# 用法：sudo ./server/install.sh
# 前置：项目根目录已存在 config.env（cp config.env.example config.env）
# ============================================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ -f config.env ] || { echo "[错误] 缺少 config.env，请先 cp config.env.example config.env 并填写"; exit 1; }
# shellcheck source=/dev/null
. ./config.env

[ "$(id -u)" -eq 0 ] || { echo "[错误] 请以 root 运行：sudo ./server/install.sh"; exit 1; }

: "${ENDPOINT:?请设置 ENDPOINT}"
: "${WG_PORT:=51820}"
: "${SERVER_V4:?请设置 SERVER_V4}"
: "${PUBLIC_IFACE:=eth0}"

export DEBIAN_FRONTEND=noninteractive
echo "[1/6] 安装依赖 (wireguard qrencode) ..."
apt-get update -y >/dev/null
apt-get install -y wireguard qrencode >/dev/null

echo "[2/6] 生成服务端密钥对 ..."
install -d -m 700 /etc/wireguard
umask 077
if [ ! -f /etc/wireguard/private.key ]; then
  wg genkey > /etc/wireguard/private.key
fi
SERVER_PRIVATE_KEY="$(cat /etc/wireguard/private.key)"
SERVER_PUBLIC_KEY="$(wg pubkey <<<"$SERVER_PRIVATE_KEY")"

echo "[3/6] 渲染 /etc/wireguard/wg0.conf ..."
SERVER_V6_LINE=""
if [ -n "${SERVER_V6:-}" ]; then
  SERVER_V6_LINE="Address = ${SERVER_V6}/64"
fi
if [ -f /etc/wireguard/wg0.conf ]; then
  cp /etc/wireguard/wg0.conf "/etc/wireguard/wg0.conf.bak.$(date +%Y%m%d-%H%M%S)"
  echo "      已备份现有配置"
fi
umask 077
sed -e "s|{{SERVER_PRIVATE_KEY}}|${SERVER_PRIVATE_KEY}|g" \
    -e "s|{{SERVER_V4}}|${SERVER_V4}|g" \
    -e "s|{{SERVER_V6_LINE}}|${SERVER_V6_LINE}|g" \
    -e "s|{{WG_PORT}}|${WG_PORT}|g" \
    -e "s|{{PUBLIC_IFACE}}|${PUBLIC_IFACE}|g" \
    server/wg0.conf.template > /etc/wireguard/wg0.conf
# 去掉因 v6 未启用产生的空行
sed -i '/^[[:space:]]*$/d' /etc/wireguard/wg0.conf
chmod 600 /etc/wireguard/wg0.conf

echo "[4/6] 开启 IPv4 转发（持久化）..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null
if grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf 2>/dev/null; then
  sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
else
  echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi

echo "[5/6] 配置防火墙（幂等）..."
command -v ufw >/dev/null 2>&1 || apt-get install -y ufw >/dev/null
ufw allow "${WG_PORT}/udp" >/dev/null 2>&1 || true
ufw allow OpenSSH >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true

echo "[6/6] 启动并开机自启 ..."
wg-quick down wg0 >/dev/null 2>&1 || true
wg-quick up wg0
systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true

echo
echo "======================== 完成 ========================"
echo "服务端公钥 : ${SERVER_PUBLIC_KEY}"
echo "Endpoint   : ${ENDPOINT}:${WG_PORT}"
echo "隧道网段   : ${WG_NETV4}（服务端 ${SERVER_V4}）"
echo
echo "下一步添加设备："
echo "  ./clients/add-client.sh <设备名> <隧道IP>"
echo "  例如：./clients/add-client.sh alice 10.8.0.2"
