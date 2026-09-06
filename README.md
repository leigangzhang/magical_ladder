# magical_ladder

一套可公开复用的 magical_ladder 部署模板：在一台 VPS 上快速搭起“1 台服务端 + 多台设备”的全隧道 VPN，每台设备**唯一私钥、唯一隧道 IP**，并附带分设备流量监控与备份/加密工具。

- 全部参数化，无任何硬编码的 IP / 密钥 / 设备名
- 一条命令初始化服务端，一条命令新增设备（自动生成 `.conf` + 二维码）
- 私钥统一落在 `secrets/`（已 gitignore），并提供 age 加解密脚本
- 内置分设备实时速率 `wgwatch` 与状态查看 `show-peers.sh`

---

## 特性

- **服务端**：Ubuntu 一键安装，自动处理密钥、`wg0.conf`、IP 转发、防火墙（ufw + MASQUERADE）、开机自启，幂等可重跑
- **客户端**：`add-client.sh` 生成独立密钥与配置 + 二维码，`wg syncconf` 热生效不打断在线会话；`uninstall.sh` 支持移除单个/多个设备或全量卸载
- **多端导入**：macOS（GUI / wg-quick）、iOS / Android（扫码 / 文件 / 手动）
- **安全**：私钥不进仓库；`secrets/`、`backup/`、`config.env`、`peers.map` 全部 gitignore；`secrets-lock/unlock` 用 age 统一加密
- **监控**：`wgwatch`（实时速率）、`show-peers.sh`（状态/累计）、可选 netdata（分设备历史曲线 + 云端/App）

## 目录结构

```
magical_ladder/
├── server/install.sh        一键初始化服务端
├── server/uninstall.sh      移除设备 / 全量卸载
├── clients/add-client.sh    新增设备（.conf + 二维码 + 追加 peer）
├── scripts/                 wgwatch / show-peers / backup / restore / secrets 加解密
├── monitoring/              可选 netdata 安装
├── docs/                    架构 / 运维 / 排障 / 参考资料
├── examples/                macOS 示例配置、iOS/Android 导入指南
├── config.env.example       全局参数模板（复制为 config.env）
└── peers.map.example        设备映射示例（运行时生成 peers.map）
```

## 快速开始

### 0. 前置条件

- 一台有公网 IP 的 Ubuntu 20.04/22.04 VPS（选型参考 [docs/references.md](docs/references.md)）；
- VPS 上能 `sudo` 的 root 或非 root 用户；
- 客户端设备：macOS / iOS / Android 等，装有 WireGuard 客户端。

### 1. 拉取项目到 VPS

```bash
git clone <你的仓库地址> /opt/magical_ladder
cd /opt/magical_ladder
cp config.env.example config.env
vim config.env            # 至少填写 ENDPOINT（VPS 公网 IP 或域名）
```

### 2. 初始化服务端

```bash
sudo ./server/install.sh
```

输出会打印 **服务端公钥** 与 Endpoint。此时服务端已就绪。

### 3. 新增设备

```bash
sudo ./clients/add-client.sh alice 10.8.0.2
# 或省略 IP 自动分配：sudo ./clients/add-client.sh bob
```

生成 `secrets/alice.conf` 与 `secrets/alice.png`。按设备类型导入：

| 设备 | 方法 |
|---|---|
| macOS（GUI） | 用 WireGuard App 导入 `.conf` 文件 |
| macOS（CLI） | 见 [examples/macos-wg-quick.conf.example](examples/macos-wg-quick.conf.example) |
| iOS / Android | 扫码或导入 `.conf`，见 [examples/ios-android-import.md](examples/ios-android-import.md) |

> 每台设备都要用**各自**的 `add-client.sh` 产物，切勿复制同一份配置到多台设备。

### 4. 验证

```bash
sudo ./scripts/show-peers.sh      # 设备名 + endpoint + 握手 + 累计流量
sudo ./scripts/wgwatch 2          # 实时速率（Ctrl-C 退出）
```

设备连上后应能看到对应行出现 endpoint 与握手。

## 常用命令速查

```bash
# 初始化服务端
sudo ./server/install.sh

# 新增设备（--dry-run 预览、--print 回显、--ipv6 分配 IPv6、--import-private 复用私钥）
sudo ./clients/add-client.sh <名字> [IP] [--dry-run|--print|--ipv6 <addr>|--import-private <key>]

# 移除设备（名字 / 隧道IP / 公钥，可多个；--dry-run 预览）
sudo ./server/uninstall.sh <名字或IP或公钥> [更多...]

# 全量卸载服务端（需 --yes）
sudo ./server/uninstall.sh --yes

# 查看
sudo ./scripts/show-peers.sh
sudo ./scripts/wgwatch [间隔秒]

# 备份 / 恢复 / 加密
./scripts/backup.sh
./scripts/secrets-lock.sh          # 生成 secrets.tar.age（依赖 age）
./scripts/secrets-unlock.sh
./scripts/restore.sh backup/<时间戳>

# 监控（可选）
sudo ./monitoring/install-netdata.sh
```

## 安全与秘密管理

- `config.env`、`peers.map`、`secrets/`、`backup/`、`.age.key`、`secrets.tar.age` 均被 `.gitignore` 忽略，**不要提交到公开仓库**；
- 所有私钥只存在于：VPS `/etc/wireguard/`、各设备客户端、本地 `secrets/`；
- 备份前用 `secrets-lock.sh`（age）加密；`.age.key` 是解密唯一凭据，请离线妥善保管；
- 公钥可公开，但本项目也**不硬编码**任何公钥，全部由脚本运行时生成并写入 `peers.map`。

## 文档

- [架构说明](docs/architecture.md)
- [运维手册](docs/operations.md)
- [故障排查](docs/troubleshooting.md)
- [参考资料](docs/references.md)

## 许可证

[MIT](LICENSE)
