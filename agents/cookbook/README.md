# Agent Cookbook

个人编程习惯与经验的可消费配方集，供 Cursor / Claude 等 Agent 使用。  
不是运行时安装器；安装与渠道配置仍在 `agents/claude`、`agents/codex`、`agents/cursor-agent`。

## 目录约定

```
agents/cookbook/
├── setup.sh           # 同步到本机 Agent 消费路径（支持 --dry-run）
├── skills/            # 按需加载的工作流配方（主内容）
│   └── git/submit/    # 整理 commit → rebase → 开 MR/PR
├── commands/          # 显式触发的短入口（可选）
├── subagents/         # 角色分工定义（可选）
├── rules/             # 常驻规范（可选，宜少）
└── hooks/             # 事件护栏（可选）
```

| 类型 | 用途 |
|------|------|
| `skills/` | 完整流程：何时做、按什么步骤做 |
| `commands/` | `/submit` 这类短入口，细节引用 skill |
| `subagents/` | 固定角色与边界 |
| `rules/` | 几乎总生效的硬约束 |
| `hooks/` | 事件自动化或门禁 |

真实可执行 Git 工具仍在 `tools/git/`（如 `git rb`、`git review`）；本目录只沉淀「如何编排」的经验。

## 同步到本机

```bash
cd agents/cookbook

./setup.sh sync              # 将 skills 链到 ~/.cursor/skills/
./setup.sh sync --dry-run    # 预览
./setup.sh sync --target claude   # 同步到 ~/.claude/skills/
./setup.sh sync --target all      # Cursor + Claude
./setup.sh status
./setup.sh unlink            # 移除本 cookbook 创建的链接
```

默认用符号链接，便于在仓库内改 recipe 后立即生效。勿把 API Key、本机绝对路径或临时配置提交进本目录。

## 现有 skills

| Skill | 触发场景 |
|-------|----------|
| `git-submit` | 整理本地 commit、按 Conventional Commits 提交、rebase 主干并创建 MR/PR |
