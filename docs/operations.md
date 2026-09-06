# 运维手册

## 查看状态

```bash
# 服务端（VPS 上，root）
./scripts/show-peers.sh            # 设备名 + IP + endpoint + 握手 + 累计流量
./scripts/wgwatch 2                # 每台设备实时速率（Ctrl-C 退出）
wg show                            # WireGuard 原生信息
```

`show-peers.sh` 与 `wgwatch` 从 `peers.map` 读取“设备名 ↔ 公钥”映射，该文件由 `add-client.sh` 自动维护。

## 添加设备

```bash
./clients/add-client.sh <设备名> [隧道IP]
# 例：./clients/add-client.sh alice 10.8.0.2
# 省略 IP 时自动分配下一个空闲地址
# --ipv6 <地址>   同时分配 IPv6
# --dry-run       只预览不落地
# --print         回显配置文本
# --import-private <私钥>  复用已有私钥（收养已部署设备）
```

输出：`secrets/<设备名>.conf` 与二维码 `secrets/<设备名>.png`。把二者之一导入设备即可。

## 删除 / 停用设备

用 `uninstall.sh`（推荐，自动清理 wg0.conf + peers.map + secrets）：

```bash
# 按名字 / 隧道 IP / 公钥（可多个，--dry-run 预览）
sudo ./server/uninstall.sh alice bob
sudo ./server/uninstall.sh 10.8.0.3 --dry-run
sudo ./server/uninstall.sh vfoZUVseHgoslLrkyNXTRF5rwhvePYTm2you9B2nklw=
```

会同步：从 `/etc/wireguard/wg0.conf` 移除 `[Peer]` 段 → `wg syncconf` 热应用（其他在线设备不受影响）→ 清理 `peers.map` 与 `secrets/<名字>.conf/.png`。

手工方式等价命令：

```bash
# 编辑 /etc/wireguard/wg0.conf 删除对应 [Peer] 段，然后热应用：
wg-quick strip wg0 | wg syncconf wg0 /dev/stdin
```

## 全量卸载

```bash
sudo ./server/uninstall.sh --yes
```

会：停用 `wg0` 与开机自启 → 备份 `/etc/wireguard` 到 `/root/wireguard-backup-<时间戳>.tar.gz` 后删除 → 删除 WG 端口的 ufw 放行（保留 OpenSSH）→ 把本地 `secrets/`、`peers.map` 改名备份。`net.ipv4.ip_forward` 保持原样，如需关闭请手动处理。

## 密钥轮换

给某设备换钥匙（保持同一隧道 IP）：

1. `./clients/add-client.sh <名字> <旧IP> --dry-run` 生成新钥匙预览；
2. 用新公钥替换 `wg0.conf` 里该 peer 的 `PublicKey`，`wg syncconf` 应用；
3. 在该设备上更新 `PrivateKey` 并重连。

> 同一 IP 不能同时映射到两个公钥，所以轮换会有短暂中断，属正常现象。

## 备份与恢复

```bash
./scripts/backup.sh                 # 拉取 VPS /etc/wireguard 到 backup/<时间戳>/
./scripts/secrets-lock.sh           # 加密 secrets/ -> secrets.tar.age（需 age）
./scripts/secrets-unlock.sh         # 解密还原
./scripts/restore.sh backup/<时间戳>  # 回传并重载
```

## 监控（可选）

```bash
./monitoring/install-netdata.sh     # 安装 netdata + WireGuard 分设备采集
```

之后到 https://app.netdata.cloud 认领节点，网页 / Netdata Mobile App 里搜索 `wireguard` 或 `Peer traffic` 查看每台设备流量。
