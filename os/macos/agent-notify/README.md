# Agent 事件提示音

统一管理 Claude Code / Codex CLI / Cursor Agent CLI 的「一轮结束 / 会话结束」提示。Mac 上常驻一个 listener 监听本地端口，收到通知后**播放统一提示音**，并用 **macOS 系统通知横幅**区分来源（Claude Code / Codex / Cursor Agent）。

支持两种来源：

- **本机**：本机的 Claude / Codex / Cursor hook 直接把消息发到 `127.0.0.1:19999`
- **远端 Linux**：远端的 hook 经 SSH 反向隧道（`-R`）把消息回传到 Mac

## 文件

| 脚本 | 平台 | 说明 |
|------|------|------|
| `agent-hooks-setup.sh` | macOS | 管理 listener、LaunchAgent，以及本机/远端的 Claude / Codex / Cursor hook |
| `agent-listener.sh` | macOS | python3 socket server：解析通知、播放提示音、弹系统通知 |

> listener 与 hook 均依赖 `python3`（macOS 自带）。通知通过带 2 秒超时的
> Python socket 发送，不依赖不同平台上行为不一致的 `nc`。

安装后 `agent-listener.sh` 会被复制到与代码库解耦的稳定位置 `~/.cliagent-hook/agent-listener.sh`，即使代码库被移动/删除，开机自启仍可用。本机与远端安装的 hook 脚本也统一放在各自 `~/.cliagent-hook/hooks/` 下。

## 快速开始

```bash
cd os/macos/agent-notify
chmod +x agent-hooks-setup.sh agent-listener.sh
```

**本机场景（本机跑 claude / codex）**

```bash
./agent-hooks-setup.sh install        # 装 LaunchAgent 并启动 listener
./agent-hooks-setup.sh hook add all   # 给本机 Claude + Codex 装 hook
```

**远端 Linux 场景（SSH 到远端跑 claude / codex）**

```bash
./agent-hooks-setup.sh install
./agent-hooks-setup.sh hook add all user@your-linux
ssh -R 19999:127.0.0.1:19999 -o ExitOnForwardFailure=yes user@your-linux
```

之后正常使用 `claude` / `codex`，一轮结束时 Mac 会播放提示音并弹出对应标题的通知横幅。

## 命令

| 命令 | 说明 |
|------|------|
| `./agent-hooks-setup.sh install` | 仅在本机安装 LaunchAgent 开机自启并启动 listener |
| `./agent-hooks-setup.sh uninstall` | 移除 LaunchAgent 并停止 listener |
| `./agent-hooks-setup.sh test [claude\|codex\|src]` | 发送一条测试通知（默认 `source=manual`） |
| `./agent-hooks-setup.sh hook add <claude\|codex\|cursor\|all> [target]` | 安装 agent 通知 hook |
| `./agent-hooks-setup.sh hook remove <claude\|codex\|cursor\|all> [target]` | 移除 agent 通知 hook |
| `./agent-hooks-setup.sh hook list [target]` | 查看 hook 安装情况 |
| `./agent-hooks-setup.sh help` | 显示帮助（含 SSH 反向隧道示例） |

`target` 省略或写 `local` / `127.0.0.1` 表示本机；写 `user@host` 表示远端（经 SSH 安装）。

## hook 接入方式

- **Claude**：在目标 `~/.claude/settings.json` 的 `hooks.Stop`（一轮结束）与 `hooks.Notification`（需要输入）各挂一条命令 hook，并设置 10 秒框架级超时。合并写入、幂等，保留其他已有 hook。
- **Cursor**：在目标 `~/.cursor/hooks.json` 的 `stop` 事件挂一条命令 hook（应用名显示为 `Cursor Agent`）。合并写入、幂等。
- **Codex**：在目标 `~/.codex/config.toml` 用托管块维护 `notify`，触发时发送 `codex:<type>`（如 `codex:agent_turn_complete`）。

  ```toml
  # >>> cliagent-hook BEGIN <<<
  notify = ["/Users/you/.cliagent-hook/hooks/cliagent-hook-codex.sh"]
  # >>> cliagent-hook END <<<
  ```

  为避免 TOML 重复键，`add` 时会移除托管块外已有的顶层 `notify`，其余配置保留。

> 远端安装依赖远端具备 `python3`（缺失则 hook 静默跳过）。

## 协议

每条通知是一行 JSON（参考 cmux 的 title/subtitle/body 结构）：

```json
{"source":"codex","event":"agent_turn_complete","origin":"devbox","cwd":"/home/u/api","message":"「重命名 foo」会话已完成"}
```

| 字段 | 说明 |
|------|------|
| `source` | `claude` / `codex` / `cursor` |
| `event` | `stop` / `notification`（Claude）、`agent_turn_complete`（Codex）、`stop`（Cursor） |
| `origin` | 发送方主机名，用于区分本地/远端 |
| `cwd` | 工作目录（绝对路径），listener 取 basename 作项目名 |
| `message` | 会话标题/状态（由 hook 决定）；为空时 subtitle 仅显示项目名 |

listener 映射为系统通知（三行：title / subtitle / body）：

- **title**（第1行）= 应用名：`Codex` / `Claude Code` / `Cursor Agent`
- **subtitle**（第2行）= `项目名 · 会话标题`（项目名 = `basename(cwd)`；会话标题 = `message`）。两者都空时回退 `Session Completed`
- **body**（第3行）= `Local · <本机名>` 或 `Remote · <主机名>`

其他说明：

- **项目名**由 listener 统一从 `cwd` 取 basename（本地/远端通用，纯字符串处理，无需访问远端文件系统）。
- **会话标题**在 hook 里生成：Claude `stop` → transcript 首条用户消息，`notification` → Claude 的提示或 `Input Needed`；Codex 取 `input-messages`（其次 `last-assistant-message`）；Cursor `stop` → 用 `conversation_id` 读 `~/.cursor/chats/*/<id>/meta.json` 的 `title`（未文档化，尽力而为，取不到则留空）。标题为空时 subtitle 仅显示项目名。
- `origin` 等于 Mac 本机主机名 → `Local · <本机名>`，否则 `Remote · <主机名>`。
- hook 依赖目标机的 `python3`（缺失则静默跳过，不影响 agent 运行）。发送端连接、
  写入与关闭均有 2 秒超时；listener 收到首行后立即关闭连接，不等待发送端继续读取。

## 提示音与通知

- **声音**：所有来源共用同一个 `CLIAGENT_HOOK_SOUND`（默认 `Funk.aiff`）。
- **区分**：横幅 title 区分应用（`Claude Code` / `Codex` / `Cursor Agent`），subtitle 显示 `项目名 · 会话标题`，body 显示 `Local/Remote · 主机名`。
- 通知横幅使用 `osascript` 弹出，**首次可能需要在「系统设置 → 通知」中允许**其显示，否则只有声音、没有横幅。

## 环境变量

**Mac listener / LaunchAgent**

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CLIAGENT_HOOK_PORT` | `19999` | 监听端口 |
| `CLIAGENT_HOOK_HOST` | `127.0.0.1` | 绑定地址 |
| `CLIAGENT_HOOK_SOUND` | `/System/Library/Sounds/Funk.aiff` | 提示音文件 |
| `CLIAGENT_HOOK_HOME` | `~/.cliagent-hook` | listener 副本与 hook 脚本安装目录 |
| `CLIAGENT_HOOK_PID_FILE` | `/tmp/cliagent-hook-listener.pid` | PID 文件 |
| `CLIAGENT_HOOK_LOG_FILE` | `/tmp/cliagent-hook-listener.log` | 日志路径 |

**hook（本机 / 远端）**

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CLIAGENT_HOOK_PORT` | `19999` | 通知端口，远端应对应 SSH `-R` 端口 |
| `CLIAGENT_HOOK_HOST` | `127.0.0.1` | 通知地址，经反向隧道时为 localhost |

## SSH 配置（远端场景）

远端通知必须带反向隧道，否则无法回传 Mac。执行 `hook add <agent> user@host` 时，
若 `~/.ssh/config` 已存在该 host 的 `Host` 条目，会自动为其补上 `RemoteForward`（幂等、
会先备份为 `config.bak.<时间>`）；若无该条目则不改动，仅提示可手动添加：

```sshconfig
Host dev-linux
    HostName your-linux-host
    User your-user
    RemoteForward 19999 127.0.0.1:19999
    ServerAliveInterval 60
    ExitOnForwardFailure yes
```

之后直接 `ssh dev-linux` 即可。

## Issues / FAQ

### 2026-07-28 — 远端 Linux 的 Agent hook 可能卡住 60 秒

**表象**：Mac listener 正常监听时，从 Mac SSH 到 Linux 运行 Claude Code，`Stop`
hook 可能一直阻塞到 Claude 的 60 秒默认超时；Codex 和 Cursor 的同类 hook 也有
相同风险。

**根因**：旧 hook 使用 `nc -w 2`。不同 `nc` 实现对 `-w` 的定义不一致；Nmap
Ncat 的该选项不限制发送完成后的读取阶段，而旧 listener 又等待客户端 EOF，双方会
互相等待。

**解法**：发送端统一改为 Python socket，在 2 秒超时内发送单行 JSON、关闭写端并
退出；listener 读到首行换行符后立即关闭连接。Claude 的 `Stop` 与 `Notification`
hook 另设 10 秒框架级超时。重新运行以下命令即可幂等升级三类 hook：

```bash
cd os/macos/agent-notify
./agent-hooks-setup.sh hook add all user@your-linux
```
