# WireGuard VPN 分流方案

基于新加坡 ECS 搭建的 WireGuard VPN，实现**智能分流**：访问海外网络走 VPN 隧道，访问国内网络直连，支持 macOS / Linux / iOS 三端。

## 工作原理

```
                        ┌─────────────────────────────────────┐
客户端（中国）            │         新加坡 ECS                   │
   │                    │   wg0: 10.8.0.1/24                  │
   │  海外流量            │                                     │      海外互联网
   ├──── WireGuard ─────►│─── NAT MASQUERADE ──────────────────►  Google/GitHub/...
   │   (非中国 IP)        │                                     │
   │                    └─────────────────────────────────────┘
   │  国内流量
   └──── 直连 ───────────────────────────────────────────────►  百度/淘宝/...
```

**分流机制**：WireGuard 客户端的 `AllowedIPs` 只包含**非中国 IP 段**（由 APNIC WHOIS 数据计算补集得出），国内 IP 流量不经过隧道，直接走本地网络出口。

**DNS 处理**：DNS 查询走隧道（使用 `8.8.8.8`），DNS 解析得到的 IP 再按分流规则路由，对国内站点无影响。

## 目录结构

```
vpn/
├── README.md
├── server/
│   └── setup.sh              # 服务端一键部署
├── client/
│   ├── gen_config.sh         # 生成客户端配置（含分流路由）
│   ├── setup_macos.sh        # macOS 一键安装
│   ├── setup_linux.sh        # Linux 一键安装
│   ├── ios_qr.sh             # iOS 二维码生成
│   └── output/               # 生成的 .conf 文件（git-ignored）
└── scripts/
    ├── update_cn_ips.sh      # 下载/更新中国 IP 段（APNIC）
    └── cn_cidr_complement.py # 计算非中国 AllowedIPs（Python 3）
```

## 快速部署

### 第一步：服务端（新加坡 ECS）

```bash
# 克隆仓库到服务器
git clone <repo> && cd devtools/tools/vpn

# 一键部署
sudo ./server/setup.sh

# 预览（不执行）
sudo ./server/setup.sh --dry-run
```

**阿里云 ECS 控制台**：安全组入方向放行 `UDP 51820`（建议限制来源 IP 为个人/公司 IP 段）。

部署完成后输出服务端公钥，记下备用：
```
Server public key: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=
```

---

### 第二步：生成客户端配置（**在服务器上执行**）

> 必须在服务器上运行，原因：需要读取 `/etc/wireguard/server_public.key` 并将客户端 `[Peer]` 块写入服务端 `wg0.conf`。

每台设备生成一份独立配置，配置中自动包含分流路由（约 12000 条非中国 CIDR）：

```bash
# 为 MacBook 生成配置（自动分配 10.8.0.2）
sudo ./client/gen_config.sh --name macbook --server-ip <ECS_PUBLIC_IP>

# 为手机生成配置（自动分配 10.8.0.3）
sudo ./client/gen_config.sh --name phone --server-ip <ECS_PUBLIC_IP>

# 强制刷新中国 IP 列表
sudo ./client/gen_config.sh --name desktop --server-ip <ECS_PUBLIC_IP> --refresh-ips
```

生成的配置文件在服务器的 `client/output/wg_<name>.conf`，**需要安全传输到对应客户端设备**：

```bash
# 在 Mac / Linux 客户端上执行，从服务器拉取配置
scp user@<ECS_PUBLIC_IP>:~/devtools/tools/vpn/client/output/wg_macbook.conf ./

# 或用 cat 复制后在客户端粘贴保存
ssh user@<ECS_PUBLIC_IP> "cat ~/devtools/tools/vpn/client/output/wg_macbook.conf"
```

---

### 第三步：各端安装

#### macOS

**方案 A：命令行（wireguard-tools）**

```bash
# 将 conf 文件拷贝到 Mac，然后执行：
sudo ./client/setup_macos.sh --config client/output/wg_macbook.conf

# 开机自动连接
sudo ./client/setup_macos.sh --config client/output/wg_macbook.conf --autostart

# 断开并清理
./client/setup_macos.sh --clean
```

**方案 B：WireGuard App（推荐 GUI 用户）**

1. App Store 搜索并安装「[WireGuard](https://apps.apple.com/app/wireguard/id1451685025)」
2. 打开 App → File → Import tunnel(s) from file
3. 选择 `wg_macbook.conf` 文件导入
4. 点击开关连接

常用命令：
```bash
sudo wg show wg0             # 查看状态
sudo wg-quick up wg0         # 连接
sudo wg-quick down wg0       # 断开
```

---

#### Linux

```bash
# 将 conf 文件拷贝到 Linux 机器，然后执行：
sudo ./client/setup_linux.sh --config client/output/wg_desktop.conf

# 开机自动连接（systemd）
sudo ./client/setup_linux.sh --config client/output/wg_desktop.conf --autostart

# 断开并清理
sudo ./client/setup_linux.sh --clean
```

常用命令：
```bash
sudo wg show wg0                          # 查看状态
sudo systemctl start wg-quick@wg0        # 连接
sudo systemctl stop  wg-quick@wg0        # 断开
journalctl -u wg-quick@wg0 -f            # 实时日志
```

---

#### iOS

1. App Store 安装「[WireGuard](https://apps.apple.com/app/wireguard/id1441195209)」

2. 在服务器上生成 iOS 专属配置并显示二维码：

```bash
# 生成 iOS 配置
sudo ./client/gen_config.sh --name iphone --server-ip <ECS_PUBLIC_IP>

# 生成二维码（需要 qrencode）
./client/ios_qr.sh --config client/output/wg_iphone.conf

# 同时保存 PNG 图片
./client/ios_qr.sh --config client/output/wg_iphone.conf --output iphone_qr.png
```

安装 qrencode（如未安装）：
```bash
# 服务端（Alibaba Cloud Linux / CentOS）
sudo dnf install -y qrencode

# macOS
brew install qrencode
```

3. iPhone 打开 WireGuard App → 点击「+」→「Create from QR code」→ 扫码导入
4. 允许添加 VPN 配置（系统弹窗）
5. 开关打开即连接

---

## 验证分流效果

连接 VPN 后：

```bash
# 海外出口（应显示新加坡 IP）
curl -s https://ifconfig.me

# 国内访问（应正常直连，不走 VPN）
curl -s --max-time 5 http://www.baidu.com -o /dev/null -w '%{http_code}\n'

# 路由验证：Google 走 VPN，百度走直连
traceroute 8.8.8.8      # 第一跳应为 10.8.0.1（VPN 服务器）
traceroute 14.215.177.38 # 第一跳应为本地网关（直连）
```

---

## 添加新客户端

```bash
# 在服务器上执行（自动追加 [Peer] 到 wg0.conf 并热重载）
sudo ./client/gen_config.sh --name newdevice --server-ip <ECS_PUBLIC_IP>

# 手动热重载（不中断现有连接）
sudo wg syncconf wg0 <(wg-quick strip wg0)
```

---

## 更新中国 IP 段

中国 IP 段由 APNIC 每日更新。建议定期重新生成客户端配置以保持分流规则最新：

```bash
# 手动更新（强制重新下载）
./scripts/update_cn_ips.sh --force --output /tmp/cn_cidrs_new.txt

# 定时任务：每月重新生成所有客户端配置（在服务器上）
# crontab -e
# 0 2 1 * * cd /path/to/devtools/tools/vpn && sudo ./client/gen_config.sh --name macbook --server-ip <IP> --refresh-ips
```

---

## 服务管理

```bash
# 服务端状态
sudo wg show wg0
sudo systemctl status wg-quick@wg0

# 查看已连接客户端及流量
sudo wg

# 重启服务
sudo systemctl restart wg-quick@wg0

# 查看实时日志
journalctl -u wg-quick@wg0 -f
```

---

## 安全建议

- **ECS 安全组**：UDP 51820 来源 IP 限制为个人/公司 IP 段，而不是 `0.0.0.0/0`
- **密钥文件**：`/etc/wireguard/*.key` 权限为 600，仅 root 可读
- **定期轮换**：如有客户端丢失/失效，在 `wg0.conf` 删除对应 `[Peer]` 并 reload
- **客户端 .conf**：含私钥，勿上传 git 或公开传输（`client/output/` 已加入 .gitignore）

---

## 技术说明

| 项目 | 值 |
|------|-----|
| 协议 | WireGuard (UDP) |
| 服务端口 | 51820/UDP |
| VPN 子网 | 10.8.0.0/24 |
| 服务端 VPN IP | 10.8.0.1 |
| 客户端 VPN IP | 10.8.0.2 起自动递增 |
| DNS | 8.8.8.8（走隧道，解析不受 GFW 干扰） |
| 分流数据源 | APNIC delegated-apnic-latest（每日更新） |
| 分流方式 | AllowedIPs = 全球 IP - 中国 IP 补集 |
| 国内 IP 条目 | ~8800 条 CIDR |
| AllowedIPs 条目 | ~12000 条（补集，WireGuard 内核路由表可正常处理） |
