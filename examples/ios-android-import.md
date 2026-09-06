# iOS / Android 导入指南

## 方式 A：扫码（推荐，iOS 最省事）

1. 把 `secrets/<设备名>.png` 在另一台设备屏幕上打开；
2. 打开 WireGuard App → 点 **+** → 选“从二维码创建/扫描”；
3. 对准二维码扫描 → 命名 → 打开开关。

## 方式 B：导入 .conf 文件

1. 把 `secrets/<设备名>.conf` 通过隔空投送/微信/邮件/网盘发到设备；
2. 用 WireGuard App 打开该文件 → 保存 → 激活。

## 方式 C：手动填写

在 App 里创建空隧道，逐项填写：

- **接口/Interface**
  - 私钥 PrivateKey：`secrets/<设备名>.conf` 里的 `PrivateKey`
  - 地址 Address：对应 `Address`（如 `10.8.0.2/24`）
  - DNS：`CLIENT_DNS`
- **对端/Peer**
  - 公钥 PublicKey：服务端公钥（`install.sh` 输出 / `secrets/<设备名>.conf` 里的 `PublicKey`）
  - AllowedIPs：`0.0.0.0/0`
  - Endpoint：`ENDPOINT:WG_PORT`
  - PersistentKeepalive：`25`

## 注意事项

- **每台设备用自己独一份配置**，绝不复制另一台设备的配置（否则会因私钥/IP 冲突而互相踢下线）；
- 若设备上存在旧隧道，请先删除/停用，只保留新的这一个；
- 连接后在设备浏览器访问 `https://ipleak.net` 确认出口 IP 是 VPS 公网 IP；
- 服务端 `./scripts/show-peers.sh` 能看到该设备出现 endpoint 与握手，即成功。
