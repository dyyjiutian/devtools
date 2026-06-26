# Agent 远程通知

通用的 Mac SSH 远程事件提示音方案。Mac 监听本地端口，远程 Linux 上的 agent hook 通过 SSH 反向隧道回调 Mac，触发共用系统提示音。

当前已接入 Claude Code 的 `SessionEnd` hook，通知 payload 为 `claude:session_end`。listener 会记录来源和事件，后续 Codex 可复用同一端口和同一声音，只需发送 `codex:<event>`。

## 文件

| 脚本 | 平台 | 说明 |
|------|------|------|
| `mac_ssh_notify.sh` | macOS | 管理 listener、LaunchAgent 与远程 Claude hook |
| `agent-listener.sh` | macOS | 监听端口、解析 `source:event`、播放提示音 |

## 快速开始

```bash
cd agent/notify
chmod +x mac_ssh_notify.sh agent-listener.sh

./mac_ssh_notify.sh install
./mac_ssh_notify.sh setup-remote user@your-linux-host
./mac_ssh_notify.sh ssh-hint user@your-linux-host
```

在远程运行 `claude`，会话结束后 Mac 会播放 `/System/Library/Sounds/Funk.aiff`。

## 协议

每条通知是一行文本：

```text
source:event
```

示例：

```text
claude:session_end
codex:session_end
```

没有冒号的旧消息仍可触发声音，来源会记录为 `unknown`。

## 命令

| 命令 | 说明 |
|------|------|
| `./mac_ssh_notify.sh install` | 写入 LaunchAgent 开机自启并启动 listener |
| `./mac_ssh_notify.sh uninstall` | 移除 LaunchAgent 并停止 listener |
| `./mac_ssh_notify.sh start` | 后台启动 listener |
| `./mac_ssh_notify.sh stop` | 停止 listener |
| `./mac_ssh_notify.sh restart` | 重启 listener |
| `./mac_ssh_notify.sh status` | 查看进程、端口、LaunchAgent 状态 |
| `./mac_ssh_notify.sh test [source]` | 向本地 19999 发测试通知 |
| `./mac_ssh_notify.sh play` | 直接播放提示音 |
| `./mac_ssh_notify.sh setup-remote <host>` | SSH 到远程并安装 Claude SessionEnd hook |
| `./mac_ssh_notify.sh ssh-hint [host]` | 打印带 `-R` 的 SSH 命令 |

## 环境变量

**Mac listener / LaunchAgent**

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `AGENT_NOTIFY_PORT` | `19999` | 监听端口 |
| `AGENT_NOTIFY_HOST` | `127.0.0.1` | 绑定地址 |
| `AGENT_NOTIFY_SOUND` | `/System/Library/Sounds/Funk.aiff` | 提示音文件 |
| `AGENT_NOTIFY_PID_FILE` | `/tmp/agent-notify-listener.pid` | PID 文件 |
| `AGENT_NOTIFY_LOG_FILE` | `/tmp/agent-notify-listener.log` | 日志路径 |

**远程 Linux hook**

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `AGENT_NOTIFY_PORT` | `19999` | 通知端口，应对应 SSH `-R` 端口 |
| `AGENT_NOTIFY_HOST` | `127.0.0.1` | 通知地址，经反向隧道时为 localhost |

旧的 `CLAUDE_LISTENER_*` 和 `CLAUDE_MAC_NOTIFY_*` 变量仍作为兼容回退可用。

## SSH 配置

```sshconfig
Host dev-linux
    HostName your-linux-host
    User your-user
    RemoteForward 19999 127.0.0.1:19999
    ServerAliveInterval 60
    ExitOnForwardFailure yes
```

之后直接 `ssh dev-linux` 即可。

