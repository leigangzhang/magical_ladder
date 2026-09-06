# 清理与卸载（Agent 一键 + 手动脚本）

两种方式都能清理 WireGuard 环境：从控制端（Mac）用 `agent-uninstall.sh` 远程一键清理，或直接登录 VPS 手动跑脚本。二者最终调用的都是同一套 `server/uninstall.sh` / `clients/remove-client.sh`。

| 方式 | 入口 | 适用场景 |
|---|---|---|
| Agent 一键清理 | `scripts/agent-uninstall.sh` | 人在控制端，远程编排清理 |
| 手动脚本清理 | `server/uninstall.sh` / `clients/remove-client.sh` | 直接登录 VPS 操作 |

---

## 一、Agent 一键清理

在控制端（项目根目录）运行，无需 root：

```bash
./scripts/agent-uninstall.sh                  # 全量卸载（VPS + 本地 secrets/peers.map 备份清理）
./scripts/agent-uninstall.sh macbook iphone   # 只移除指定设备
./scripts/agent-uninstall.sh --dry-run ...    # 预览，不执行
./scripts/agent-uninstall.sh --host root@vps --remote-dir /opt/magical_ladder ...
```

流程：

1. `ssh` 到 VPS 执行 `server/uninstall.sh --yes`（全量）或 `clients/remove-client.sh <设备>`（移除指定设备）；
2. 同步清理控制端本地的 `secrets/`、`peers.map` 及对应设备配置文件；
3. 打印清理结果与备份位置。

### AI Agent 指令（复制给 Claude Code / Codex / DeepSeek Harness）

```text
帮我用仓库 git@github.com:leigangzhang/magical_ladder.git 清理 WireGuard 环境。
全量卸载会停掉 VPN 并删除服务端配置，属破坏性动作，必须等我明确确认后再执行。

1. 下载仓库到控制端（已存在则跳过）：
   git clone git@github.com:leigangzhang/magical_ladder.git ~/magical_ladder
   cd ~/magical_ladder

2. 准备 SSH 免密（同部署流程：/etc/hosts、ssh-copy-id、指纹确认，遇到要密码/确认就停下等我）。

3. 生成 config.env：ENDPOINT 取 /etc/hosts 里 vpshost 的 IP；SSH_HOST=vpshost。

4. 执行前先问我确认是「全量卸载」还是「只移除某几台设备」，确认后再运行：
   - 全量：./scripts/agent-uninstall.sh
   - 只移除：./scripts/agent-uninstall.sh macbook iphone
   运行后若 SSH 中断，停下等我重连。

5. 完成后汇报：VPS 侧已卸载/移除的内容，以及本地 secrets、peers.map 的备份位置。
```

---

## 二、手动脚本清理（登录 VPS 以 root 执行）

### 2.1 全量卸载

```bash
sudo ./server/uninstall.sh --yes
sudo ./server/uninstall.sh --yes --dry-run   # 先预览
```

会依次：

1. `wg-quick down wg0` 并 `systemctl disable wg-quick@wg0`；
2. 备份 `/etc/wireguard` 到 `/root/wireguard-backup-<时间戳>.tar.gz` 后删除；
3. 删除 WG 端口的 ufw 放行（**保留 OpenSSH**）；
4. 把项目里的 `secrets/`、`peers.map` 改名备份（`secrets.bak-<时间戳>`、`peers.map.bak-<时间戳>`）。

> `net.ipv4.ip_forward` 与 OpenSSH 防火墙规则保持原样，如需关闭请手动处理。

### 2.2 移除一个或多个设备

```bash
sudo ./clients/remove-client.sh alice bob          # 按名字
sudo ./clients/remove-client.sh 10.8.0.3           # 按隧道 IP
sudo ./clients/remove-client.sh vfoZUVse...=       # 按公钥（完整值或唯一前缀）
sudo ./clients/remove-client.sh alice --dry-run    # 预览
```

会同步：从 `wg0.conf` 删除对应 `[Peer]` 段 → `wg syncconf` 热应用（其他在线设备不受影响）→ 清理 `peers.map` → 删除 `secrets/<名字>.conf/.png`。

> 按名字/隧道 IP 解析依赖项目根目录的 `peers.map`（由 `add-client.sh` 维护）；公钥可直接给完整值或唯一前缀。

---

## 三、清理产物与备份位置

| 产物 | 位置 |
|---|---|
| 服务端配置备份 | VPS `/root/wireguard-backup-<时间戳>.tar.gz` |
| 本地 secrets 备份 | 项目 `secrets.bak-<时间戳>/` |
| 本地 peers.map 备份 | 项目 `peers.map.bak-<时间戳>` |

如需完全移除，确认无误后再删除上述备份。

## 四、需要人工接管的点

| 步骤 | 需人工介入 | Agent 应如何等待 |
|---|---|---|
| SSH 免密准备 | sudo 密码 / ssh-copy-id 密码 / 指纹确认 | 停下等人操作/确认 |
| 全量卸载 | 破坏性动作 | 等人在指令里明确授权 |
| 卸载执行中 | 可能中断 SSH（全隧道控制端） | 断开即停下等人重连 |
| 清理确认 | 是否删除本地 secrets/备份 | 列出备份位置等人决定 |

## 五、安全注意

- 私钥只存在于 VPS `/etc/wireguard`、各设备、本地 `secrets/`，**不提交仓库**；
- 全量卸载前务必确认 `/root/wireguard-backup-*.tar.gz` 备份已生成；
- 卸载不会自动关闭 `net.ipv4.ip_forward`，也不会删除 OpenSSH 防火墙规则，如需彻底还原请手动处理。

> 相关：日常增删设备、密钥轮换见 [operations.md](operations.md)；部署流程见 [agent-deploy.md](agent-deploy.md)。
