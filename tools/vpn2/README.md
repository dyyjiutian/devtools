# VPN2 - Xray VLESS + Reality 中继代理

基于 Xray VLESS + Reality 协议的三段式代理，专为国内访问 claude.ai 等受限站点设计。

## 架构

```
国内机器                   杭州中继 ECS               新加坡出口 ECS              目标站点
  │                      198.51.100.10              198.51.100.30               │
  │                            │                          │                      │
  │  Xray VLESS+Reality        │    iptables DNAT 转发    │  Xray VLESS+Reality  │
  ├──────────────────────────►│──────────────────────────►│─────────────────────►│
  │  (伪装 TLS 流量)            │  (纯 TCP 转发，无感知)     │  (伪装 microsoft.com) │
  │◄──────────────────────────│◄──────────────────────────│◄─────────────────────│
```

| 节点 | IP | 作用 | 技术方案 |
|------|----|------|----------|
| 中继节点 | 198.51.100.10 | 流量中转，规避国内审查对境外 IP 的封锁 | iptables DNAT（纯转发，无代理软件） |
| 出口节点 | 198.51.100.30 | 实际出境，访问 claude.ai | Xray VLESS + Reality（伪装 www.microsoft.com） |

## 为什么需要中继节点？

直接使用新加坡 ECS IP 访问 claude.ai 时，该 IP 可能因被标记而被 GFW 干扰。通过杭州中继节点（阿里云国内 ECS）转发，国内流量只与国内 IP 通信，GFW 看到的是阿里云内网流量，从而绕过封锁。

## 目录结构

```
vpn2/
├── README.md
├── exit/
│   └── setup.sh    # 新加坡出口节点：安装 Xray，配置 VLESS+Reality
├── relay/
│   └── setup.sh    # 杭州中继节点：配置 iptables DNAT 转发
└── client/
    ├── setup.sh             # 客户端：Linux（systemd）/ macOS（Homebrew + LaunchAgent）
    ├── macos-system-proxy.sh # macOS：系统代理 on | off | status（可选）
    ├── proxy-on.sh          # macOS：一键开启系统代理 → 封装 macos-system-proxy.sh on
    └── proxy-off.sh         # macOS：一键关闭系统代理 → 封装 macos-system-proxy.sh off
```

## 部署顺序

**必须按以下顺序操作：出口节点 → 中继节点 → 客户端**

---

### 第一步：部署出口节点（新加坡 ECS 198.51.100.30）

```bash
# 登录新加坡 ECS
ssh root@198.51.100.30

# 上传并执行部署脚本
sudo ./exit/setup.sh
```

脚本会自动：
- 安装 Xray-core
- 安装 Cloudflare WARP 并设置为 proxy 模式（SOCKS5 on 40000）
- 生成 UUID、Reality X25519 密钥对、Short ID
- 写入 VLESS + Reality 服务端配置（伪装 `www.microsoft.com`）
  - `anthropic.com` / `claude.ai` 流量经 WARP 出站（绕过 Cloudflare Bot 防护）
  - 其余流量直连
- 配置 systemd 服务并开放防火墙 443 端口

**记录输出中的客户端连接参数**，后续步骤需要：

```
UUID       : xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
Public Key : <base64_public_key>
Short ID   : <8_hex_chars>
```

参数同时持久化在 `/root/.vpn2_exit_config`，可随时查看：

```bash
cat /root/.vpn2_exit_config
```

阿里云控制台：放行**入方向** `TCP 443`。

---

### 第二步：部署中继节点（杭州 ECS 198.51.100.10）

```bash
# 登录杭州 ECS
ssh root@198.51.100.10

# 执行部署脚本（无需任何连接参数）
sudo ./relay/setup.sh
```

或显式指定参数（使用默认值时可省略）：

```bash
sudo ./relay/setup.sh \
  --exit-ip=198.51.100.30 \
  --exit-port=443 \
  --listen-port=443
```

脚本会自动：
- 开启内核 `net.ipv4.ip_forward`（持久化到 sysctl）
- 设置 iptables DNAT 规则（TCP 443 → 198.51.100.30:443）
- 持久化 iptables 规则（重启后自动恢复）

阿里云控制台：
- **中继 ECS 安全组**：入方向放行 `TCP 443`
- **出方向**：允许访问 `198.51.100.30:443`（通常默认放行）

---

### 第三步：部署客户端（国内机器）

**Linux**：需要 root。

```bash
sudo ./client/setup.sh \
  --relay-ip=198.51.100.10 \
  --uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  --public-key=<base64_public_key> \
  --short-id=<十六进制_short_id>
```

**macOS**：无需 sudo；依赖 [Homebrew](https://brew.sh) 安装 Xray，用户级 LaunchAgent 托管进程。

```bash
./client/setup.sh \
  --relay-ip=198.51.100.10 \
  --uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  --public-key=<base64_public_key> \
  --short-id=<十六进制_short_id>
```

脚本会自动：
- 安装或确认 Xray-core（Linux：官方安装脚本；macOS：`brew install xray`）
- 写入客户端配置（Linux：`/usr/local/etc/xray/client.json`；macOS：`$(brew --prefix)/etc/xray/client.json`）
- 暴露 SOCKS5（`127.0.0.1:10808`）和 HTTP（`127.0.0.1:10809`）
- 配置路由：国内流量直连，claude.ai 等走代理
- **macOS**：校验 UUID / Short ID 格式；启动成功后以端口监听为准（失败时打印 `/tmp/xray-client.log` 末尾）

**从 VLESS 链接填写参数**：链接形如 `vless://<UUID>@198.51.100.10:443?...&pbk=<公钥>&sid=<short_id>&...`。其中 `<UUID>` 必须完整复制（仅含十六进制与连字符）；勿在 UUID 首部多加字母（例如误把 `a2e5...` 写成 `xa2e5...` 会导致 Xray 拒绝启动）。

---

### macOS：一键开关「系统全局代理」

先确保 `./client/setup.sh` 已成功、`10808`/`10809` 在监听，再为本机某个**网络服务**（默认 **Wi‑Fi**）打开「网页代理 / 安全网页代理 / SOCKS」指向本地 Xray：

```bash
# 查看可用网络服务名（以太网、VPN、Thunderbolt 等）
./client/macos-system-proxy.sh list-services

# 开启（需管理员密码）
./client/proxy-on.sh
# 或指定网络服务（例如以太网）
./client/macos-system-proxy.sh on --service="Ethernet"

# 查看当前开关与地址
./client/macos-system-proxy.sh status

# 关闭（恢复直连）
./client/proxy-off.sh
```

也可通过环境变量覆盖端口或服务名，例如：`VPN2_PROXY_SERVICE="以太网" VPN2_SOCKS_PORT=10808 ./client/proxy-on.sh`。

**注意**：开启系统代理后，若 Xray 未运行，整机上网可能中断；离家或停用代理时请执行 `./client/proxy-off.sh`。

---

## 验证

```bash
# 客户端状态（Linux / macOS 均可用；Linux 若仅用 socks 端口检查需自行 ss）
./client/setup.sh --status

# 手动测试代理端口是否在监听（macOS）
lsof -iTCP:10808 -sTCP:LISTEN

# 通过 SOCKS 访问（浏览器访问通常正常；裸 curl 可能被 Cloudflare 返回 403，不代表代理未通）
curl -x socks5h://127.0.0.1:10808 -sSIL \
  -o /dev/null -w "HTTP %{http_code}\n" https://claude.ai/

# 测试出口 IP（可能因站点策略返回非 200，仅供参考）
curl -x socks5h://127.0.0.1:10808 -sSL https://api4.ipify.org
```

---

## 客户端方案

根据设备类型选择对应方案；参数均来自出口节点 `cat /root/.vpn2_exit_config` 或部署输出的 **VLESS 链接**。

### 方案一：Linux（shell 脚本，推荐服务器 / Linux 桌面）

在国内 Linux 机器上：

```bash
sudo ./client/setup.sh \
  --relay-ip=198.51.100.10 \
  --uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  --public-key=<base64_public_key> \
  --short-id=<十六进制_short_id>
```

本地端口：
- SOCKS5：`socks5h://127.0.0.1:10808`
- HTTP：`http://127.0.0.1:10809`

浏览器可为单个浏览器配置 SOCKS（见下文 SwitchyOmega）；全局 HTTP 代理可由桌面环境单独配置。

终端示例：

```bash
curl -x socks5h://127.0.0.1:10808 https://claude.ai/
export https_proxy=http://127.0.0.1:10809
export http_proxy=http://127.0.0.1:10809
```

---

### 方案二：macOS（shell 脚本 + 可选系统代理）

与 Linux 相同参数，**不要使用 sudo**：

```bash
./client/setup.sh \
  --relay-ip=198.51.100.10 \
  --uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  --public-key=<base64_public_key> \
  --short-id=<十六进制_short_id>
```

本地端口仍为 `10808` / `10809`。需要「系统设置 → 网络」里的全局代理时，使用仓库内脚本一键开关：

```bash
./client/proxy-on.sh          # 开启（默认 Wi‑Fi）
./client/proxy-off.sh        # 关闭
./client/macos-system-proxy.sh status
```

详见上文 **「macOS：一键开关系统全局代理」**。

---

### 方案三：macOS（可视化客户端）

推荐使用 **V2RayXS**（基于 Xray-core，对 Reality 支持较好）。

**安装 V2RayXS：**

1. 下载：[github.com/tzmax/V2RayXS/releases](https://github.com/tzmax/V2RayXS/releases) → 下载最新 `.dmg` 安装
2. 打开后菜单栏出现图标，点击 → **偏好设置** → 允许系统扩展（首次）

**导入 VLESS 链接：**

先拼好 VLESS 链接（将实际参数填入），macOS 使用 `fp=chrome`：

```
vless://<UUID>@198.51.100.10:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=<PUBLIC_KEY>&sid=<SHORT_ID>&type=tcp&headerType=none#VPN2
```

> 出口节点部署完成后脚本会自动输出完整链接（同时输出 iOS 专用版本），`<中继IP>` 替换为 `198.51.100.10`。

导入步骤：
1. 复制上面的 VLESS 链接
2. 点击菜单栏 V2RayXS 图标 → **从剪贴板导入**
3. 节点出现在列表中后，点击选中 → **启用系统代理**

备选客户端：**V2rayU**（[github.com/yanue/V2rayU](https://github.com/yanue/V2rayU)），导入方式相同。

---

### 方案四：iOS（Shadowrocket）

**安装 Shadowrocket：**

需要**非国区 Apple ID**（如美区），在 App Store 搜索 Shadowrocket，约 $2.99。

> **重要**：iOS 使用专用 VLESS 链接（`fp=ios`），不能直接用 macOS 的链接。iOS 系统无法模拟 Chrome TLS 指纹，必须使用 `fp=ios`，否则握手会失败。

**获取 iOS 专用 VLESS 链接：**

在出口节点执行 `cat /root/.vpn2_exit_config` 获取参数，然后拼接以下格式（注意 `fp=ios`）：

```
vless://<UUID>@198.51.100.10:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=ios&pbk=<PUBLIC_KEY>&sid=<SHORT_ID>&type=tcp&headerType=none#VPN2-Claude-iOS
```

重新运行 `exit/setup.sh` 也会自动输出 iOS 专用链接。

**导入 VLESS 链接：**

方式一：扫二维码
1. 在电脑上将 iOS 专用 VLESS 链接转为二维码（可用 [qrcode.tec-it.com](https://qrcode.tec-it.com) 在线生成）
2. 打开 Shadowrocket → 右上角 **+** → **扫描二维码**

方式二：复制链接
1. 在 iPhone 上复制 iOS 专用 VLESS 链接
2. 打开 Shadowrocket，顶部会提示「检测到剪贴板内容」→ 点击**添加**

方式三：手动填写
1. 打开 Shadowrocket → 右上角 **+**
2. 填写如下字段：

| 字段 | 值 |
|------|----|
| 类型 | VLESS |
| 地址 | `198.51.100.10` |
| 端口 | `443` |
| UUID | `<UUID>` |
| Flow | `xtls-rprx-vision` |
| TLS | 开启，选择 **Reality** |
| SNI | `www.microsoft.com` |
| Public Key | `<PUBLIC_KEY>` |
| Short ID | `<SHORT_ID>` |
| Fingerprint | `ios`（**注意：不是 chrome**） |

3. 保存 → 点击节点旁的连接按钮 → 允许添加 VPN 配置

**设置规则（按需代理）：**

Shadowrocket 默认全局代理。如需只代理境外流量：
- 首页 → **全局路由** → 选择**配置**（按规则分流）

---

**浏览器（按需代理）**：安装 [SwitchyOmega](https://github.com/FelisCatus/SwitchyOmega) → 情景模式 → SOCKS5 → `127.0.0.1:10808`。

---

## 服务管理

### 出口节点（新加坡）

```bash
systemctl status xray          # 查看状态
journalctl -u xray -f          # 实时日志
systemctl restart xray         # 重启
cat /root/.vpn2_exit_config    # 查看连接参数
```

### 中继节点（杭州）

```bash
iptables -t nat -L -n -v       # 查看 NAT 转发规则
cat /proc/sys/net/ipv4/ip_forward  # 验证 IP 转发
# 清除转发规则
sudo ./relay/setup.sh --clean
```

### 客户端（Linux）

```bash
systemctl status xray-client          # 查看状态
journalctl -u xray-client -f          # 实时日志
systemctl restart xray-client        # 重启
sudo ./client/setup.sh --clean       # 停止并卸载
```

配置文件：`/usr/local/etc/xray/client.json`。

### 客户端（macOS）

```bash
./client/setup.sh --status
launchctl list | grep com.vpn2.xray-client   # LaunchAgent（PID 为 - 表示未常驻成功）
tail -f /tmp/xray-client.log                # Xray 标准输出 / 错误

# 重启 Xray 客户端
launchctl unload ~/Library/LaunchAgents/com.vpn2.xray-client.plist
launchctl load -w ~/Library/LaunchAgents/com.vpn2.xray-client.plist

./client/setup.sh --clean                  # 停止并卸载（含 plist）

# 系统全局代理（networksetup）
./client/macos-system-proxy.sh status
./client/proxy-off.sh                     # 关机或停用 VPN2 前建议先关闭系统代理
```

配置文件：`$(brew --prefix)/etc/xray/client.json`（Apple Silicon 常见为 `/opt/homebrew/etc/xray/client.json`）。

---

## 安全说明

- **Reality 协议**：通过 TLS 握手伪装成访问 `www.microsoft.com` 的流量，流量特征无法与正常 HTTPS 区分
- **中继节点无感知**：杭州 ECS 仅做 TCP 转发，不解密、不存储任何流量内容
- **建议**：阿里云安全组限制 443 入方向仅允许可信客户端 IP，防止被扫描滥用
- **UUID 和私钥**：请妥善保管出口节点生成的配置，切勿公开

## 常见问题

**Q: 中继节点部署后能否复用现有 nginx SNI 代理（vpn 方案）？**

A: 两者均监听 443 端口，存在冲突。建议：
- 方案一：中继节点使用不同端口（如 `--listen-port=8443`），客户端对应修改 `--relay-port=8443`
- 方案二：中继节点为专用机器，不部署其他服务

**Q: Claude iOS App 能用但 ChatGPT/Gemini App 正常，是什么原因？**

A: 根本原因是 **Cloudflare Bot Challenge**。Claude 的服务器（`claude.ai`、`a-api.anthropic.com`）部署在 Cloudflare 后，Cloudflare 对数据中心 IP（如阿里云 ECS）的出站连接触发 `cf-mitigated: challenge`，返回需要 JS 执行的挑战页面。浏览器能通过（有 JS 引擎），iOS 原生 App 无法通过（URLSession 没有 JS 引擎），所以 App 反复得到 403 并重试。ChatGPT/Gemini 使用自有 CDN 基础设施，不经过 Cloudflare 此机制，不受影响。

解决方案：出口节点安装 Cloudflare WARP，将 Anthropic 域名流量通过 WARP（Cloudflare 自有 IP 出站），Cloudflare 不会 challenge 自家 WARP 的流量。

**Q: 出口节点重新部署会导致 UUID 和密钥变化吗？**

A: 不会。脚本会读取 `/root/.vpn2_exit_config` 缓存，复用已有参数。如需重新生成，删除该文件后重新运行。

**Q: macOS 能连上，但 iOS Shadowrocket 连不上？**

A: iOS 无法模拟 Chrome TLS 指纹，必须将 VLESS 链接中的 `fp=chrome` 改为 `fp=ios`。使用 `fp=chrome` 时 Reality 握手会在 iOS 侧失败，表现为超时或连接被重置。重新运行出口节点的 `exit/setup.sh` 会同时输出 macOS 版和 iOS 专用版 VLESS 链接。

**Q: 如何添加更多受代理站点？**

A: 编辑客户端配置（Linux：`/usr/local/etc/xray/client.json`；macOS：`$(brew --prefix)/etc/xray/client.json`），在 `routing.rules` 的 `proxy` 规则中添加域名；Linux 执行 `systemctl restart xray-client`；macOS 执行上文「重启 Xray 客户端」中的 `launchctl unload` / `load`。

**Q: macOS 上 `curl -x socks5h://127.0.0.1:10808 https://claude.ai/` 返回 403？**

A: 代理链路可能已通（浏览器访问正常即可）；裸 `curl` 易被 Cloudflare 拦截，可用 `./client/setup.sh --status` 或 `lsof -iTCP:10808 -sTCP:LISTEN` 确认本地监听。
