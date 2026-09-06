#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# secrets-lock.sh - 用 age 把 secrets/ 加密成 secrets.tar.age
# 首次运行会自动生成身份密钥 .age.key（位于项目根目录，已 gitignore）。
# 依赖：age（brew install age / apt install age / 下载单文件）
# ============================================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v age >/dev/null 2>&1 || { echo "[错误] 缺少 age。安装：brew install age  或  apt install age"; exit 1; }
[ -d secrets ] || { echo "[提示] 尚无 secrets/ 目录，无需加密"; exit 0; }

IDENT=".age.key"
if [ ! -f "$IDENT" ]; then
  umask 077
  age-keygen -o "$IDENT"
  echo "已生成身份密钥 ${IDENT}（请妥善保管，解密必需）"
fi

RECIPIENT="$(age-keygen -y "$IDENT")"
tar -C . -cf - secrets | age -r "$RECIPIENT" -o secrets.tar.age
chmod 600 secrets.tar.age

echo "已加密 -> secrets.tar.age"
echo "解密：./scripts/secrets-unlock.sh"
