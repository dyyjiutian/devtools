# FRP 远程访问（SSH + VNC）

通过 [FRP](https://github.com/fatedier/frp) 内网穿透，在 Linux 服务器上暴露端口，从任意位置 SSH / VNC 登录内网 Mac。

## 架构

```
┌─────────────┐         frp 控制连接          ┌──────────────┐
│  Mac 客户端  │ ────────────────────────────▶ │ Linux 服务端  │
│   (frpc)    │         :7000                 │   (frps)     │
│             │                               │              │
│ SSH  :22    │◀──── 远程端口映射 ────────────▶│ :6000 (SSH)  │
│ VNC  :5900  │◀──── 远程端口映射 ────────────▶│ :6001 (VNC)  │
└─────────────┘                               └──────────────┘
                                                     ▲
                                                     │ 用户连接
                                              ssh -p 6000 user@SERVER_IP
                                              vnc://SERVER_IP:6001
```

- **Linux（当前机器）**：运行 `frps`，持有可被访问的 IP
- **Mac**：运行 `frpc`，将本机 SSH/VNC 注册到 Linux

## 快速开始

### 1. Linux 服务端

```bash
cd network/frp/server
sudo ./setup.sh
```

脚本会：
- 安装 frps v0.69.1
- 生成 token 并写入 `/etc/frp/`
- 配置 systemd 自启动
- 尝试开放防火墙端口（firewalld / ufw）
- 输出 Mac 客户端所需的连接参数

查看状态：

```bash
sudo ./setup.sh --status
```

### 2. macOS 客户端

先在 Mac 上开启共享服务：
- **系统设置 > 通用 > 共享 > 远程登录**（SSH）
- **系统设置 > 通用 > 共享 > 屏幕共享**（VNC）

然后运行：

```bash
cd network/frp/client
./setup.sh \
  --server-ip=<Linux_IP> \
  --token=<从服务端获取的token> \
  --client-name=$(hostname -s) \
  --ssh-remote-port=6000 \
  --vnc-remote-port=6001
```

### 3. 连接 Mac

```bash
# SSH
ssh -p 6000 <mac_username>@<Linux_IP>

# VNC（macOS 自带屏幕共享客户端）
open vnc://<Linux_IP>:6001
```

## 多台 Mac

每台 Mac 使用不同的远程端口，并在服务端允许的范围内（默认 6000-6100）：

| Mac       | SSH 远程端口 | VNC 远程端口 |
|-----------|-------------|-------------|
| macbook-a | 6000        | 6001        |
| macbook-b | 6002        | 6003        |
| imac      | 6004        | 6005        |

## 常用命令

```bash
# 服务端
sudo systemctl status frps
sudo journalctl -u frps -f
sudo ./server/setup.sh --clean

# 客户端
./client/setup.sh --status
tail -f ~/.config/frp/frpc.log
./client/setup.sh --clean
```

## 端口说明

| 端口 | 用途 |
|------|------|
| 7000 | frps 控制端口（Mac frpc 连接） |
| 7500 | frps 管理面板（仅本机，需 SSH 隧道） |
| 6000+ | SSH/VNC 映射端口（按 Mac 分配） |

## 云服务器注意

若 Linux 在阿里云/腾讯云等，除脚本自动配置的 firewalld/ufw 外，还需在**云安全组**放行：
- `7000/tcp`（frps 控制）
- `6000-6100/tcp`（SSH/VNC 映射）

## 故障排查

| 现象 | 可能原因 | 处理 |
|------|---------|------|
| frpc 连不上 | 7000 端口未放行 | 检查云安全组 + 防火墙 |
| SSH 连接被拒 | Mac 未开远程登录 | 系统设置开启「远程登录」 |
| VNC 黑屏/连不上 | 未开屏幕共享 | 系统设置开启「屏幕共享」 |
| token 错误 | 两端 token 不一致 | `sudo server/setup.sh --status` 核对 |
| 端口冲突 | 多台 Mac 用了相同远程端口 | 为每台 Mac 分配不同端口 |

## 文件位置

**Linux 服务端：**
- 二进制：`/usr/local/frp/frps`
- 配置：`/etc/frp/frps.toml`
- Token：`/etc/frp/.token`

**macOS 客户端：**
- 二进制：`~/.local/frp/frpc`
- 配置：`~/.config/frp/frpc.toml`
- 日志：`~/.config/frp/frpc.log`
- 自启动：`~/Library/LaunchAgents/com.frp.client.plist`
