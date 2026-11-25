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

## L3 Compose pair（可选）

用两台特权 systemd 容器验证 **client ↔ exit**（不部署中继、TUN、WARP）。server 固定 ALinux 3，client 为 Ubuntu / ALinux 3 / ALinux 4。成功标准：client SOCKS5 能访问 `https://example.com`。

```bash
bazel test --config=l3 //network/vpn:vpn_pair_linux_ubuntu_e2e_test
bazel test --config=l3 //network/vpn:vpn_pair_linux_alinux3_e2e_test
bazel test --config=l3 //network/vpn:vpn_pair_linux_alinux4_e2e_test
```

需要本机 Docker 与 `docker compose`。容器以 `/sbin/init` 为 PID 1，并加 `privileged` + `cgroup: host`，否则 `systemctl` 会失败。出口安装使用 `--skip-warp`。默认 `bazel test //...` 不会跑这一层。拉 Docker Hub 基础镜像走 IPv4（失败则 DaoCloud mirror）；Compose 网络关闭 IPv6。在 Docker Desktop ARM 上，systemd 255 可能无法拉起 amd64 `xray`，pair client 会回退为直接 `xray run`。

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
- 用量 = 持久化累计（`/var/lib/vpn-exit/traffic.tsv`）+ 当前 Xray 进程内计数；`add`/`remove`/`sync` 重载会保留已用流量
- 月初或手动清零：`sudo ./exit/manage.sh reset-stats all`（同时清空持久化文件并重启 Xray）

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

## 方案 B：Linux（systemd + 终端代理 / TUN）

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

# 可选：在上述任一种安装命令中增加 --tun，自动接管 Linux 宿主机 TCP/UDP
sudo ./client/linux_setup.sh install --tun \
  --vless="vless://<UUID>@198.51.100.10:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.icloud.com&fp=chrome&pbk=<PUBLIC_KEY>&sid=<SHORT_ID>&type=tcp&headerType=none#标签"
```

若同时传入 `--vless` 与 `--uuid` / `--public-key` / `--short-id` 中任意一个，脚本会报错退出。
`--vless` 会自动解析 UUID、中继 `host:port`、`pbk`、`sid`、`sni`、`fp`、`flow`、`spx`；`--relay-ip=` / `--relay-port=` 等其他可选参数仍可与 `--vless` 一起使用（例如中继节点做了端口转发，只需 `--vless="..." --relay-port=8443`）。

脚本会自动：
- 安装 Xray-core（官方脚本失败时回退到 ghfast.top / jsdelivr / mirror.ghproxy.com 镜像）
- 安装 geoip.dat / geosite.dat 路由数据（优先 `cache/binaries/`，缺失时再走 jsdelivr / GitHub）
- 写入 `/usr/local/etc/xray/client.json`
- 暴露 SOCKS5（`127.0.0.1:10808`）和 HTTP（`127.0.0.1:10809`）
- 配置 systemd 服务 `xray-client` 并设为开机自启
- 配置路由：国内直连，claude.ai / anthropic.com 走代理

### Linux TUN 模式（可选）

`--tun` 会在保留 SOCKS5/HTTP 入站的同时创建 `xray0`，并通过
`xray-client-tun-routing.service` 自动管理宿主机策略路由。流量进入 Xray 后仍使用
同一套路由规则：内网和国内域名/IP 直连，境外流量通过 VLESS Reality。
TUN 模式使用 systemd 动态专用用户绕过 Xray 自身流量（包括内部 DNS），同时临时
关闭会影响 `xray0` 回包的反向路径过滤；停止或卸载时会恢复脚本启用前的值。

启用策略路由前，脚本还会安装独立的 nftables 入站连接标记规则；没有 nftables 时
回退到 IPv4/IPv6 iptables。来自物理网卡的入站新连接（包括任意客户端的 SSH 和
ping）会动态标记为 `255`，本机回包按标记优先走主路由，因此不依赖某个固定来源 IP，
更换 SSH 客户端也不会改变行为。若两种防火墙后端都不可用，脚本会拒绝启用 TUN，
不会先添加全局策略路由。阿里云安全组和系统防火墙是否放行 SSH/ICMP 仍需单独配置。

TUN 模式下宿主机应用通常不再需要 `proxy on`、`setproxy on`、`--dnf-proxy` 或
`--docker-daemon`；这些显式代理方式仍然兼容。TUN 不会设置
`GIT_SSH_COMMAND`，Git SSH 会和其他宿主机 TCP 流量一样自动分流。

策略规则只匹配宿主机本地进程，不接管 Docker 容器、虚拟机或路由器转发的流量。
当前固定的 Xray v26.3.27 TUN 支持 TCP/UDP，但不代理 ICMP；主机的 ping 回包会
由上述连接标记规则保持正常路由，因此 ping 可用于检查主机可达性，但不能单独用来
判断 Xray 隧道是否正常，请使用 `linux_setup.sh status` 或 HTTP/SSH 测试。

如果远程 TUN 启用失败或网络中断，请通过 ECS Workbench/串口/云助手执行：

```bash
sudo systemctl disable --now xray-client-tun-routing.service xray-client.service
sudo /usr/local/libexec/xray-client-tun-route down 2>/dev/null || true
```

切回普通 SOCKS5/HTTP 模式时，使用原参数重新安装但不要传 `--tun`；脚本会先撤销
之前管理的 TUN 路由。彻底卸载可执行 `sudo ./client/linux_setup.sh clean`。

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
仓库后依然可用（原理与 `tools/git/bin` 下的 `git rb` 等子命令一致）：

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
systemctl status xray-client-tun-routing  # TUN 策略路由（仅 --tun 模式存在）
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

## Issues

### 2026-11-25 — vpn pair e2e 全 OS 失败：Xray 因缺少 geoip.dat 退出 23

**表象**：`vpn_pair_linux_{ubuntu,alinux3,alinux4}_e2e_test` 在「配置并启动 Xray systemd 服务」失败，日志只有 `Xray 服务启动失败，查看日志: journalctl -u xray -n 50`。镜像已能构建，其它 L3 测试不受影响。

**根因**：`install_xray` 用 `--without-geodata` 离线安装，不把 `geoip.dat` 放到 Xray 资源目录。服务端路由含 `geoip:private`，Xray 26 启动时打开 `/usr/local/bin/geoip.dat` 失败并以状态 23 退出。单元写了 `RestartPreventExitStatus=23`，所以 `systemctl restart` 后服务保持 failed。

**解法**：安装后从 `cache/binaries/geoip.dat` 与 `geosite.dat` 拷到 `/usr/local/share/xray`，再符号链接到 `/usr/local/bin`，并写 `XRAY_LOCATION_ASSET` drop-in。启动失败时把 `journalctl -u xray -n 50` 打到 stderr。容器内复现：`devtools-e2e:ubuntu` 上 `systemctl is-active xray` 由 failed 变为 active。

### 2026-11-24 — vpn pair e2e 全 OS 失败：Xray 在线安装撞 GitHub 403 限流

**表象**：`vpn_pair_linux_{ubuntu,alinux3,alinux4}_e2e_test` 在「安装 Xray-core」步失败，`curl: (22) The requested URL returned error: 403`、`error: Failed to get release list`；多个 PR 并行跑 e2e 时必现。

**根因**：`exit/setup.sh` 从 GitHub 拉官方安装脚本，脚本再调 GitHub release API 取版本列表；runner 共享 IP 的未认证 API 限额（60 次/小时）被并行 CI 任务耗尽，返回 403。

**解法**：`install_xray` 优先用仓库缓存离线安装——`cache/scripts/install-release.sh install --local cache/binaries/Xray-linux-<arch>-*.zip --without-geodata`（按 `uname -m` 选 64/arm64-v8a/arm32-v7a），缓存缺失才回退在线路径。Compose e2e 把仓库挂进容器，全程零 GitHub 请求。契约断言见 `exit/setup_test.sh [8/8]`。

### 2026-11-24 — nvim/vim alinux3 e2e 900s 超时：plus 仓 45MB 元数据拖垮 dnf

**表象**：`nvim_ops_linux_alinux3_e2e_test`、`vim_ops_linux_alinux3_e2e_test` TIMEOUT in 900s；同期 ubuntu/alinux4 通过。vim 日志里运行时 dnf 光 `alinux3-plus` 元数据就 45MB@142kB/s≈5m23s；nvim 还要先自建镜像（构建期 dnf 725s+），900s 预算必超。

**根因**：美国 runner 访问 Aliyun 镜像只有 ~100kB/s；`Dockerfile.e2e.alinux3` 构建后 `dnf clean all` 清掉了元数据缓存，运行时 setup 再装依赖又把 plus（~45MB）等重仓元数据全量重下。

**解法**：① 构建期安装加 `--disablerepo='*plus*' --disablerepo='*epel*'`（所需包都在 os/updates/powertools）；② 构建后用 sed 把 plus/epel 仓 `enabled=0`，运行时同样跳过；③ `clean all` 改 `clean packages`，保留新鲜元数据缓存供同 job 内运行时安装复用。④ 首轮修复后复测仍超时：慢镜像下 108 个包的下载本身就要 30min，首个测试还得承担镜像构建成本——E2E workflow 增加独立预构建步骤（`run_e2e_in_docker.sh --build-only` 依次构建三个镜像），把构建耗时移出 bazel 测试预算，测试直接复用本地镜像/层缓存。契约断言同步更新（`e2e_runner_suite.sh`）。

### 2026-11-23 — 定位真因：dnf-makecache 与 getty 卡住 alinux3 容器启动

**表象**：6 个 compose pair（server 均为 alinux3）全报 `systemd not ready in server (state=starting)`，加到 600s 仍卡死；`systemctl list-jobs` 诊断显示唯一 running job 是 `dnf-makecache.service`。IT 的 alinux3 L2 测试也在构建期 900s 超时。

**根因**：alinux3 的 dnf 默认启用 plus(~44MB)/updates(~41MB) 等重型仓库，从美国 runner 访问 Aliyun 镜像只有 ~50–130 kB/s。① 启动期 `dnf-makecache.service` 联网刷 ~90MB 元数据，把 systemd 卡在 `starting`；② 构建期 `dnf install` 同样先下 ~90MB 元数据（L2 只装 git/tar/gzip 三个基础包也要下全量），慢镜像下超时。本地复现还发现 `serial-getty@getty.service` 等待容器里不存在的 `/dev/getty` 设备，是另一类启动陷阱。

**解法**：① `Dockerfile.e2e.alinux3/alinux4` 用 `ln -sf /dev/null` mask `dnf-makecache.service/.timer`（alinux4 含 dnf5 名）与 `serial-getty@getty.service`/`getty@tty1.service`/`getty.target`——测试容器用 docker exec，不需要这些。本地验证 mask 后 systemd 4s 到 `running`。② `Dockerfile.alinux3`（L2）装 git/tar/gzip 时 `--disablerepo='*plus*'/'*powertools*'/'epel'`，本地构建从 900s+ 降到 ~80s。契约断言同步更新。600s 等待预算保留作为兜底。

### 2026-11-24 — L2 精简仓库误禁 updates 把 git 降级，git 测试 `init -b` 报错

**表象**：`git_linux_alinux3_docker_test` 2.1s 失败，`error: unknown switch 'b'`（`git_suite.sh` 用 `git init -b main`）。

**根因**：上一条精简时把 `updates` 也禁了，git 退回 os 基础仓的 2.27（`init -b` 需 ≥2.28）；新版 git 2.43 在 `updates` 仓。

**解法**：L2 精简保留 `updates`，只禁 `plus/powertools/epel`。本地验证 git 2.43.7、构建 ~82s。

### 2026-11-20 — alinux3 VPN pair 仍等不到 systemd（180s 窗口在高负载下不够）

**表象**：`vpn_pair_linux_alinux3_e2e_test` 报 `systemd not ready in server (state=starting)`，FAILED in ~237s；同 job 的 proxy/alinux4/ubuntu pair 与 nvim/vim 都过。失败后 dump 的 `docker compose logs` 是空的。

**根因**：延续 2026-08-17 的已知问题——alinux3 较老的 systemd 在 `--jobs=2` 并行 docker build/dnf 负载下启动慢，180 次循环（实际 ~237s）窗口仍不够。pair 测试本身是 `size=enormous`（3600s），等待窗口却远小于预算。且 systemd 日志进 journal 不进 console，失败时 dump console 日志拿不到任何诊断。

**解法**：`wait_systemd` 改为基于 `SECONDS` 的 600s 预算（仍远小于 3600s），轮询间隔 2s；失败时改 dump `systemctl list-jobs` / `systemctl --failed`（定位阻塞 unit），console 日志仅作补充。`compose_runner_suite.sh` 同步契约断言。

### 2026-08-17 — Compose E2E 里 exit/setup.sh 因 hostname 退出 127

**表象**：特权 systemd 容器已起来，`pair_server.sh` 在「检测系统环境」以 127 退出。

**根因**：`SERVER_IP=$(curl ... || hostname -I | awk ...)` 在 `set -o pipefail` 下，curl 失败后 `hostname` 不存在会使整段失败。

**解法**：curl / hostname / `ip -4 addr` 分层回退，每步 `|| true`。Compose pair：`bazel test --config=l3 //network/vpn:vpn_pair_linux_alinux3_e2e_test`。

### 2026-08-17 — GitHub E2E 上 alinux4 VPN pair 等不到 systemd

**表象**：`vpn_pair_linux_alinux4_e2e_test` 报 `systemd not ready in server (state=starting)`。同 job 里其它 pair 能过。

**根因**：CI 默认并行跑多个特权 systemd 容器，cgroup 争用时 `systemctl is-system-running` 会长时间停在 `starting`。90s 超时不够。

**解法**：等待加到 180s。Linux E2E 使用 `--jobs=2`（ubuntu-latest 4 vCPU）；`run_compose_e2e.sh` 用 `flock` 串行化特权 systemd compose，避免 cgroup 争用。

### 2026-08-17 — L1 VPN 测试在 macOS 上失败

**表象**：`linux_setup.sh --help` 直接报「仅支持 Linux」；`manage_test` 报 `grep: invalid option -- P`，流量断言错；`linux_setup_test` 在 geo 缓存步骤调用 curl 并报「geoip.dat 下载失败」。

**根因**：Darwin 检查写在 `--help` 解析之前；`get_user_session_traffic` 用了 GNU `grep -P`；`file_size` 只用 GNU `stat -c%s`，在 BSD `stat` 上得到 0，缓存被当成无效。

**解法**：直接执行时 `--help` 可用；`source` 时不做 Darwin 拦截。流量解析改用 `sed`。`file_size` 回退到 `stat -f%z`。

### 2026-08-04 — 国内网络下载 geoip.dat / geosite.dat 超时

**症状**：`linux_setup.sh` / `macos_setup.sh` 安装时从 `cdn.jsdelivr.net` 拉
Loyalsoldier `geoip.dat` / `geosite.dat`，长时间卡在 `curl: (28) Operation timed out`
（例如收到约 3–4MB 后超时）。

**根因**：jsdelivr 在部分国内网络上不稳定，单文件约十几到几十 MB，默认镜像链易失败。

**解法**：将两份数据缓存到 `cache/binaries/{geoip,geosite}.dat`；客户端 `ensure_geo_data`
优先从本地缓存复制，缓存缺失时才回退在线下载。预取：

```bash
bash cache/download.sh linux   # 或 macos / all
```

### 2026-08-04 — 配置校验报 `code not found in geoip.dat: PRIVATE`

**症状**：写入 `client.json` 后 `xray run -test` 失败：
`failed to load GeoIP: private > code not found in geoip.dat: PRIVATE`。

**根因**：jsdelivr 超时可能留下约数 MB 的截断 `geoip.dat`。旧逻辑仅检查
`>= 64KiB`，截断文件会被当成“已就绪”，而 `PRIVATE` 段通常在文件后部，截断后缺失。

**解法**：校验体积（geoip ≥ 8MiB、geosite ≥ 4MiB）并要求 `geoip.dat` 含 `PRIVATE`；
下载改为先写临时文件再 `mv`；校验失败时 `ensure_geo_data <dir> true` 强制刷新。
有仓库缓存时可直接：

```bash
sudo cp cache/binaries/geoip.dat cache/binaries/geosite.dat /usr/local/share/xray/
sudo ./client/linux_setup.sh install --vless='...'
```

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
