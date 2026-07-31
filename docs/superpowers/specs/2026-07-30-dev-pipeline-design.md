# 定制 Dev Loop（轻量 Superpowers）设计

## 目标

用 cookbook 中的薄路由工作流，替代官方 Superpowers 作为**默认开发总入口**，在保留 ask / design / execute / verify 纪律的同时降低流程开销；并增加 execute 后的 **simply**（按 Clean Architecture 精简过度设计）。

官方 Superpowers 插件保留，仅在用户明确要求时使用。

命名：总入口为 `dev-loop`（开发闭环 / 快速迭代）；子步骤为 ask → design → workspace → execute → simply → verify → submit。

## 决策摘要

| 项 | 选择 |
|---|---|
| 落地方式 | Router + 薄包装 skill（方案 1） |
| 总入口名 | `dev-loop`（原 dev-pipeline） |
| 模式选择 | 先任务分流；实现类再按复杂度选 full/simple；用户可随时覆盖 |
| Debug 分流 | 排查/根因不清不进实现闭环，留给原生 agent 判断；根因清楚再进 loop |
| 完整模式 | ask → design → workspace → execute → simply → verify → submit |
| 简单模式 | ask(轻量) → workspace → execute → verify → submit（无长 design、无 simply；须有 verify） |
| Simply | 仅 full 且须显式执行；不牺牲功能/可读性，用更简单优雅的实现 |
| Verify 覆盖 | 按改动选回归老用例或补新用例（simple/full 相同） |
| Workspace | full：`.worktrees/<topic>`；simple：在主干则建临时分支；默认不在主干实现 |
| Workspace 后 | 新建隔离后 rebase `origin/main`；结构漂移大则退回 ask |
| Worktree 使用方式 | 留在当前 Cursor 窗口；读写强制 worktree 绝对路径（方案 A） |
| Simply 强度 | 默认自动精简（须显式调用）；有争议再问；不以牺牲可读性换短 |
| Design 正式度 | 中等：短结构落盘到 `docs/superpowers/specs/` |
| 验证策略 | 行为/逻辑 → TDD；配置/文档/幂等脚本 → 实现后验证；须判断回归 vs 新用例；门禁 `dev-verify` |
| 与官方共存 | 保留插件；用 router skill + User Rule 覆盖默认入口 |
| 存放位置 | `agents/cookbook/skills/`，经 `setup.sh sync` 链到本机 |

## 组件

均位于 `agents/cookbook/skills/`（目录布局与现有 `git/submit` 一致，可用嵌套路径）：

| Skill | 职责 |
|---|---|
| `dev-loop` | 总入口：任务分流 → 判复杂度 → 选模式 → 编排子 skill；处理用户覆盖 |
| `dev-ask` | 澄清意图与需求及验证策略（含回归 vs 新用例）。完整模式可更深；简单模式更快收敛、默认不落长文档 |
| `dev-design` | 仅完整模式：写中等短 design |
| `dev-workspace` | execute 前隔离：full 用 `.worktrees/`；simple 在主干建分支；rebase + 漂移检查 |
| `dev-execute` | 按已确认意图/design 实现；完整模式且多步任务时可先写短 plan；完成后显式交 simply（full） |
| `dev-simply` | 仅完整模式、execute 之后须显式执行：不牺牲功能/可读性的精简 |
| `dev-verify` | 验证门禁（两种模式都必须；按改动回归或补新用例） |
| `dev-submit` | verify 后可选收尾：询问是否提交；确认 local/remote 后委托 `git-submit` |

可选：`agents/cookbook/rules/prefer-dev-loop.mdc`，声明开发任务优先 `dev-loop`。

澄清阶段统一走 `dev-ask`，由 `dev-loop` 传入 mode=`full|simple` 控制深度与是否落盘。

## 模式路由

`dev-loop` 开场：

1. 读用户请求并粗看仓库上下文；先做任务分流（debug/排查且根因不清 → 不进实现闭环，留给原生判断）
2. 实现类任务：自动选择完整 / 简单，并一句话说明理由
3. 进入对应闭环；用户可覆盖

### 判定启发式

| 倾向完整 | 倾向简单 |
|---|---|
| 新功能 / 新模块 / 行为变更大 | 小修、文案、配置、单点 bug |
| 多文件 / 跨模块、需设计取舍 | 范围清晰、改动面小 |
| 用户说「设计一下 / 写 design」 | 用户说「直接改 / 快点」 |

用户覆盖口令（示例）：`用完整流程` / `用简单流程` / `跳过 simply` / `用官方 superpowers`。

### 闭环

```text
完整: ask → design → workspace → execute → simply → verify
简单: ask → workspace → execute → verify
```

两种模式的 ask **都必须**把意图和需求搞清楚。差异仅在于：

- 完整：可多轮取舍；产出短 design；`.worktrees/` 隔离；execute 后跑 simply
- 简单：少问快收敛（建议默认 ≤3 个关键问题）；对话内确认即可，默认不落盘；主干上则建临时分支；无 simply

## Workspace 隔离

在意图/design 确认之后、`dev-execute` 之前执行。

| 模式 | 行为 |
|---|---|
| full | `git worktree add .worktrees/<topic> -b <branch> origin/main`；已在 linked worktree 则不嵌套 |
| simple | 当前为 `main`/`master` 则 `checkout -b` 临时分支；已在功能分支则留下 |
| 例外 | 用户明确「就在当前分支 / 主干上做」时可跳过新建隔离 |

**新建 worktree 或新建分支后：**

1. `git fetch` + `git rebase origin/main`
2. 对照已确认设计做结构漂移检查：关键路径/模块消失或搬迁、与设计冲突的主干改动 → **退回 `dev-ask`**（full 时更新 design）；小冲突则解决后继续
3. 完整模式：留在当前 Cursor 窗口，但所有读写使用 worktree **绝对路径**

脏工作区在主干建分支前须警告，避免夹带无关改动。

**`dev-execute` Preflight：** 每次改文件前在当前 workspace 跑 `git status` / `git diff`；若出现未知改动或目标文件被外部改写，先停下确认，避免与其它操作叠成内容不一致。

## Design 与 Plan 产物

**完整模式 design** 路径：`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`

短结构（避免长章节审批）：

1. 目标
2. 决策摘要
3. 方案 / 边界
4. 测试要点（必填：层级 UT/场景、mock/夹具/环境、兼容性或性能等特别点、完成证据）
5. 非目标

ask 阶段就必须与用户对齐验证策略；simple 模式至少口头确认「怎么验」以及回归老用例还是补新用例，full 写入 design。`dev-verify` 按该约定执行，不得无说明降级。

**短 plan**（可选）：`docs/superpowers/plans/YYYY-MM-DD-<topic>.md`，仅在完整模式且任务明显多步时编写。

**简单模式**：默认不落盘；用户明确要求时再写。

## Simply（Clean Architecture 精简）

触发：完整模式，在 `dev-execute` 之后、`dev-verify` 之前**必须显式**执行（除非用户跳过）。
目标：在不牺牲功能与可读性的前提下，用更简单优雅的方式实现同一行为。若 simply 改动了行为或验证面，`dev-verify` 必须覆盖这些变更（含必要的补测）。

默认自动处理：

- 删除未使用的抽象 / 空接口 /「为未来预留」的层
- 合并过度拆分、无真实依赖倒置价值的适配层
- 用更直接的结构替换绕弯实现（行为不变）
- 保持用例边界清晰：CLI → 用例编排 → 系统/包管理/网络适配（对齐仓库 `AGENTS.md`）

必须停下来询问的情况：

- 改变对外接口或用户可见行为
- 可能削弱可测性
- 与仓库既有模块边界 / 模式明显冲突

精简后若行为可能变化，进入或重跑 `dev-verify`。

## 验证门禁（`dev-verify`）

simple 与 full 都必须经过本门禁。

| 改动类型 | 策略 |
|---|---|
| 行为 / 逻辑 / bug fix | TDD：先失败测试，再最小实现 |
| 纯配置 / 文档 / 幂等脚本调整 | 实现后做最小验证（如 `bash -n`、`--help`、相关回归、`--dry-run`） |

覆盖选择：现有用例能盖住则回归；盖不住则设计/补新用例；部分覆盖则二者兼用。

完成前遵守 verification-before-completion 精神：有证据再宣称通过；缺工具则如实说明未跑。

## 提交收尾（`dev-submit`）

验证通过后进入可选收尾（两种模式共用）：

- 默认不主动 commit / push；本轮已明确「做完自己提交」可跳过「是否提交」一问，但仍须确认范围
- 范围：`local`（仅本地 commit）或 `remote`（commit → rebase 主干 → 开 PR/MR）
- 细节委托 `git-submit`；rebase 冲突仅自动处理明显可判项，拿不准则人工确认

## 与官方 Superpowers 的关系

| 场景 | 行为 |
|---|---|
| 一般实现/已知缺陷修复 | 优先读并遵循 `dev-loop` |
| debug / 排查 / 根因不清 | 不进 `dev-loop` 实现闭环；留给原生 agent 自行判断（可选用官方 debug skill，但不强制） |
| 用户明确要求官方流程 | 可使用官方 brainstorm / writing-plans / executing-plans 等 |
| 官方其他 skill（debug、code-review、finishing-branch 等） | 在明确相关或原生判断选用时可用；不再充当实现总入口 |

通过 skill `description`（触发条件写清）+ User Rule / cookbook rule 压住 `using-superpowers`「任意会话即触发」的默认抢占。

## 同步与文档

- 实现后更新 `agents/cookbook/README.md` 的 skills 表
- 用户执行 `agents/cookbook/setup.sh sync`（或 `--target all`）使本机生效；旧名 skill 链接需 unlink 后重 sync
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
- **解法：** 增加 `dev-workspace`；full → `.worktrees/` + 绝对路径；simple → 主干则建临时分支；新建隔离后 rebase，漂移大则退回 ask。

### 2026-07-30 — 设计阶段测试策略过粗

- **表象：** design「测试要点」可写成空话，实现后才决定测什么。
- **根因：** ask/design 未强制对齐 UT vs 场景/mock/环境及兼容性/性能点。
- **解法：** ask 增加 Testing strategy；design `## 测试要点` 必填层级/方法/环境/特别点/完成证据；`dev-verify` 按设计执行不得无说明降级。

### 2026-07-30 — 命名对齐快速迭代语义

- **表象：** `dev-pipeline` / brainstorm / spec / exec / test 偏重流程与单测用语。
- **根因：** 初版沿用 Superpowers 词汇。
- **解法：** 总入口改为 `dev-loop`；子 skill 改为 ask / design / execute / verify（workspace、simply 保留）。

### 2026-07-30 — 验证通过后缺少提交收尾

- **表象：** `dev-verify` 结束后闭环停止，不会询问整理 commit / 开 PR；也易与「主动自动提交」混淆。
- **根因：** 初版未定义 submit 步骤；提交能力只在独立 `git-submit`。
- **解法：** 增加 `dev-submit`（verify 之后）；默认先问；确认 `local`/`remote` 后委托 `git-submit`；rebase 冲突仅安全自动解决。

### 2026-07-31 — debug 分流、simply 显式化与 simple 模式验证

- **表象：** 排查类任务被套进实现闭环；simply 少被显式调用且目标偏「删抽象」；simple 模式易弱化 verify。
- **根因：** 总入口未做任务分流；simply/verify 约定不够硬。
- **解法：** `dev-loop` 增加 Task triage（debug 留给原生判断）；强化 simply 的 Goal 与显式调用；verify 增加 Coverage choice（回归 vs 新用例），simple/full 都必须过门禁。
