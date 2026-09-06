#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# agent-deploy.sh - 从控制端（Mac 等）远程编排安装与配置
#
# 用法（在控制端、项目根目录运行，无需 root）：
#   ./scripts/agent-deploy.sh [设备=IP ...] [选项]
#     设备写法：macbook=10.8.0.2  或  iphone（省略 IP 自动分配）
#   --host user@host    VPS SSH 目标（默认取 config.env 的 SSH_HOST，补 root@）
#   --remote-dir PATH   VPS 上的项目目录（默认 /opt/magical_ladder）
#   --dry-run           只打印将执行的命令，不落地
#
# 流程：同步仓库 → 安装服务端 → 为每台设备生成配置 → 拉回 secrets/。
# 详见 docs/agent-deploy.md。
# ============================================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ -f config.env ] || { echo "[错误] 请先 cp config.env.example config.env 并填写"; exit 1; }
# shellcheck source=/dev/null
. ./config.env

HOST=""
REMOTE_DIR=/opt/magical_ladder
DEVICES=()
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --remote-dir) REMOTE_DIR="$2"; shift 2 ;;
    --devices) for d in $2; do DEVICES+=("$d"); done; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    -*) echo "[错误] 未知选项：$1"; exit 2 ;;
    *) DEVICES+=("$1"); shift ;;
  esac
done

# 默认主机：SSH_HOST 补 root@
if [ -z "$HOST" ]; then
  HOST="${SSH_HOST:-vps}"
  case "$HOST" in *@*) ;; *) HOST="root@$HOST" ;; esac
fi

run() { if [ "$DRY" -eq 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }

sync_repo() {
  if [ "$DRY" -eq 1 ]; then
    echo "[dry-run] rsync 同步 ./ -> ${HOST}:${REMOTE_DIR}/"
    return
  fi
  if command -v rsync >/dev/null 2>&1; then
    rsync -az --delete \
      --exclude=.git --exclude=secrets --exclude=backup \
      --exclude=.age.key --exclude=secrets.tar.age \
      ./ "${HOST}:${REMOTE_DIR}/"
  else
    tar czf - --exclude=.git --exclude=secrets --exclude=backup \
      --exclude=.age.key --exclude=secrets.tar.age . \
      | ssh "$HOST" "mkdir -p '$REMOTE_DIR' && tar xzf - -C '$REMOTE_DIR'"
  fi
}

echo "== [1/4] 同步仓库到 ${HOST}:${REMOTE_DIR} =="
sync_repo

echo "== [2/4] 安装服务端 =="
run ssh "$HOST" "cd '$REMOTE_DIR' && ./server/install.sh"

echo "== [3/4] 生成设备配置（${#DEVICES[@]} 台）=="
for d in "${DEVICES[@]}"; do
  name="${d%%=*}"
  ip="${d#*=}"
  [ "$ip" = "$d" ] && ip=""
  if [ -n "$ip" ]; then
    run ssh "$HOST" "cd '$REMOTE_DIR' && ./clients/add-client.sh '$name' '$ip'"
  else
    run ssh "$HOST" "cd '$REMOTE_DIR' && ./clients/add-client.sh '$name'"
  fi
done

echo "== [4/4] 拉回 secrets =="
run mkdir -p secrets
run scp -q -r "${HOST}:${REMOTE_DIR}/secrets/." secrets/

echo
echo "完成。本机 secrets/ 目录："
ls -1 secrets/ 2>/dev/null | sed 's/^/  /' || echo "  （空）"
echo "按 docs/agent-deploy.md 第四节的说明把配置导入各终端。"
