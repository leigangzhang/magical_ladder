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

编辑 `/etc/wireguard/wg0.conf` 删除对应 `[Peer]` 段，然后热应用：

```bash
wg-quick strip wg0 | wg syncconf wg0 /dev/stdin
```

同时从 `peers.map` 删掉该行。

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
