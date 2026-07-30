# Agent Cookbook

个人编程习惯与经验的可消费配方集，供 Cursor / Claude 等 Agent 使用。  
不是运行时安装器；安装与渠道配置仍在 `agents/claude`、`agents/codex`、`agents/cursor-agent`。

## 目录约定

```
agents/cookbook/
├── setup.sh           # 同步到本机 Agent 消费路径（支持 --dry-run）
├── skills/            # 按需加载的工作流配方（主内容）
│   ├── git/submit/    # 整理 commit → rebase → 开 MR/PR
│   └── dev/           # 轻量开发流水线（替代默认 Superpowers 总入口）
├── commands/          # 显式触发的短入口（可选）
├── subagents/         # 角色分工定义（可选）
├── rules/             # 常驻规范（可选，宜少）
├── tests/             # cookbook 结构校验
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

./setup.sh sync              # skills → ~/.cursor/skills/；rules → ~/.cursor/rules/
./setup.sh sync --dry-run    # 预览
./setup.sh sync --target claude   # 仅 skills → ~/.claude/skills/（跳过 Cursor rules）
./setup.sh sync --target all      # Cursor skills+rules + Claude skills
./setup.sh status
./setup.sh unlink            # 移除本 cookbook 创建的链接
```

默认用符号链接，便于在仓库内改 recipe 后立即生效。勿把 API Key、本机绝对路径或临时配置提交进本目录。

## 现有 skills

| Skill | 触发场景 |
|-------|----------|
| `git-submit` | 整理本地 commit、按 Conventional Commits 提交、rebase 主干并创建 MR/PR |
| `dev-pipeline` | 开发任务默认总入口：自动选完整/简单模式并编排子 skill |
| `dev-brainstorm` | 澄清意图与需求（简单/完整模式都要做） |
| `dev-spec` | 完整模式：写中等短 spec 到 `docs/superpowers/specs/` |
| `dev-exec` | 按已确认意图/spec 实现 |
| `dev-simply` | 完整模式、exec 之后：按 Clean Architecture 精简过度设计 |
| `dev-test` | 测试门禁：行为/逻辑走 TDD；配置/文档/幂等脚本走实现后验证 |

### Dev Pipeline 模式

- **完整：** brainstorm → spec → exec → simply → test  
- **简单：** brainstorm → exec → test（无长 spec、无 simply）  
- 覆盖口令：`用完整流程` / `用简单流程` / `跳过 simply` / `用官方 superpowers`

设计见 `docs/superpowers/specs/2026-07-30-dev-pipeline-design.md`。

## Rules

| Rule | 作用 |
|------|------|
| `prefer-dev-pipeline.mdc` | `alwaysApply`：开发任务优先 `dev-pipeline`，不默认走官方 Superpowers 总入口 |

`./setup.sh sync`（`--target cursor` 或 `all`）会把 `rules/*.mdc` 链到 `~/.cursor/rules/`。

## 校验

```bash
bash agents/cookbook/tests/skills_structure_test.sh
bash -n agents/cookbook/setup.sh
```
