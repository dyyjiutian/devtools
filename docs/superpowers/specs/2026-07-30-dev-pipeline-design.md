# 定制 Dev Pipeline（轻量 Superpowers）设计

## 目标

用 cookbook 中的薄路由工作流，替代官方 Superpowers 作为**默认开发总入口**，在保留 brainstorm / spec / exec / TDD 纪律的同时降低流程开销；并增加 exec 后的 **simply**（按 Clean Architecture 精简过度设计）。

官方 Superpowers 插件保留，仅在用户明确要求时使用。

## 决策摘要

| 项 | 选择 |
|---|---|
| 落地方式 | Router + 薄包装 skill（方案 1） |
| 模式选择 | Agent 按复杂度自动选；用户可随时覆盖 |
| 完整模式 | brainstorm → spec → workspace → exec → simply → test |
| 简单模式 | brainstorm(轻量) → workspace → exec → test（无长 spec、无 simply） |
| Workspace | full：`.worktrees/<topic>`；simple：在主干则建临时分支；默认不在主干实现 |
| Workspace 后 | 新建隔离后 rebase `origin/main`；结构漂移大则退回 brainstorm |
| Worktree 使用方式 | 留在当前 Cursor 窗口；读写强制 worktree 绝对路径（方案 A） |
| Simply 强度 | 默认自动精简；有争议再问 |
| Spec 正式度 | 中等：短结构落盘到 `docs/superpowers/specs/` |
| 测试策略 | 行为/逻辑 → TDD；配置/文档/幂等脚本 → 实现后验证 |
| 与官方共存 | 保留插件；用 router skill + User Rule 覆盖默认入口 |
| 存放位置 | `agents/cookbook/skills/`，经 `setup.sh sync` 链到本机 |

## 组件

均位于 `agents/cookbook/skills/`（目录布局与现有 `git/submit` 一致，可用嵌套路径）：

| Skill | 职责 |
|---|---|
| `dev-pipeline` | 总入口：判复杂度 → 选模式 → 编排子 skill；处理用户覆盖 |
| `dev-brainstorm` | 澄清意图与需求。完整模式可更深；简单模式同样必须把意图/需求问清，但更快收敛、默认不落长文档 |
| `dev-spec` | 仅完整模式：写中等短 spec |
| `dev-workspace` | exec 前隔离：full 用 `.worktrees/`；simple 在主干建分支；rebase + 漂移检查 |
| `dev-exec` | 按已确认意图/spec 实现；完整模式且多步任务时可先写短 plan |
| `dev-simply` | 仅完整模式、exec 之后：精简过度设计 |
| `dev-test` | 测试门禁（两种模式共用） |

可选：`agents/cookbook/rules/` 或 Cursor User Rule 一条，声明开发任务优先 `dev-pipeline`。

简单模式不再单独叫 `dev-ask`；澄清阶段统一走 `dev-brainstorm`，由 `dev-pipeline` 传入 mode=`full|simple` 控制深度与是否落盘。

## 模式路由

`dev-pipeline` 开场：

1. 读用户请求并粗看仓库上下文
2. 自动选择完整 / 简单，并一句话说明理由
3. 进入对应流水线；用户可覆盖

### 判定启发式

| 倾向完整 | 倾向简单 |
|---|---|
| 新功能 / 新模块 / 行为变更大 | 小修、文案、配置、单点 bug |
| 多文件 / 跨模块、需设计取舍 | 范围清晰、改动面小 |
| 用户说「设计一下 / 写 spec」 | 用户说「直接改 / 快点」 |

用户覆盖口令（示例）：`用完整流程` / `用简单流程` / `跳过 simply` / `用官方 superpowers`。

### 流水线

```text
完整: brainstorm → spec → workspace → exec → simply → test
简单: brainstorm → workspace → exec → test
```

两种模式的 brainstorm **都必须**把意图和需求搞清楚。差异仅在于：

- 完整：可多轮取舍；产出短 spec；`.worktrees/` 隔离；exec 后跑 simply
- 简单：少问快收敛（建议默认 ≤3 个关键问题）；对话内确认即可，默认不落盘；主干上则建临时分支；无 simply

## Workspace 隔离

在意图/spec 确认之后、`dev-exec` 之前执行。

| 模式 | 行为 |
|---|---|
| full | `git worktree add .worktrees/<topic> -b <branch> origin/main`；已在 linked worktree 则不嵌套 |
| simple | 当前为 `main`/`master` 则 `checkout -b` 临时分支；已在功能分支则留下 |
| 例外 | 用户明确「就在当前分支 / 主干上做」时可跳过新建隔离 |

**新建 worktree 或新建分支后：**

1. `git fetch` + `git rebase origin/main`
2. 对照已确认设计做结构漂移检查：关键路径/模块消失或搬迁、与设计冲突的主干改动 → **退回 `dev-brainstorm`**（full 时更新 spec）；小冲突则解决后继续
3. 完整模式：留在当前 Cursor 窗口，但所有读写使用 worktree **绝对路径**

脏工作区在主干建分支前须警告，避免夹带无关改动。

**`dev-exec` Preflight：** 每次改文件前在当前 workspace 跑 `git status` / `git diff`；若出现未知改动或目标文件被外部改写，先停下确认，避免与其它操作叠成内容不一致。

## Spec 与 Plan 产物

**完整模式 spec** 路径：`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`

短结构（避免长章节审批）：

1. 目标
2. 决策摘要
3. 方案 / 边界
4. 测试要点
5. 非目标

**短 plan**（可选）：`docs/superpowers/plans/YYYY-MM-DD-<topic>.md`，仅在完整模式且任务明显多步时编写。

**简单模式**：默认不落盘；用户明确要求时再写。

## Simply（Clean Architecture 精简）

触发：完整模式，在 `dev-exec` 之后、`dev-test` 之前执行。若 simply 改动了行为或测试面，`dev-test` 必须覆盖这些变更（含必要的补测）。

默认自动处理：

- 删除未使用的抽象 / 空接口 /「为未来预留」的层
- 合并过度拆分、无真实依赖倒置价值的适配层
- 保持用例边界清晰：CLI → 用例编排 → 系统/包管理/网络适配（对齐仓库 `AGENTS.md`）

必须停下来询问的情况：

- 改变对外接口或用户可见行为
- 可能削弱可测性
- 与仓库既有模块边界 / 模式明显冲突

精简后若行为可能变化，进入或重跑 `dev-test`。

## 测试门禁（`dev-test`）

| 改动类型 | 策略 |
|---|---|
| 行为 / 逻辑 / bugfix | TDD：先失败测试，再最小实现 |
| 纯配置 / 文档 / 幂等脚本调整 | 实现后做最小验证（如 `bash -n`、`--help`、相关回归、`--dry-run`） |

完成前遵守 verification-before-completion 精神：有证据再宣称通过；缺工具则如实说明未跑。

## 与官方 Superpowers 的关系

| 场景 | 行为 |
|---|---|
| 一般开发任务 | 优先读并遵循 `dev-pipeline` |
| 用户明确要求官方流程 | 可使用官方 brainstorm / writing-plans / executing-plans 等 |
| 官方其他 skill（debug、code-review、finishing-branch 等） | 在明确相关时仍可按需使用；不再充当总入口 |

通过 skill `description`（触发条件写清）+ User Rule / cookbook rule 压住 `using-superpowers`「任意会话即触发」的默认抢占。

## 同步与文档

- 实现后更新 `agents/cookbook/README.md` 的 skills 表
- 用户执行 `agents/cookbook/setup.sh sync`（或 `--target all`）使本机生效
- 不把本机绝对路径、密钥写入 cookbook

## 非目标

- 不禁用或卸载官方 Superpowers 插件
- 不完整复制官方 skill 套件
- 不强制 visual companion、冗长多轮章节审批
- 不要求用户改开 Cursor 窗口到新 worktree（用绝对路径方案 A）
- 不在简单模式执行 simply
- 不在简单模式强制创建 `.worktrees/`（仅分支隔离）
- 本设计不改根 `setup.sh` 安装逻辑（cookbook 已有独立 sync）

## Issues

### 2026-07-30 — 完整流程缺少实现前隔离与主干保护

- **表象：** 完整/简单模式可直接在主干或当前脏工作区改代码，易污染主 checkout。
- **根因：** 初版刻意不强制 worktree，未定义分支策略。
- **解法：** 增加 `dev-workspace`；full → `.worktrees/` + 绝对路径；simple → 主干则建临时分支；新建隔离后 rebase，漂移大则退回 brainstorm。
