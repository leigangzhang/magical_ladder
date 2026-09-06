#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# secrets-unlock.sh - 解密 secrets.tar.age 还原到 secrets/
# 需要与加密时一致的 .age.key（位于项目根目录）。
# ============================================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v age >/dev/null 2>&1 || { echo "[错误] 缺少 age。安装：brew install age  或  apt install age"; exit 1; }
IDENT=".age.key"
[ -f "$IDENT" ] || { echo "[错误] 缺少身份密钥 ${IDENT}"; exit 1; }
[ -f secrets.tar.age ] || { echo "[错误] 缺少 secrets.tar.age"; exit 1; }

rm -rf secrets && mkdir -p secrets
age -d -i "$IDENT" -o secrets.tar secrets.tar.age
tar -xf secrets.tar -C .
rm -f secrets.tar

echo "已解密 -> secrets/"
