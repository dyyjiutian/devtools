# VPN - Xray VLESS + Reality 中继代理

基于 Xray VLESS + Reality 协议的三段式代理，专为国内访问 claude.ai 等受限站点设计。

## 架构

```
国内机器                   杭州中继 ECS               新加坡出口 ECS              目标站点
  │                      198.51.100.10              198.51.100.30               │
  │                            │                          │                      │
  │  Xray VLESS+Reality        │    iptables DNAT 转发    │  Xray VLESS+Reality  │
  ├──────────────────────────►│──────────────────────────►│─────────────────────►│
  │  (伪装 TLS 流量)            │  (纯 TCP 转发，无感知)     │  (伪装 icloud.com)    │
  │◄──────────────────────────│◄──────────────────────────│◄─────────────────────│
```

| 节点 | IP | 作用 | 技术方案 |
|------|----|------|----------|
| 中继节点 | 198.51.100.10 | 流量中转，规避国内审查对境外 IP 的封锁 | iptables DNAT（纯转发，无代理软件） |
| 出口节点 | 198.51.100.30 | 实际出境，访问 claude.ai | Xray VLESS + Reality（伪装 www.icloud.com） |

## 为什么需要中继节点？

直接使用新加坡 ECS IP 访问 claude.ai 时，该 IP 可能因被标记而被 GFW 干扰。通过杭州中继节点（阿里云国内 ECS）转发，国内流量只与国内 IP 通信，GFW 看到的是阿里云内网流量，从而绕过封锁。

## 目录结构

```
vpn/
├── README.md
├── exit/
│   ├── setup.sh           # 新加坡出口节点：安装 Xray，配置 VLESS+Reality（支持多用户）
│   └── manage.sh          # 用户管理：新增/移除用户、流量统计、配额控制
├── relay/
│   └── setup.sh           # 杭州中继节点：配置 iptables DNAT 转发
└── client/
    ├── linux_setup.sh       # Linux 客户端一体化脚本：install / status / clean / proxy
    ├── macos_setup.sh       # macOS 客户端一体化脚本：install / status / clean / proxy
    ├── install-setproxy.sh  # 安装独立的 setproxy 命令到 ~/.local/bin
    ├── bin/setproxy         # 自包含的 setproxy 命令：on / off / status / test
    └── pac.js               # PAC 智能分流规则（供 V2RayXS / V2rayU 等 GUI 客户端）
```

## 部署顺序

**必须按以下顺序操作：出口节点 → 中继节点 → 客户端**

---

### 第一步：部署出口节点（新加坡 ECS 198.51.100.30）

```bash
# 登录新加坡 ECS
ssh root@198.51.100.30

# 单用户（默认，创建 user1）
sudo ./exit/setup.sh

# 多用户：一次创建多个用户（每人独立 UUID / VLESS 链接）
sudo ./exit/setup.sh --users=alice,bob,carol

# 也可传数字：--users=3 → 创建 user1 user2 user3
sudo ./exit/setup.sh --users=3
```

脚本会自动：
- 安装 Xray-core
- 安装 Cloudflare WARP 并设置为 proxy 模式（SOCKS5 on 40000）
- 生成 Reality X25519 密钥对、Short ID，以及每用户独立 UUID
- 写入 VLESS + Reality 服务端配置（伪装 `www.icloud.com`）
  - `anthropic.com` / `claude.ai` 流量经 WARP 出站（绕过 Cloudflare Bot 防护）
  - 其余流量直连
  - **Stats API** 监听 `127.0.0.1:10085`，用于流量统计与配额控制
- 配置 systemd 服务并开放防火墙 443 端口

每个用户对应一条独立 VLESS 链接，部署完成后脚本逐用户打印。

参数持久化在 `/root/.vpn_exit_config`，可随时查看：

```bash
cat /root/.vpn_exit_config
```

阿里云控制台：放行**入方向** `TCP 443`。

#### 多用户日常管理（manage.sh）

```bash
# 列出所有用户 + 流量统计
sudo ./exit/manage.sh list

# 新增用户（立即生效，输出 VLESS 链接）
sudo ./exit/manage.sh add carol

# 移除用户（立即踢出，Xray 热重载，无需重启）
sudo ./exit/manage.sh remove bob

# 打印某用户的 VLESS 链接
RELAY_IP=198.51.100.10 sudo ./exit/manage.sh vless alice

# 查看流量统计
sudo ./exit/manage.sh stats
sudo ./exit/manage.sh stats alice

# 设置月流量配额（超限自动移除，0 = 无限制）
sudo ./exit/manage.sh quota alice 50

# 安装每小时配额巡检 cron（超限用户自动踢出）
sudo ./exit/manage.sh install-cron

# 重置流量计数（all 会重启 Xray）
sudo ./exit/manage.sh reset-stats all
sudo ./exit/manage.sh reset-stats alice
```

**流量控制说明：**
- 统计基于 Xray Stats API，按用户 email（`alice@vpn`）分项记录上行/下行流量
- 配额单位为 GB，`check-quotas` 子命令检查所有设有配额的用户，超限者从配置移除并热重载 Xray
- `install-cron` 将 `check-quotas` 注册为每小时 cron，日志写入 `/var/log/vpn-quota.log`
- 流量统计从 Xray 上次重启开始累计；月初重置可执行 `sudo ./exit/manage.sh reset-stats all`

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

根据设备类型选择对应方案。参数均来自出口节点 `cat /root/.vpn_exit_config` 或部署输出的 **VLESS 链接**。

> macOS 桌面用户**优先推荐方案 A（V2RayXS 白屏化 GUI）**，无需运行任何 shell 脚本。
> 服务器 / Linux / 不想用 GUI 的高级用户使用方案 B / C。

---

## 方案 A：macOS — V2RayXS（推荐，白屏化 GUI）

**V2RayXS** 是基于 Xray-core 的 macOS 菜单栏客户端，对 Reality 协议支持良好，**导入 VLESS 链接 + 启用系统代理**即可使用，无需任何命令行操作。

### 1. 安装 V2RayXS

从 [github.com/tzmax/V2RayXS/releases](https://github.com/tzmax/V2RayXS/releases) 下载最新 `.dmg`，安装后菜单栏出现图标。首次启动需在「系统设置 → 隐私与安全性」允许其系统扩展。

### 2. 导入 VLESS 链接

先把出口节点输出的参数拼成 VLESS 链接（macOS 使用 `fp=chrome`）：

```
vless://<UUID>@198.51.100.10:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.icloud.com&fp=chrome&pbk=<PUBLIC_KEY>&sid=<SHORT_ID>&type=tcp&headerType=none#VPN
```

> 出口节点部署完成后脚本会自动输出完整链接，复制即可。

操作：
1. 复制 VLESS 链接
2. 菜单栏 V2RayXS 图标 → **从剪贴板导入**
3. 节点列表中选中该节点 → **启用系统代理**

### 3. （可选）启用 PAC 智能分流

仓库内 `client/pac.js` 内置了常见境外站点和 AI 服务规则（Claude / OpenAI / Gemini / GitHub / Google / Twitter 等数百条）：

1. 菜单栏 V2RayXS → **PAC 设置** → 选择「使用自定义 PAC 文件」
2. 浏览选择本仓库的 `client/pac.js`
3. 切换到「PAC 模式」即生效，国内站点直连、命中规则的境外站点走代理

`pac.js` 中的 `${V2RAYXS_SOCKS}` / `${V2RAYXS_HTTP}` 占位符会被 V2RayXS 自动替换为实际本地端口。

**备选 GUI**：[V2rayU](https://github.com/yanue/V2rayU)，导入流程相同。

---

## 方案 B：Linux（systemd + 终端代理）

在国内 Linux 机器上，两种方式二选一（不能同时使用）：

```bash
# 方式一：--vless= 直接传入出口节点输出的完整 VLESS 链接（务必用引号包裹，避免 shell 把 & 当作后台执行符）
sudo ./client/linux_setup.sh install \
  --vless="vless://<UUID>@198.51.100.10:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.icloud.com&fp=chrome&pbk=<PUBLIC_KEY>&sid=<SHORT_ID>&type=tcp&headerType=none#标签"

# 方式二：手动指定三个必需参数
sudo ./client/linux_setup.sh install \
  --relay-ip=198.51.100.10 \
  --uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  --public-key=<base64_public_key> \
  --short-id=<十六进制_short_id>
```

若同时传入 `--vless` 与 `--uuid` / `--public-key` / `--short-id` 中任意一个，脚本会报错退出。
`--vless` 会自动解析 UUID、中继 `host:port`、`pbk`、`sid`、`sni`、`fp`、`flow`、`spx`；`--relay-ip=` / `--relay-port=` 等其他可选参数仍可与 `--vless` 一起使用（例如中继节点做了端口转发，只需 `--vless="..." --relay-port=8443`）。

脚本会自动：
- 安装 Xray-core（官方脚本失败时回退到 ghfast.top / jsdelivr / mirror.ghproxy.com 镜像）
- 下载 geoip.dat / geosite.dat 路由数据（jsdelivr CDN 镜像）
- 写入 `/usr/local/etc/xray/client.json`
- 暴露 SOCKS5（`127.0.0.1:10808`）和 HTTP（`127.0.0.1:10809`）
- 配置 systemd 服务 `xray-client` 并设为开机自启
- 配置路由：国内直连，claude.ai / anthropic.com 走代理

本地端口：
- SOCKS5：`socks5h://127.0.0.1:10808`
- HTTP：`http://127.0.0.1:10809`

**一键开关终端环境变量代理**（写入 `~/.config/vpn/proxy.env` + 自动加载到 `~/.bashrc` / `~/.zshrc`）：

```bash
./client/linux_setup.sh proxy on        # 新开终端自动生效
./client/linux_setup.sh proxy off       # 关闭
./client/linux_setup.sh proxy status    # 查看代理状态 + 端口监听 + xray 日志查看方式
./client/linux_setup.sh proxy test      # 测试常用站点连通性 + 海外/国内基准测速
```

`proxy test` 会检查：
- 常用站点连通性（不依赖当前 shell 是否已 `source` 过代理变量）：
  - 经代理（SOCKS）：`google.com` / `github.com` / `raw.githubusercontent.com` / `docker.io` / `claude.ai`（403 也视为代理已通）
  - 经代理（HTTP）：`api4.ipify.org`
  - 直连（验证国内站点走的是直连，不进隧道）：`www.baidu.com`
- 基准测速（仅供粗略参考，实际速度随中继/出口节点负载波动）：
  - 海外：经代理下载 OVH 提供的 1MB 测试文件
  - 国内：直连下载阿里云镜像文件

让**当前**终端立即生效：

```bash
source ./client/linux_setup.sh proxy on
# 或
eval "$(./client/linux_setup.sh proxy on --emit)"
```

终端示例：

```bash
curl -x socks5h://127.0.0.1:10808 https://claude.ai/
export https_proxy=http://127.0.0.1:10809
export http_proxy=http://127.0.0.1:10809
```

浏览器可为单个浏览器配置 SOCKS（见下文 SwitchyOmega）；桌面环境的全局 HTTP 代理可单独配置。

#### 更方便的用法：全局 `setproxy` 命令（可选）

不想每次都敲完整路径 `./client/linux_setup.sh proxy ...`？可以安装一个自包含的
`setproxy` 命令到 `~/.local/bin`，之后在**任意目录**下都能直接使用，且删除本
仓库后依然可用（原理与 `vcs/git/bin` 下的 `git rb` 等子命令一致）：

```bash
./client/install-setproxy.sh          # 安装到 ~/.local/bin（自动加入 PATH）
./client/install-setproxy.sh --dry-run    # 仅预览
./client/install-setproxy.sh --uninstall  # 卸载

# 新开终端后即可直接使用（临时启用/禁用只需 on / off）：
setproxy on                    # 终端 HTTP/HTTPS/SOCKS 代理；Git SSH 与 Docker 不受影响
setproxy on --git-ssh          # 额外让 Git SSH 通过本地 SOCKS5
setproxy on --docker-daemon    # 额外写入 Docker daemon.json 的 HTTP 代理
setproxy on --dnf-proxy        # 额外写入 dnf 的 HTTP 下载代理
setproxy off
setproxy status   # 查看代理状态 + 端口监听 + xray 日志查看方式
setproxy test     # 测试常用站点连通性 + 海外/国内基准测速
```

`setproxy` 与 `linux_setup.sh proxy` 管理的是同一份配置文件
（`~/.config/vpn/proxy.env`），两者可互操作、随意混用。

在安装了 dnf 的 Linux 上，`setproxy on --dnf-proxy` 会通过 `sudo` 在
`/etc/dnf/dnf.conf` 写入 HTTP 代理，因此安装软件也能走本地代理；普通的
`setproxy on` 不修改 dnf。只要存在由 setproxy 管理的状态，`setproxy off` 就会
自动恢复写入前的 dnf 代理配置，无需再次传 `--dnf-proxy`。若该项配置期间被
手动或被其他工具修改，`setproxy off` 会保留当前值并提示，避免覆盖用户修改。

---

## 方案 C：macOS（命令行 Xray，不想用 GUI 时）

**与方案 A 二选一**——只有在你偏好命令行 / LaunchAgent 托管 / 没有图形界面时再使用本方案。

不要使用 sudo；依赖 [Homebrew](https://brew.sh)：

```bash
./client/macos_setup.sh install \
  --relay-ip=198.51.100.10 \
  --uuid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  --public-key=<base64_public_key> \
  --short-id=<十六进制_short_id>
```

脚本会自动：
- 通过 `brew install xray` 安装 Xray-core（默认走阿里云 Homebrew bottle 镜像）
- 写入 `$(brew --prefix)/etc/xray/client.json`
- 用户级 LaunchAgent（`~/Library/LaunchAgents/com.vpn.xray-client.plist`）托管进程并设为登录自启
- 校验 UUID / Short ID 格式；启动成功后以 SOCKS 端口监听为准（失败时打印 `/tmp/xray-client.log` 末尾）

**一键开关「系统全局代理」**（macOS 系统设置 → 网络 → 当前服务的网页代理 / 安全网页代理 / SOCKS 三项一并设置）：

```bash
# 列出可用网络服务名（Wi-Fi / Ethernet / Thunderbolt Bridge ...）
./client/macos_setup.sh proxy list-services

# 开启（默认 Wi-Fi，需管理员密码）
./client/macos_setup.sh proxy on
# 指定网络服务
./client/macos_setup.sh proxy on --service="Ethernet"

# 查看 / 关闭
./client/macos_setup.sh proxy status
./client/macos_setup.sh proxy off
```

也可用环境变量覆盖：`VPN_PROXY_SERVICE="以太网" VPN_SOCKS_PORT=10808 ./client/macos_setup.sh proxy on`。

**注意**：开启系统代理后，若 Xray 未运行，整机上网可能中断；离家或停用代理时请执行 `./client/macos_setup.sh proxy off`。

---

## 方案 D：iOS（Shadowrocket）

**安装 Shadowrocket：** 需要**非国区 Apple ID**（如美区），App Store 搜索 Shadowrocket，约 $2.99。

> **重要**：iOS 使用专用 VLESS 链接（`fp=ios`），不能直接用 macOS 的链接。iOS 系统无法模拟 Chrome TLS 指纹，必须使用 `fp=ios`，否则握手会失败。

**获取 iOS 专用 VLESS 链接：**

在出口节点执行 `cat /root/.vpn_exit_config` 获取参数，然后拼接（注意 `fp=ios`）：

```
vless://<UUID>@198.51.100.10:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.icloud.com&fp=ios&pbk=<PUBLIC_KEY>&sid=<SHORT_ID>&type=tcp&headerType=none#VPN-Claude-iOS
```

重新运行 `exit/setup.sh` 也会自动输出 iOS 专用链接。

**导入 VLESS 链接（三选一）：**

- **扫二维码**：电脑端将链接转为二维码（[qrcode.tec-it.com](https://qrcode.tec-it.com)）→ Shadowrocket 右上角 **+** → **扫描二维码**
- **复制链接**：iPhone 上复制 → 打开 Shadowrocket → 顶部「检测到剪贴板内容」→ **添加**
- **手动填写**：Shadowrocket 右上角 **+**，逐字段填写：

| 字段 | 值 |
|------|----|
| 类型 | VLESS |
| 地址 | `198.51.100.10` |
| 端口 | `443` |
| UUID | `<UUID>` |
| Flow | `xtls-rprx-vision` |
| TLS | 开启，选择 **Reality** |
| SNI | `www.icloud.com` |
| Public Key | `<PUBLIC_KEY>` |
| Short ID | `<SHORT_ID>` |
| Fingerprint | `ios`（**注意：不是 chrome**） |

保存 → 点击节点旁的连接按钮 → 允许添加 VPN 配置。

**按需代理**：Shadowrocket 默认全局代理。如需仅代理境外流量：首页 → **全局路由** → 选择**配置**（按规则分流）。

---

### 浏览器（按需代理）

无论 macOS / Linux，桌面浏览器都可装 [SwitchyOmega](https://github.com/FelisCatus/SwitchyOmega)：情景模式 → SOCKS5 → `127.0.0.1:10808`。

---

## 验证

```bash
# Linux
./client/linux_setup.sh status

# macOS（命令行方案）
./client/macos_setup.sh status

# 手动测试代理端口是否在监听
# macOS:
lsof -iTCP:10808 -sTCP:LISTEN
# Linux:
ss -tln | grep -E '10808|10809'

# 通过 SOCKS 访问（浏览器访问正常即可；裸 curl 可能被 Cloudflare 返回 403，不代表代理未通）
curl -x socks5h://127.0.0.1:10808 -sSIL \
  -o /dev/null -w "HTTP %{http_code}\n" https://claude.ai/

# 测试出口 IP（可能因站点策略返回非 200，仅供参考）
curl -x socks5h://127.0.0.1:10808 -sSL https://api4.ipify.org
```

---

## 服务管理

### 出口节点（新加坡）

```bash
systemctl status xray          # 查看状态
journalctl -u xray -f          # 实时日志
systemctl restart xray         # 重启
cat /root/.vpn_exit_config     # 查看连接参数
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
./client/linux_setup.sh status        # 一站式状态查看
./client/linux_setup.sh proxy test    # 常用站点连通性 + 海外/国内基准测速
sudo ./client/linux_setup.sh clean    # 停止并卸载
systemctl status xray-client          # 原生 systemd 命令
journalctl -u xray-client -n 50 --no-pager  # 最近日志
journalctl -u xray-client -f          # 实时日志
systemctl restart xray-client         # 重启
```

配置文件：`/usr/local/etc/xray/client.json`。
终端代理配置文件：`~/.config/vpn/proxy.env`（`linux_setup.sh proxy` 与全局
`setproxy` 命令共享该文件）。
dnf 代理状态文件：`~/.config/vpn/setproxy-dnf-state.json`（仅在 Linux dnf 主机上
由 `setproxy` 管理）。

### 客户端（macOS · 命令行方案）

```bash
./client/macos_setup.sh status              # 一站式状态查看
launchctl list | grep com.vpn.xray-client   # LaunchAgent（PID 为 - 表示未常驻成功）
tail -f /tmp/xray-client.log                # Xray 标准输出 / 错误

# 重启 Xray 客户端
launchctl unload ~/Library/LaunchAgents/com.vpn.xray-client.plist
launchctl load -w ~/Library/LaunchAgents/com.vpn.xray-client.plist

./client/macos_setup.sh clean               # 停止并卸载（含 plist）

# 系统全局代理（networksetup）
./client/macos_setup.sh proxy status
./client/macos_setup.sh proxy off           # 关机或停用 VPN 前建议先关闭系统代理
```

配置文件：`$(brew --prefix)/etc/xray/client.json`（Apple Silicon 常见为 `/opt/homebrew/etc/xray/client.json`）。

### 客户端（macOS · V2RayXS 方案）

通过菜单栏 V2RayXS 图标管理：启用/停用代理、切换节点、PAC / 全局模式切换、查看日志。无需命令行。

---

## 安全说明

- **Reality 协议**：通过 TLS 握手伪装成访问 `www.icloud.com` 的流量，流量特征无法与正常 HTTPS 区分
- **中继节点无感知**：杭州 ECS 仅做 TCP 转发，不解密、不存储任何流量内容
- **建议**：阿里云安全组限制 443 入方向仅允许可信客户端 IP，防止被扫描滥用
- **UUID 和私钥**：请妥善保管出口节点生成的配置，切勿公开

## 常见问题

**Q: 中继节点部署后能否复用现有 nginx SNI 代理（proxy 方案）？**

A: 两者均监听 443 端口，存在冲突。建议：
- 方案一：中继节点使用不同端口（如 `--listen-port=8443`），客户端对应修改 `--relay-port=8443`
- 方案二：中继节点为专用机器，不部署其他服务

**Q: Claude iOS App 能用但 ChatGPT/Gemini App 正常，是什么原因？**

A: 根本原因是 **Cloudflare Bot Challenge**。Claude 的服务器（`claude.ai`、`a-api.anthropic.com`）部署在 Cloudflare 后，Cloudflare 对数据中心 IP（如阿里云 ECS）的出站连接触发 `cf-mitigated: challenge`，返回需要 JS 执行的挑战页面。浏览器能通过（有 JS 引擎），iOS 原生 App 无法通过（URLSession 没有 JS 引擎），所以 App 反复得到 403 并重试。ChatGPT/Gemini 使用自有 CDN 基础设施，不经过 Cloudflare 此机制，不受影响。

解决方案：出口节点安装 Cloudflare WARP，将 Anthropic 域名流量通过 WARP（Cloudflare 自有 IP 出站），Cloudflare 不会 challenge 自家 WARP 的流量。

**Q: 出口节点重新部署会导致 UUID 和密钥变化吗？**

A: 不会。脚本会读取 `/root/.vpn_exit_config` 缓存，复用已有参数。如需重新生成，删除该文件后重新运行。

**Q: macOS 能连上，但 iOS Shadowrocket 连不上？**

A: iOS 无法模拟 Chrome TLS 指纹，必须将 VLESS 链接中的 `fp=chrome` 改为 `fp=ios`。使用 `fp=chrome` 时 Reality 握手会在 iOS 侧失败，表现为超时或连接被重置。重新运行出口节点的 `exit/setup.sh` 会同时输出 macOS 版和 iOS 专用版 VLESS 链接。

**Q: 如何添加更多受代理站点？**

A: 编辑客户端配置（Linux：`/usr/local/etc/xray/client.json`；macOS 命令行方案：`$(brew --prefix)/etc/xray/client.json`），在 `routing.rules` 的 `proxy` 规则中添加域名；Linux 执行 `systemctl restart xray-client`；macOS 执行上文「重启 Xray 客户端」中的 `launchctl unload` / `load`。V2RayXS 用户直接编辑 `client/pac.js` 中的 `domains` 数组即可。

**Q: macOS 上 `curl -x socks5h://127.0.0.1:10808 https://claude.ai/` 返回 403？**

A: 代理链路可能已通（浏览器访问正常即可）；裸 `curl` 易被 Cloudflare 拦截，可用 `./client/macos_setup.sh status` 或 `lsof -iTCP:10808 -sTCP:LISTEN` 确认本地监听。
