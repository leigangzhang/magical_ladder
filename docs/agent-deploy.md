# Agent 驱动安装与配置流程

从你的**控制端（如 Mac）**远程编排，自动完成：把项目同步到 VPS → 安装服务端 → 为每台终端生成独立配置 → 拉回配置文件/二维码，最后在每台设备上导入。

```
控制端(Mac, Agent) ──ssh──▶ VPS：install.sh / add-client.sh
      ▲                              │
      └──scp 拉回 secrets/<设备>.conf/.png
                                      ▼
                          分发到各终端（macOS / iOS / Android 导入）
```

## 一、前置条件

1. 控制端能**免密 SSH** 到 VPS：

   ```bash
   # 本机没有密钥则先生成
   ssh-keygen -t ed25519 -C "你的备注"
   # 把公钥装上 VPS（之后 ssh root@vps 不再要密码）
   ssh-copy-id root@vps
   ```

2. 控制端有本项目（`magical_ladder/`）且已配置 `config.env`：

   ```bash
   cd magical_ladder
   cp config.env.example config.env
   vim config.env      # ENDPOINT、SERVER_V4 等按需填写
   ```

3. VPS 上无需预装 git —— 脚本会用 rsync/scp 把仓库同步过去（见下）。

## 二、一键编排（推荐）

用仓库自带的 `scripts/agent-deploy.sh`，在控制端执行：

```bash
# 基本用法：默认从 config.env 读 SSH_HOST，安装服务端 + 3 台设备
./scripts/agent-deploy.sh macbook=10.8.0.2 mac-mini=10.8.0.3 iphone=10.8.0.4

# 指定主机 / 远端目录 / 预览（只打印不执行）
./scripts/agent-deploy.sh --host root@vps --remote-dir /opt/magical_ladder \
    --devices "macbook=10.8.0.2 iphone" --dry-run
```

脚本做的事：

1. `rsync` 把本地项目同步到 `VPS:/opt/magical_ladder`（排除 `.git`、`secrets`、`backup`）；
2. 在 VPS 上执行 `./server/install.sh`（幂等，装依赖 + 生成密钥 + 起 wg0 + 防火墙）；
3. 对每个 `<名字>=<IP>` 执行 `./clients/add-client.sh`（省略 IP 则自动分配）；
4. `scp` 把 VPS 上的 `secrets/<名字>.conf` 与二维码拉回本机 `secrets/`；
5. 打印每台设备的配置路径与公钥。

## 三、手动逐步等效命令（不用脚本时）

```bash
# 1) 同步仓库到 VPS
rsync -az --delete --exclude=.git --exclude=secrets --exclude=backup ./ root@vps:/opt/magical_ladder/

# 2) 安装服务端
ssh root@vps 'cd /opt/magical_ladder && ./server/install.sh'

# 3) 为每台终端生成配置
ssh root@vps 'cd /opt/magical_ladder && ./clients/add-client.sh macbook 10.8.0.2'
ssh root@vps 'cd /opt/magical_ladder && ./clients/add-client.sh iphone'    # 自动分配 IP

# 4) 拉回配置与二维码
scp root@vps:/opt/magical_ladder/secrets/ ./secrets/
```

## 四、把配置分发到各终端

| 终端 | 导入方式 |
|---|---|
| macOS（本机/其他 Mac） | 把 `secrets/<名字>.conf` 拖进 WireGuard App，或 `sudo cp ... /etc/wireguard/wg0.conf && sudo wg-quick up wg0` |
| iOS / Android | 隔空投送/微信/邮件发 `secrets/<名字>.conf`，用 WireGuard 打开；或另一屏显示 `secrets/<名字>.png` 扫码 |

> 每台终端必须使用**各自**的 `secrets/<名字>.conf`，切勿复制同一份到多台设备（会因私钥/IP 冲突互相踢下线）。详见 [examples/ios-android-import.md](examples/ios-android-import.md)。

## 五、安全注意

- `config.env` 里只有 ENDPOINT/IP/DNS 等参数、**不含密钥**，可安全经 SSH 同步；
- 私钥只在 VPS `/etc/wireguard`、各设备、以及本机 `secrets/` 中，**不要提交到仓库**；
- 传输走的都是 SSH/SCP（已加密），无需额外加 TLS；
- 拉回本机的 `secrets/` 与 VPS 上的 `secrets/` 都已被 `.gitignore` 忽略。

## 六、常见问题

- **`ssh: connect to host ... port 22: Connection refused`**：VPS 的 sshd 未开或 22 端口防火墙没放行；
- **`rsync: command not found`**：控制端没有 rsync，可改用手动流程里的 `scp -r` 同步；
- **`config.env` 未配置**：先 `cp config.env.example config.env` 并填 `ENDPOINT`；
- **add-client 报「设备名已存在」**：`peers.map` 里已有同名，换名或用 `clients/remove-client.sh` 先移除；
- **设备连不上**：确认服务端 `./scripts/show-peers.sh` 能看到该设备出现 endpoint 与握手。

## 七、需要人工接管的地方（Agent 应停下等待）

| 阶段 | 需人工介入的点 | Agent 应如何等待 |
|---|---|---|
| 控制端准备 | 写 `/etc/hosts` 需 sudo 密码 | 停下，给出命令等人执行 |
| 控制端准备 | `ssh-keygen` 是否复用密钥/设 passphrase | 停下让人确认 |
| 控制端准备 | `ssh-copy-id` 首次输 VPS root 密码 | 停下等人输入 |
| 首次 SSH | 主机指纹 `yes/no` 确认 | 停下等人确认，不要自动 yes |
| 首次 SSH | 未免密时 `ssh root@vps` 要密码 | 停下等人输入 |
| 参数决策 | 隧道网段 / DNS / 是否 IPv6 | 列默认值等人确认无冲突 |
| 服务端安装 | `ufw enable` / `wg-quick up` 可能中断 SSH | 每步后探测连通性，断则等人重连 |
| 分发接入 | macOS GUI 导入 + 打开开关 | GUI 操作，等人完成 |
| 分发接入 | iOS/Android 扫码/导入 | 必须人在设备上操作 |
| 清理 | 全量卸载（破坏性） | 等人在指令里明确授权后再执行 |
| 通用 | 私钥提交/任何不可逆删除 | 停下求确认 |

核心原则：**要密码、要确认指纹、要在别的设备上手动操作、不可逆删除 —— 这四类一律停下等待人工接管**，不要自动跳过或失败重试。
