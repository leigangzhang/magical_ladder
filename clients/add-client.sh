#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# 新增一台客户端设备：生成密钥、追加 Peer、热生效、输出配置与二维码
#
# 用法（在 VPS 上以 root 运行）：
#   ./clients/add-client.sh <设备名> [隧道IP] [选项]
#
# 选项：
#   --ipv6 ADDR          同时分配隧道 IPv6 地址（需服务端已启用 IPv6）
#   --import-private KEY 复用已有私钥（例如“收养”已部署的设备，避免重新导入）
#   --print              回显完整客户端配置文本
#   --dry-run            只打印将执行的动作，不落地任何修改
# ============================================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ -f config.env ] || { echo "[错误] 缺少 config.env，请先 cp config.env.example config.env 并填写"; exit 1; }
# shellcheck source=/dev/null
. ./config.env

[ "$(id -u)" -eq 0 ] || { echo "[错误] 请以 root 运行：sudo ./clients/add-client.sh ..."; exit 1; }

NAME=""
IP=""
IPV6=""
PRINT=0
DRY=0
IMPORT_PRIV=""

while [ $# -gt 0 ]; do
  case "$1" in
    --ipv6) IPV6="${2:-}"; shift 2 ;;
    --import-private) IMPORT_PRIV="${2:-}"; shift 2 ;;
    --print) PRINT=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    -*) echo "[错误] 未知选项：$1"; exit 2 ;;
    *)
      if [ -z "$NAME" ]; then NAME="$1";
      elif [ -z "$IP" ]; then IP="$1";
      else echo "[错误] 多余参数：$1"; exit 2; fi
      shift ;;
  esac
done

[ -n "$NAME" ] || { echo "[错误] 缺少设备名"; exit 2; }

# 校验设备名只含字母数字与 -_
[[ "$NAME" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "[错误] 设备名仅允许字母/数字/-/_"; exit 2; }

SERVER_PUBLIC_KEY="$(wg pubkey <<<"$(cat /etc/wireguard/private.key)")"

# ---- 隧道 IP：未给则自动分配下一个空闲地址 ----
if [ -z "$IP" ]; then
  base="${SERVER_V4%.*}."
  last="$({ echo "$SERVER_V4"; grep -oE "${base//./\\.}[0-9]+" /etc/wireguard/wg0.conf 2>/dev/null || true; } \
        | sed -E 's/.*\.//' | sort -n | tail -1)"
  next=$(( last + 1 ))
  IP="${base}${next}"
fi

[[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "[错误] 隧道 IPv4 格式错误：$IP"; exit 2; }
[[ "$IP" == "$SERVER_V4" ]] && { echo "[错误] ${IP} 是服务端地址，请换一个"; exit 2; }

# ---- 冲突检查 ----
if grep -qE "^[[:space:]]*${IP//./\\.}/32" /etc/wireguard/wg0.conf 2>/dev/null; then
  echo "[错误] ${IP}/32 已被占用"; exit 1
fi
if [ -f peers.map ] && grep -qE "^[[:space:]]*${NAME}[[:space:]]" peers.map 2>/dev/null; then
  echo "[错误] 设备名 ${NAME} 已存在（见 peers.map）"; exit 1
fi

# ---- 密钥 ----
if [ -n "$IMPORT_PRIV" ]; then
  CLIENT_PRIVATE_KEY="$IMPORT_PRIV"
else
  CLIENT_PRIVATE_KEY="$(wg genkey)"
fi
CLIENT_PUBLIC_KEY="$(wg pubkey <<<"$CLIENT_PRIVATE_KEY")"

if grep -qF "PublicKey = ${CLIENT_PUBLIC_KEY}" /etc/wireguard/wg0.conf 2>/dev/null; then
  echo "[错误] 该公钥已在 wg0.conf 中（可能重复导入同一把私钥）"
  exit 1
fi

# ---- 组装客户端配置值 ----
CLIENT_V6_LINE=""
CLIENT_ALLOWED_IPS="0.0.0.0/0"
ALLOWED_IPS="${IP}/32"
if [ -n "$IPV6" ]; then
  CLIENT_V6_LINE="Address = ${IPV6}/64"
  CLIENT_ALLOWED_IPS="0.0.0.0/0, ::/0"
  ALLOWED_IPS="${IP}/32, ${IPV6}/128"
fi

render_client() {
  sed -e "s|{{CLIENT_PRIVATE_KEY}}|${CLIENT_PRIVATE_KEY}|g" \
      -e "s|{{CLIENT_V4}}|${IP}|g" \
      -e "s|{{CLIENT_V6_LINE}}|${CLIENT_V6_LINE}|g" \
      -e "s|{{CLIENT_DNS}}|${CLIENT_DNS:-8.8.8.8}|g" \
      -e "s|{{SERVER_PUBLIC_KEY}}|${SERVER_PUBLIC_KEY}|g" \
      -e "s|{{CLIENT_ALLOWED_IPS}}|${CLIENT_ALLOWED_IPS}|g" \
      -e "s|{{ENDPOINT}}|${ENDPOINT}|g" \
      -e "s|{{WG_PORT}}|${WG_PORT:-51820}|g" \
      -e "s|{{KEEPALIVE}}|${KEEPALIVE:-25}|g" \
      clients/client.conf.template | sed '/^[[:space:]]*$/d'
}

CONF_TEXT="$(render_client)"

if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] 设备名   : ${NAME}"
  echo "[dry-run] 隧道 IP  : ${IP}"
  echo "[dry-run] 公钥     : ${CLIENT_PUBLIC_KEY}"
  echo "[dry-run] 将追加 [Peer] 到 /etc/wireguard/wg0.conf 并 wg syncconf"
  echo "[dry-run] 将生成 secrets/${NAME}.conf 与 secrets/${NAME}.png"
  echo "-------- 配置预览 --------"
  echo "$CONF_TEXT"
  exit 0
fi

# ---- 追加 Peer 并热生效 ----
umask 077
cat >> /etc/wireguard/wg0.conf <<EOF

[Peer]
# ${NAME} ${IP}
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${ALLOWED_IPS}
EOF

wg-quick strip wg0 | wg syncconf wg0 /dev/stdin

# ---- 输出配置与二维码 ----
mkdir -p secrets && chmod 700 secrets
umask 077
printf '%s\n' "$CONF_TEXT" > "secrets/${NAME}.conf"
chmod 600 "secrets/${NAME}.conf"
command -v qrencode >/dev/null 2>&1 && qrencode -t PNG -s 10 -o "secrets/${NAME}.png" < "secrets/${NAME}.conf" || true

# ---- 记录 peers.map ----
{ grep -vE "^[[:space:]]*${NAME}[[:space:]]" peers.map 2>/dev/null || true; printf '%s\t%s\t%s\n' "$NAME" "$IP" "$CLIENT_PUBLIC_KEY"; } > peers.map.tmp
mv peers.map.tmp peers.map

echo "======================== 已添加 ${NAME} ========================"
echo "隧道 IP : ${IP}"
echo "公钥    : ${CLIENT_PUBLIC_KEY}"
echo "配置文件: secrets/${NAME}.conf"
[ -f "secrets/${NAME}.png" ] && echo "二维码  : secrets/${NAME}.png"
echo
echo "把 secrets/${NAME}.conf 导入到设备（或用二维码扫描），然后连接即可。"
[ "$PRINT" -eq 1 ] && { echo "-------- 配置内容 --------"; echo "$CONF_TEXT"; }
