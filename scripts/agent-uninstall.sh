#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# agent-uninstall.sh - 从控制端（Mac 等）远程编排清理
#
# 用法（在控制端、项目根目录运行，无需 root）：
#   ./scripts/agent-uninstall.sh                  # 全量卸载（VPS + 本地 secrets 清理）
#   ./scripts/agent-uninstall.sh alice iphone     # 仅移除指定设备（按名字）
#   ./scripts/agent-uninstall.sh --dry-run ...    # 只打印将执行的命令
#   --host user@host / --remote-dir PATH          同 agent-deploy.sh
#
# 流程：在 VPS 上执行 server/uninstall.sh 或 clients/remove-client.sh，
#       并同步清理控制端本地的 secrets/ 与 peers.map。
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
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    -*) echo "[错误] 未知选项：$1"; exit 2 ;;
    *) DEVICES+=("$1"); shift ;;
  esac
done

if [ -z "$HOST" ]; then
  HOST="${SSH_HOST:-vps}"
  case "$HOST" in *@*) ;; *) HOST="root@$HOST" ;; esac
fi

run() { if [ "$DRY" -eq 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }

TS="$(date +%Y%m%d-%H%M%S)"

if [ ${#DEVICES[@]} -eq 0 ]; then
  # ---- 全量清理 ----
  echo "== [1/3] VPS 全量卸载（server/uninstall.sh --yes）=="
  run ssh "$HOST" "cd '$REMOTE_DIR' && ./server/uninstall.sh --yes"

  echo "== [2/3] 备份并清理本地 secrets / peers.map =="
  if [ "$DRY" -eq 1 ]; then
    echo "[dry-run] mv secrets -> secrets.bak-${TS}；mv peers.map -> peers.map.bak-${TS}"
  else
    [ -d secrets ] && mv secrets "secrets.bak-${TS}"
    [ -f peers.map ] && mv peers.map "peers.map.bak-${TS}"
  fi

  echo "== [3/3] 完成 =="
else
  # ---- 移除指定设备 ----
  NAMES=()
  for d in "${DEVICES[@]}"; do NAMES+=("${d%%=*}"); done

  echo "== [1/3] VPS 移除设备：${NAMES[*]} =="
  run ssh "$HOST" "cd '$REMOTE_DIR' && ./clients/remove-client.sh ${NAMES[*]}"

  echo "== [2/3] 清理本地 secrets/<设备>.conf/.png =="
  for n in "${NAMES[@]}"; do
    if [ "$DRY" -eq 1 ]; then
      echo "[dry-run] rm secrets/${n}.conf secrets/${n}.png"
    else
      rm -f "secrets/${n}.conf" "secrets/${n}.png"
    fi
  done

  echo "== [3/3] 完成 =="
fi
