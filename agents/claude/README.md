# Claude Code 工具

[Claude Code](https://claude.ai/code) 的安装配置，以及 Mac 远程 SSH 使用 Claude 时的会话结束提示音方案。

---

## 目录

| 脚本 | 平台 | 说明 |
|------|------|------|
| `setup.sh` | macOS / Linux | 安装、卸载、配置 Claude Code |

---

## Claude Code 安装与配置

```bash
cd agents/claude

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

远程通知能力已抽到通用目录 `os/macos/agent-notify/`，用于 Claude、Codex 等 agent 共享同一个 Mac listener 和提示音。Claude Code 当前通过 `SessionEnd` hook 发送 `claude:session_end`。

```bash
cd os/macos/agent-notify
./agent-hooks-setup.sh install
./agent-hooks-setup.sh hook add all user@your-linux-host
```

详见 [os/macos/agent-notify/README.md](../../os/macos/agent-notify/README.md)。

---

## 相关链接

- [Claude Code 文档](https://code.claude.com/docs)
- [Claude Code Hooks 指南](https://code.claude.com/docs/en/hooks-guide)
