#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# backup.sh - 把 VPS 上的 /etc/wireguard 拉到本地 backup/<时间戳>/
# 在本地（非 VPS）运行；需要 config.env 中的 SSH_HOST 或默认 vps。
# ============================================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SSH_HOST="${SSH_HOST:-vps}"
[ -f config.env ] && { . ./config.env; SSH_HOST="${SSH_HOST:-vps}"; }

TS="$(date +%Y%m%d-%H%M%S)"
DEST="backup/${TS}"
mkdir -p "$DEST"

echo "从 ${SSH_HOST}:/etc/wireguard 拉取到 ${DEST} ..."
scp -q -r "${SSH_HOST}:/etc/wireguard/" "$DEST/"

echo "备份完成：$DEST"
echo "如需加密保存，运行：./scripts/secrets-lock.sh"
