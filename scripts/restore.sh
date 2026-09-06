#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# restore.sh - 把本地备份回传到 VPS 的 /etc/wireguard 并重载接口
# 用法：./scripts/restore.sh backup/<时间戳>
# ============================================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIR="${1:?用法: ./scripts/restore.sh backup/<时间戳>}"

SSH_HOST="${SSH_HOST:-vps}"
[ -f config.env ] && { . ./config.env; SSH_HOST="${SSH_HOST:-vps}"; }

SRC="$(cd "$DIR" 2>/dev/null && pwd)"
[ -d "$SRC" ] || { echo "[错误] 目录不存在：$DIR"; exit 1; }
# 兼容两种情况：目录本身是 wireguard，或目录下有 wireguard 子目录
[ -d "$SRC/wireguard" ] && SRC="$SRC/wireguard"

echo "回传 ${SRC} -> ${SSH_HOST}:/etc/wireguard ..."
scp -q -r "${SRC}/." "${SSH_HOST}:/etc/wireguard/"

echo "重载 wg0 ..."
ssh "$SSH_HOST" 'wg-quick down wg0 2>/dev/null || true; wg-quick up wg0'

echo "恢复完成。可用 ./scripts/show-peers.sh 校验。"
