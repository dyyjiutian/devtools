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

./setup.sh install                      # 安装 Claude Code（npm）+ 自动安装推荐插件
./setup.sh install-plugins              # 安装全部核心 + 推荐插件
./setup.sh install-plugins --list       # 打印可安装列表
./setup.sh install-plugins superpowers  # 只安装指定插件（短名或 name@marketplace）
./setup.sh sync                         # 将 config/ 中的通用配置合并到本机
./setup.sh uninstall                    # 卸载
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

`install` 与无参 `install-plugins` 会安装以下插件；`install-plugins <name>` 可只装一项（短名如 `superpowers`，或完整 `superpowers@claude-plugins-official`）。

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
`permissions.defaultMode` 是托管字段：`sync` 一律取模板值（当前为 `bypassPermissions`），
本机若为其他模式（如 `auto`/`default`）会被对齐——这台机器上不再弹权限确认。

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

## Issues / FAQ

### 2026-07-30 — `rm -rf /tmp/...` 确认后仍被 deny

表象：用户同意删除 `/tmp` 下临时目录后，Claude 仍报 Permission denied。根因是 deny 中的 `Bash(rm -rf /*)`（及 `-fr` / `/bin/rm` / `sudo` 变体）把 `*` 通配成任意根下路径，连 `/tmp/...` 一并永久拒绝（deny 优先于 ask）。解法：模板去掉这些过宽规则，仅保留精确的 `rm -rf /`、`~`、`$HOME` 等；`sync` 会从本机 deny 列表剔除旧规则。普通 `rm -rf`（含 `/tmp`）继续走 ask。修复后执行 `./setup.sh sync`。

### 2026-07-30 — 长插件列表下可能重复安装

表象：已安装全部插件后再次运行 `./setup.sh install-plugins`，偶尔仍会重复安装部分插件。根因是脚本在 `set -o pipefail` 下通过 `claude plugins list | grep -q` 判断插件是否存在；列表较长时 `grep -q` 提前退出，可能使前序命令收到 SIGPIPE，整个 pipeline 被误判为未匹配。现在会先完整读取插件列表再检查，并由长列表幂等回归测试覆盖。

### 2026-08-23 — `claude update` 卡住 / `install_failed`

表象：`claude update` 长时间无进展，`~/.local/share/claude/versions/` 出现 0 字节的新版本文件，`~/.claude/.last-update-result.json` 记录 `"status":"install_failed"`。根因是原生安装的更新需从 `downloads.claude.ai` 下载约 325MB 二进制（版本 feed `https://downloads.claude.ai/claude-code-releases/latest` → manifest `…/<ver>/manifest.json` → 二进制 `…/<ver>/darwin-arm64/claude`）；本机直连该域名被墙，而经代理的 HTTP/2 长连接会降速（实测下载 32MB：HTTP/1.1 ≈ 3.9MB/s 稳定 vs HTTP/2 ≈ 1.2MB/s），下载停在 0 字节后判定失败。解法：手动升级，用 `curl --http1.1` 下载二进制并 sha256 校验（对照 manifest 的 `checksum`），`cp` 到 `~/.local/share/claude/versions/<ver>` 并 `chmod +x`，再 `ln -sfn` 更新 `~/.local/bin/claude`。claude/codex 均无配置项可强制 HTTP/1.1 或 HTTP/2；claude 下载器尊重 `HTTPS_PROXY`/`HTTP_PROXY`（含 `CLAUDE_CODE_HTTPS_PROXY`），可借此让原生 update 走快代理。

### 2026-11-16 — npm install 报 ENOTEMPTY（回收目录残留）

表象：`./setup.sh install`（npm 安装路径）报 `ENOTEMPTY: directory not empty, rename '…/@anthropic-ai/claude-code' -> '…/@anthropic-ai/.claude-code-XXXX'`。根因：npm 升级时把旧包目录 rename 成按路径**确定性生成**的隐藏回收目录 `.<pkg>-<hash>`；上次安装中断留下同名回收目录后，再次 install 的 rename 目标是非空目录，直接 ENOTEMPTY（与 codex 模块同日记录的问题同源）。解法：`install` 现在会在 `npm install -g` 前自动清理 npm 全局 lib/bin 下的 `.claude-code-*` 回收残留（`_npm_clean_retired`）。手工修复：`rm -rf "$(npm root -g)/@anthropic-ai/.claude-code-"* "$(npm prefix -g)/bin/.claude-code-"*` 后重装。

---

## 相关链接

- [Claude Code 文档](https://code.claude.com/docs)
- [Claude Code Hooks 指南](https://code.claude.com/docs/en/hooks-guide)
