# Cursor Agent CLI 工具

[Cursor Agent CLI](https://cursor.com/docs/cli/overview) 的安装、权限配置与推荐 skills / marketplace 同步。使用 Cursor 自身账号与模型，不集成 OpenRouter 等第三方渠道。

---

## 目录

| 脚本 | 平台 | 说明 |
|------|------|------|
| `setup.sh` | macOS / Linux | 安装、卸载、同步权限、安装推荐 skills |

---

## 安装与配置

```bash
cd agents/cursor-agent

./setup.sh install                              # 安装 CLI + 推荐 skills/marketplace + sync
./setup.sh install-plugins                      # 安装全部核心 marketplace + cookbook + 推荐 skills
./setup.sh install-plugins --list               # 打印可安装列表
./setup.sh install-plugins git-submit brainstorming
./setup.sh sync                                 # 同步权限策略到 ~/.cursor/cli-config.json
./setup.sh login                                # 浏览器登录 Cursor 账号
./setup.sh status                               # 查看安装与权限摘要
./setup.sh update                               # 更新到最新版
./setup.sh uninstall                            # 卸载 CLI（保留 ~/.cursor 配置）
```

确保 `~/.local/bin` 在 `PATH` 中（安装脚本默认把 `agent` / `cursor-agent` 链到这里）。

---

## 默认权限

`./setup.sh sync` 会合并以下策略到 `~/.cursor/cli-config.json`：

- `approvalMode = allowlist`；`sandbox.mode = disabled`
- **宽 allow（大部分免审批）**：`Shell(*)`、`Read(**)`、`Write(**)`、`WebFetch(*)`、`Mcp(*)`
- **敏感 deny（永久拒绝）**：`rm` / `scp` / `sftp` / `rsync` / `curl` / `wget` / `nc` / `ncat` / `socat`
- 合并时保留本机已有 allow/deny，并强制敏感项从 allow 剔除、写入 deny
- 不改动 `model` / `authInfo` / `privacyCache` 等 Cursor 自身托管字段

> Cursor CLI 只有 allow/deny，没有 Claude 的 `ask`。此处对敏感命令使用 `deny`（比 Claude ask / Codex prompt 更严）。

重启 Cursor Agent CLI 后生效。

---

## Skills / Marketplace

Cursor Agent CLI 目前仅支持 `plugin marketplace` 管理，没有与 Claude/Codex 对等的 plugin install 子命令。本脚本因此：

1. 预置核心 marketplace（`obra/superpowers`）
2. 调用 `agents/cookbook/setup.sh sync --target cursor` 同步 cookbook skills（如 `git-submit`）
3. 将推荐 skills 从 git 浅克隆缓存并符号链接到 `~/.cursor/skills/<name>`

| 类别 | 短名 | 说明 |
|------|------|------|
| 核心 marketplace | `superpowers` | https://github.com/obra/superpowers |
| 核心 skills | `cookbook` / `git-submit` | 本仓库 cookbook |
| 推荐 skills | `brainstorming` 等 | 来自 superpowers 仓库的常用工作流 skills |

正式的 IDE plugin 安装仍在 Cursor Customize → Plugins 中完成。

---

## 与 Claude / Codex 的差异

| 方面 | Claude Code | Codex CLI | Cursor Agent |
|------|-------------|-----------|--------------|
| 配置文件 | `~/.claude/settings.json` | `~/.codex/config.toml` | `~/.cursor/cli-config.json` |
| 渠道切换 | anthropic / openrouter / proxy | openai / openrouter / proxy | 无（Cursor 账号内置模型） |
| 敏感命令 | `ask` 确认 / 灾难性 `deny` | `prefix_rule` → prompt | `deny` 永久拒绝 |
| 扩展安装 | `claude plugins install` | `codex plugin add` | marketplace + skills 链接 |
| 认证 | API Key / claude login | API Key / codex login | `agent login` |

---

## 通用配置（config/）

| 文件 | 说明 |
|------|------|
| `config/cli-config.json` | 可移植的权限模板（宽 allow + 敏感 deny） |

---

## Issues

### 2026-07-30 — 窄 allowlist 改为宽 allow + 敏感 deny

- **表象**：除列出的几十条开发命令外，其余 Shell/网络/MCP 仍频繁请求审批。
- **根因**：`approvalMode=allowlist` 下仅 allow 内条目自动通过；旧模板用长白名单，覆盖不全。
- **解法**：模板改为 `Shell(*)` / `Read(**)` / `Write(**)` / `WebFetch(*)` / `Mcp(*)`，敏感命令写入 `deny`。运行 `./setup.sh sync` 合并到本机。

---

## 相关链接

- [Cursor CLI 文档](https://cursor.com/docs/cli/overview)
- [Permissions 参考](https://cursor.com/docs/cli/reference/permissions)
- [Configuration 参考](https://cursor.com/docs/cli/reference/configuration)
- [Skills](https://cursor.com/docs/skills)
- 会话结束提示音见 [os/macos/agent-notify/README.md](../../os/macos/agent-notify/README.md)
