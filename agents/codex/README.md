# Codex CLI 工具

[OpenAI Codex CLI](https://developers.openai.com/codex) 的安装配置，以及与 `agents/claude` 对齐的多渠道快速切换方案。

---

## 目录

| 脚本 | 平台 | 说明 |
|------|------|------|
| `setup.sh` | macOS / Linux | 安装、卸载、配置 Codex CLI |

---

## Codex CLI 安装与配置

```bash
cd agents/codex

./setup.sh install     # 安装 Codex CLI（npm install -g @openai/codex）
./setup.sh sync        # 同步 config.toml、敏感命令规则和 AGENTS.md
./setup.sh uninstall   # 卸载
./setup.sh login       # 使用 codex login 登录（ChatGPT 订阅 / API Key）
```

> Homebrew 用户也可用 `brew install --cask codex`。

## 默认权限

`./setup.sh sync` 会同步以下权限策略：

- 普通命令、文件写入和网络访问默认允许，不再逐项维护命令白名单。
- `rm`、`scp`、`sftp`、`rsync`、`curl`、`wget`、`nc`、`ncat`、`socat` 每次执行前请求确认。
- `git push`、`npm` 等正常开发和发布操作保持默认允许。
- 同步会保留现有模型、渠道、插件、MCP 和用户自定义规则；仅替换带 `devtools codex permissions` 标记的规则块。

Codex 的原生规则按命令前缀匹配，因此 `curl` 下载和本地 `rsync` 也会触发确认。这是为了避免上传参数顺序变化导致漏检。

---

## 快速切换渠道

支持三种渠道，可随时快速切换：

| 渠道 | 说明 | Base URL |
|------|------|----------|
| `openai` | OpenAI 官方（ChatGPT 登录或 `OPENAI_API_KEY`） | `https://api.openai.com/v1` |
| `openrouter` | OpenRouter 多模型聚合（GPT / Claude / Gemini / Qwen / GLM 等） | `https://openrouter.ai/api/v1` |
| `proxy` | 自定义代理（LiteLLM / 百炼 / 国内中转，OpenAI 兼容端点） | 自定义 |

```bash
# 交互式选择渠道
./setup.sh switch

# 直接切换
./setup.sh switch openai
./setup.sh switch openrouter
./setup.sh switch proxy

# 切换渠道并指定模型
./setup.sh switch openrouter --model openai/gpt-4o

# 仅切换模型（保持当前渠道）
./setup.sh model gpt-5-codex

# 查看当前配置
./setup.sh status
```

**API Key 管理**：首次切换某渠道时会提示输入 API Key，保存到 `~/.codex/.profile-keys`（本地文件，chmod 600，不进 git）。之后切换该渠道时自动复用，无需重复输入。

**Key 如何生效**：Codex 通过 `config.toml` 中每个自定义渠道的 `env_key` 从环境变量读取 Key。脚本会把已保存的 Key 写入 `~/.codex/env.sh`（导出对应环境变量），并可选地在 `~/.zshrc` / `~/.bashrc` 中加入一行自动 `source`，使新终端自动加载。当前终端可手动执行 `source ~/.codex/env.sh` 立即生效。

**OpenRouter 常用模型**（`switch openrouter --model <name>`）：

| 模型 | model name |
|------|-----------|
| GPT-4o | `openai/gpt-4o` |
| GPT-5 | `openai/gpt-5` |
| Claude Sonnet 4.6 | `anthropic/claude-sonnet-4-6` |
| Gemini 2.5 Pro | `google/gemini-2.5-pro` |
| Qwen Plus | `qwen/qwen-plus` |
| GLM-4 Plus | `zhipuai/glm-4-plus` |
| DeepSeek Chat | `deepseek/deepseek-chat` |

---

## 精细配置（configure）

非交互式设置具体参数：

```bash
./setup.sh configure --provider openrouter --api-key "sk-or-v1-..." --model "openai/gpt-4o"
./setup.sh configure --provider proxy --base-url "https://your-proxy.com/v1" --api-key "your-key"
./setup.sh configure --reasoning high      # 仅调整当前渠道的 reasoning effort
```

reasoning effort 可选：`minimal` / `low` / `medium` / `high` / `xhigh`。

---

## 与 Claude 版的差异

| 方面 | Claude Code | Codex CLI |
|------|-------------|-----------|
| 配置文件 | `~/.claude/settings.json`（JSON） | `~/.codex/config.toml`（TOML） |
| 写入方式 | 合并 `env` 字段 | 在标记之间维护「托管块」，标记外的手动配置保留 |
| API Key | 直接写入 `settings.json` 的 `env` | 通过 `env_key` 引用环境变量（`~/.codex/env.sh`） |
| 扩展能力 | 插件（plugins） | MCP 服务器（`[mcp_servers.*]`） |
| 全局指令 | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` |

---

## 通用配置（config/）

| 文件 | 说明 |
|------|------|
| `config/config.toml` | 可移植的 config.toml 参考模板（含托管块 / 自定义渠道 / MCP 示例） |
| `config/AGENTS.md` | 全局行为指令（语言规则：仅中文或英文） |
| `config/profiles/openai.json` | OpenAI 官方渠道配置 |
| `config/profiles/openrouter.json` | OpenRouter 渠道配置（含常用模型列表） |
| `config/profiles/proxy.json` | 自定义代理渠道配置模板 |

`sync` 命令首次会初始化 `config.toml` 托管块（默认 openai）并写入 `AGENTS.md` 语言规则；`switch` / `model` / `configure` 会重新生成托管块，标记之外的手动配置始终保留。

---

## Mac SSH 远程会话结束提示音

远程通知能力在通用目录 `os/macos/agent-notify/`，供 Claude、Codex 等共享同一个 Mac listener 和提示音。

```bash
cd os/macos/agent-notify
./agent-hooks-setup.sh install
./agent-hooks-setup.sh hook add codex user@your-linux-host
```

详见 [os/macos/agent-notify/README.md](../../os/macos/agent-notify/README.md)。

---

## 相关链接

- [Codex CLI 文档](https://developers.openai.com/codex)
- [config.toml 配置参考](https://developers.openai.com/codex/config-reference)
- [openai/codex 仓库](https://github.com/openai/codex)
