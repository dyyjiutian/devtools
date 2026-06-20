# Claude Code 工具

[Claude Code](https://claude.ai/code) 的安装配置，以及 Mac 远程 SSH 使用 Claude 时的会话结束提示音方案。

---

## 目录

| 脚本 | 平台 | 说明 |
|------|------|------|
| `setup.sh` | macOS / Linux | 安装、卸载、配置 Claude Code |
| `mac_ssh_hook.sh` | macOS | 管理 listener 与远程 SessionEnd hook |
| `claude-listener.sh` | macOS | 监听端口并播放提示音（由 hook 脚本启动） |

---

## Claude Code 安装与配置

```bash
cd agent/claude

./setup.sh install           # 安装 Claude Code（npm）+ 自动安装插件
./setup.sh install-plugins   # 仅安装/更新插件
./setup.sh sync              # 将 config/ 中的通用配置合并到本机
./setup.sh uninstall         # 卸载
```

---

## 快速切换渠道

支持三种使用渠道，可随时快速切换：

| 渠道 | 说明 | Base URL |
|------|------|----------|
| `anthropic` | Anthropic 官方 API | `https://api.anthropic.com` |
| `openrouter` | OpenRouter 多模型聚合（Claude / GPT-4o / Gemini / Qwen / GLM 等） | `https://openrouter.ai/api/v1` |
| `proxy` | 自定义代理（LiteLLM / GLM / 百炼 / 国内中转） | 自定义 |

```bash
# 交互式选择渠道
./setup.sh switch

# 直接切换
./setup.sh switch anthropic
./setup.sh switch openrouter
./setup.sh switch proxy

# 切换渠道并指定模型
./setup.sh switch openrouter --model openai/gpt-4o
./setup.sh switch openrouter --model zhipuai/glm-4-plus

# 仅切换模型（保持当前渠道）
./setup.sh model anthropic/claude-opus-4-8

# 查看当前配置
./setup.sh status
```

**API Key 管理**：首次切换某渠道时会提示输入 API Key，可选择保存到 `~/.claude/.profile-keys`（本地文件，chmod 600，不进 git）。之后切换该渠道时自动复用，无需重复输入。

**OpenRouter 常用模型**（`switch openrouter --model <name>`）：

| 模型 | model name |
|------|-----------|
| Claude Sonnet 4.6 | `anthropic/claude-sonnet-4-6` |
| Claude Opus 4.8 | `anthropic/claude-opus-4-8` |
| GPT-4o | `openai/gpt-4o` |
| Gemini 2.5 Pro | `google/gemini-2.5-pro` |
| Qwen Plus | `qwen/qwen-plus` |
| GLM-4 Plus | `zhipuai/glm-4-plus` |
| DeepSeek Chat | `deepseek/deepseek-chat` |

---

## 精细配置（configure）

非交互式设置具体参数：

```bash
./setup.sh configure --api-key "sk-ant-..." --model "claude-sonnet-4-6"
./setup.sh configure --base-url "https://your-proxy.com/v1" --api-key "your-key"
```

配置写入 `~/.claude/settings.json` 的 `env` 对象。

---

## 插件

`install` 和 `install-plugins` 会自动安装以下插件：

| 类别 | 插件 | 说明 |
|------|------|------|
| 核心 | `superpowers` | 工作流技能（brainstorm / debugging / TDD 等） |
| 核心 | `context7` | 实时库文档查询 |
| 核心 | `claude-hud` | 会话状态栏（token / 模型 / 任务） |
| 推荐 | `github` | GitHub PR / Issue / Actions 集成 |
| 推荐 | `code-review` | 代码审查技能 |
| 推荐 | `remember` | 跨会话持久化记忆 |
| 推荐 | `commit-commands` | Git commit 辅助命令 |
| 推荐 | `exa` | AI 增强网络搜索 |

---

## 通用配置（config/）

| 文件 | 说明 |
|------|------|
| `config/settings.json` | 可移植的 Claude 设置模板（不含 macOS 专属的 statusLine / afplay hook） |
| `config/CLAUDE.md` | 全局行为指令（语言规则：仅中文或英文） |
| `config/profiles/anthropic.json` | Anthropic 官方渠道配置 |
| `config/profiles/openrouter.json` | OpenRouter 渠道配置（含常用模型列表） |
| `config/profiles/proxy.json` | 自定义代理渠道配置模板 |

`sync` 命令将 settings.json 和 CLAUDE.md 合并到本机，保留已有的系统专属配置（statusLine、hooks 等）。

---

## Mac SSH 远程会话结束提示音

在 Mac 上 SSH 到远程 Linux 跑 Claude Code 时，会话结束（退出、`/clear` 等）会在 **Mac 本地** 播放 `Funk.aiff` 系统提示音，方便合盖或切窗口时感知任务完成。

### 原理

```
远程 Linux                         Mac
┌─────────────────────┐           ┌──────────────────────────┐
│ claude 会话结束      │           │ claude-listener.sh       │
│ SessionEnd hook     │           │ 监听 127.0.0.1:19999     │
│   nc 127.0.0.1:19999│──SSH -R──▶│   afplay Funk.aiff       │
└─────────────────────┘           └──────────────────────────┘
```

1. Mac 上 `claude-listener.sh` 监听 `127.0.0.1:19999`
2. SSH 时使用 `-R 19999:127.0.0.1:19999` 建立反向隧道
3. 远程 `SessionEnd` hook 向 `127.0.0.1:19999` 发通知
4. 流量经隧道到达 Mac listener，触发 `afplay`

### 前提

- **Mac**：macOS，已安装 `nc`（系统自带）、`afplay`（系统自带）
- **远程**：Linux，已安装 [Claude Code](https://claude.ai/code) 与 `python3`（`setup-remote` 合并配置用）
- SSH 客户端支持反向端口转发（OpenSSH 默认支持）

### 快速开始

**1. Mac 上安装 listener 并配置开机自启**

```bash
cd agent/claude
chmod +x mac_ssh_hook.sh claude-listener.sh

./mac_ssh_hook.sh install
./mac_ssh_hook.sh status    # 确认 19999 端口在监听
```

**2. 在远程 Linux 安装 SessionEnd hook**

```bash
./mac_ssh_hook.sh setup-remote user@your-linux-host
```

会在远程创建：

- `~/.claude/hooks/session-end-notify-mac.sh`
- 向 `~/.claude/settings.json` 注册 `SessionEnd` hook（幂等，不重复添加）

**3. 带反向隧道 SSH 到远程**

```bash
./mac_ssh_hook.sh ssh-hint user@your-linux-host
# 或手动：
ssh -R 19999:127.0.0.1:19999 \
    -o ServerAliveInterval=60 \
    -o ExitOnForwardFailure=yes \
    user@your-linux-host
```

**4. 在远程运行 Claude**

```bash
claude
# 退出会话或 /clear 后，Mac 应播放 Funk.aiff
```

### 命令参考

| 命令 | 说明 |
|------|------|
| `./mac_ssh_hook.sh install` | 写入 LaunchAgent 开机自启并启动 listener |
| `./mac_ssh_hook.sh uninstall` | 移除 LaunchAgent 并停止 listener |
| `./mac_ssh_hook.sh start` | 后台启动 listener（不写入自启） |
| `./mac_ssh_hook.sh stop` | 停止 listener |
| `./mac_ssh_hook.sh restart` | 重启 listener |
| `./mac_ssh_hook.sh status` | 查看进程、端口、LaunchAgent 状态 |
| `./mac_ssh_hook.sh test` | 向本地 19999 发测试通知 |
| `./mac_ssh_hook.sh play` | 直接播放提示音（不经过 listener） |
| `./mac_ssh_hook.sh setup-remote <host>` | SSH 到远程并安装 SessionEnd hook |
| `./mac_ssh_hook.sh ssh-hint [host]` | 打印带 `-R` 的 SSH 命令 |

### 环境变量

**Mac（listener / LaunchAgent）**

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CLAUDE_LISTENER_PORT` | `19999` | 监听端口 |
| `CLAUDE_LISTENER_HOST` | `127.0.0.1` | 绑定地址 |
| `CLAUDE_LISTENER_SOUND` | `/System/Library/Sounds/Funk.aiff` | 提示音文件 |
| `CLAUDE_LISTENER_PID_FILE` | `/tmp/claude-listener.pid` | PID 文件 |
| `CLAUDE_LISTENER_LOG_FILE` | `/tmp/claude-listener.log` | 日志路径 |

自定义提示音示例：

```bash
CLAUDE_LISTENER_SOUND=/System/Library/Sounds/Glass.aiff ./mac_ssh_hook.sh install
```

**远程 Linux（SessionEnd hook）**

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CLAUDE_MAC_NOTIFY_PORT` | `19999` | 通知端口（应对应 SSH `-R` 端口） |
| `CLAUDE_MAC_NOTIFY_HOST` | `127.0.0.1` | 通知地址（经反向隧道时为 localhost） |

### 开机自启

`install` 会创建用户级 LaunchAgent：

```
~/Library/LaunchAgents/com.devtools.claude-listener.plist
```

- `RunAtLoad`：登录后自动启动
- `KeepAlive`：异常退出后自动重启

手动管理：

```bash
launchctl list | grep com.devtools.claude-listener
tail -f /tmp/claude-listener.log
```

### 故障排查

**Mac 没有声音**

1. `./mac_ssh_hook.sh status` — listener 是否在跑、19999 是否监听
2. `./mac_ssh_hook.sh test` — 本地链路是否正常
3. `./mac_ssh_hook.sh play` — 排除 afplay / 音量 / 静音问题
4. 查看日志：`tail -20 /tmp/claude-listener.log`

**远程 Claude 结束但 Mac 无反应**

1. 确认 SSH 命令包含 `-R 19999:127.0.0.1:19999`
2. 在远程测试隧道：`printf 'test\n' | nc -w 2 127.0.0.1 19999`
3. 确认 hook 已注册：`grep -A5 SessionEnd ~/.claude/settings.json`
4. 确认 hook 可执行：`~/.claude/hooks/session-end-notify-mac.sh`

**SSH 反向隧道建立失败**

- 远程 `sshd` 需允许 `AllowTcpForwarding`（默认通常为 `yes`）
- 若 19999 已被占用，可改端口并两端一致：

  ```bash
  CLAUDE_LISTENER_PORT=29999 ./mac_ssh_hook.sh install
  ssh -R 29999:127.0.0.1:29999 user@host
  ```

**`setup-remote` 失败**

- 确保 Mac 能免密或已交互登录：`ssh user@host echo ok`
- 远程需有 `python3`

### 与 ~/.ssh/config 配合

```sshconfig
Host dev-linux
    HostName your-linux-host
    User your-user
    RemoteForward 19999 127.0.0.1:19999
    ServerAliveInterval 60
    ExitOnForwardFailure yes
```

之后直接 `ssh dev-linux` 即可，无需每次手敲 `-R`。

---

## 相关链接

- [Claude Code 文档](https://code.claude.com/docs)
- [Claude Code Hooks 指南](https://code.claude.com/docs/en/hooks-guide)
