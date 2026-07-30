# Agent Cookbook

个人编程习惯与经验的可消费配方集，供 Cursor / Claude / Codex 等 Agent 使用。
不是运行时安装器；安装与渠道配置仍在 `agents/claude`、`agents/codex`、`agents/cursor-agent`。

## 目录约定

```
agents/cookbook/
├── setup.sh           # 同步到本机 Agent 消费路径（支持 --dry-run）
├── skills/            # 按需加载的工作流配方（主内容）
│   ├── git/submit/    # 整理 commit → rebase → 开 MR/PR
│   └── dev/           # 轻量开发闭环（替代默认 Superpowers 总入口）
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

## 同步到本机（多 Agent CLI）

`setup.sh sync` 把 cookbook 里的 skills（及 Cursor rules）链到各 Agent 的本机消费目录。默认符号链接，便于在仓库内改 recipe 后立即生效。

| `--target` | skills 目标 | rules |
|------------|-------------|-------|
| `cursor`（默认） | `~/.cursor/skills/` | `~/.cursor/rules/` |
| `claude` | `~/.claude/skills/` | 跳过 |
| `codex` | `~/.agents/skills/` | 跳过 |
| `all` | 上述三端 | 仅 Cursor |

> Codex 官方推荐用户级路径为 `~/.agents/skills/`。若仍使用旧路径，可覆盖：
> `CODEX_SKILLS_DIR="$HOME/.codex/skills" ./setup.sh sync --target codex`

### 一次安装到多个 Agent

```bash
cd agents/cookbook

./setup.sh sync --target all           # Cursor + Claude + Codex
./setup.sh sync --target all --dry-run # 预览三端路径，不改动文件
./setup.sh status                      # 查看各端链接状态
```

### 只安装到某一个 Agent

```bash
./setup.sh sync                        # 仅 Cursor（skills + rules）
./setup.sh sync --target claude        # 仅 Claude skills
./setup.sh sync --target codex         # 仅 Codex skills
```

### 常用维护

```bash
./setup.sh unlink --target all         # 移除本 cookbook 创建的三端链接
./setup.sh sync --copy --target all    # 复制而非符号链接（适合只读部署）
```

勿把 API Key、本机绝对路径或临时配置提交进本目录。

## 现有 skills

| Skill | 触发场景 |
|-------|----------|
| `git-submit` | 整理本地 commit、按 Conventional Commits 提交、rebase 主干并创建 MR/PR |
| `dev-loop` | 开发任务默认总入口：自动选完整/简单模式并编排子 skill |
| `dev-ask` | 澄清意图、需求与验证策略（简单/完整模式都要做） |
| `dev-design` | 完整模式：写中等短 design（含可执行的测试要点）到 `docs/superpowers/specs/` |
| `dev-workspace` | execute 前隔离：full 用 `.worktrees/`；simple 在主干建临时分支；rebase + 漂移检查 |
| `dev-execute` | 按已确认意图/design 实现；每次改文件前 Preflight 检测未知脏改动 |
| `dev-simply` | 完整模式、execute 之后：按 Clean Architecture 精简过度设计 |
| `dev-verify` | 验证门禁：行为/逻辑走 TDD；配置/文档/幂等脚本走实现后验证 |
| `dev-submit` | verify 通过后可选收尾：询问是否提交；确认 local/remote 后委托 `git-submit` |

### Dev Loop 模式

- **完整：** ask → design → workspace → execute → simply → verify → submit
- **简单：** ask → workspace → execute → verify → submit（无长 design、无 simply）
- **隔离：** 默认不在主干实现；full 建 `.worktrees/<topic>`（当前窗口 + 绝对路径）；新建隔离后 rebase，结构漂移大则退回 ask
- **提交：** 默认先问再提交（本轮已授权「做完自己提交」可跳过是否提交）；先确认仅本地 commit 或 rebase + 开 PR/MR
- **覆盖口令：** `用完整流程` / `用简单流程` / `跳过 simply` / `跳过 worktree` / `就在当前分支做` / `用官方 superpowers`

设计见 `docs/superpowers/specs/2026-07-30-dev-pipeline-design.md`（文档文件名历史保留；内容已对齐 `dev-loop`）。

## Rules

| Rule | 作用 |
|------|------|
| `prefer-dev-loop.mdc` | `alwaysApply`：开发任务优先 `dev-loop`，不默认走官方 Superpowers 总入口 |

`./setup.sh sync`（`--target cursor` 或 `all`）会把 `rules/*.mdc` 链到 `~/.cursor/rules/`。Claude / Codex 不消费 Cursor `.mdc` rules。

## 校验

```bash
bash agents/cookbook/tests/skills_structure_test.sh
bash agents/cookbook/tests/setup_sync_test.sh
bash -n agents/cookbook/setup.sh
```
