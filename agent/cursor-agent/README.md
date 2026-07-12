# Cursor Agent CLI 工具

[Cursor Agent CLI](https://cursor.com/docs/cli/overview) 的安装与权限配置。使用 Cursor 自身账号与模型，不集成 OpenRouter 等第三方渠道。

---

## 目录

| 脚本 | 平台 | 说明 |
|------|------|------|
| `setup.sh` | macOS / Linux | 安装、卸载、同步权限配置 |

---

## 安装与配置

```bash
cd agent/cursor-agent

./setup.sh install   # 安装 Cursor Agent CLI（官方 install 脚本）
./setup.sh sync      # 同步权限策略到 ~/.cursor/cli-config.json
./setup.sh login     # 浏览器登录 Cursor 账号
./setup.sh status    # 查看安装与权限摘要
./setup.sh update    # 更新到最新版
./setup.sh uninstall # 卸载 CLI（保留 ~/.cursor 配置）
```

确保 `~/.local/bin` 在 `PATH` 中（安装脚本默认把 `agent` / `cursor-agent` 链到这里）。

---

## 默认权限

`./setup.sh sync` 会合并以下策略到 `~/.cursor/cli-config.json`：

- `approvalMode = allowlist`：不在 allow 中的工具调用需确认
- `sandbox.mode = disabled`：默认不启用沙箱（接近 Codex 的 `danger-full-access`）
- 常用开发命令、`Read(**)`、`Write(**)` 写入 `allow`，自动通过
- `rm` / `scp` / `sftp` / `rsync` / `curl` / `wget` / `nc` / `ncat` / `socat` **不进 allow**，每次执行前确认
- `deny` 默认为空：敏感命令不永久禁止（与 Codex 的 prompt 策略对齐，不同于 Claude 的硬 deny）
- 合并时保留本机已有 allow/deny 条目，并强制从 allow 中剔除上述敏感 Shell
- 不改动 `model` / `authInfo` / `privacyCache` 等 Cursor 自身托管字段

重启 Cursor Agent CLI 后生效。

---

## 与 Claude / Codex 的差异

| 方面 | Claude Code | Codex CLI | Cursor Agent |
|------|-------------|-----------|--------------|
| 配置文件 | `~/.claude/settings.json` | `~/.codex/config.toml` | `~/.cursor/cli-config.json` |
| 渠道切换 | anthropic / openrouter / proxy | openai / openrouter / proxy | 无（Cursor 账号内置模型） |
| 敏感命令 | `deny` 永久禁止 | `prefix_rule` → prompt | 不进 `allow` → 每次确认 |
| 认证 | API Key / claude login | API Key / codex login | `agent login` |

---

## 通用配置（config/）

| 文件 | 说明 |
|------|------|
| `config/cli-config.json` | 可移植的权限模板（approvalMode / sandbox / permissions） |

---

## 相关链接

- [Cursor CLI 文档](https://cursor.com/docs/cli/overview)
- [Permissions 参考](https://cursor.com/docs/cli/reference/permissions)
- [Configuration 参考](https://cursor.com/docs/cli/reference/configuration)
- 会话结束提示音见 [agent/notify/README.md](../notify/README.md)
