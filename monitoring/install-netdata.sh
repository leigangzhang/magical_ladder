#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# install-netdata.sh - 安装 netdata 并启用 WireGuard 分设备采集（可选）
# 在 VPS 上以 root 运行。安装后请到 https://app.netdata.cloud 认领节点，
# 即可在网页或 Netdata Mobile App 查看每台设备的流量图表。
# ============================================================================

[ "$(id -u)" -eq 0 ] || { echo "[错误] 请以 root 运行：sudo ./monitoring/install-netdata.sh"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
echo "[1/3] 安装依赖 ..."
command -v curl >/dev/null 2>&1 || apt-get install -y curl >/dev/null

echo "[2/3] 安装 netdata（stable 渠道）..."
if ! command -v netdata >/dev/null 2>&1; then
  curl -L -Ss -o /tmp/netdata-kickstart.sh https://my-netdata.io/kickstart.sh
  bash /tmp/netdata-kickstart.sh --stable-channel
  rm -f /tmp/netdata-kickstart.sh
fi

echo "[3/3] 启用 go.d wireguard 采集模块并重启 ..."
mkdir -p /etc/netdata/go.d
cat > /etc/netdata/go.d/wireguard.conf <<'EOF'
jobs:
  - name: wg0
    interface_name: wg0
EOF
systemctl restart netdata || systemctl restart netdata.service || true

echo
echo "完成。本地预览：ssh -L 19999:127.0.0.1:19999 <你的VPS> 后浏览器打开 http://127.0.0.1:19999"
echo "远程查看：到 https://app.netdata.cloud 登录并 Claim a node，然后运行页面给出的 netdata-claim.sh 命令。"
echo "分设备图表：仪表盘搜索 'wireguard' 或 'Peer traffic'。"
