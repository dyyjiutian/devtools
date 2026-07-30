---
name: dev-workspace
description: >-
  Use after clarifying intent (and writing a full-mode spec) and before
  implementation in the dev-pipeline workflow. Sets up branch or .worktrees
  isolation, rebases onto main, and checks for structural drift.
  Triggers: worktree, .worktrees, 临时分支, 隔离, rebase, 不在主干改.
---

# Dev Workspace

在 `dev-exec` 之前准备隔离工作区。默认**不在主干**（`main` / `master`）上直接改代码，除非用户明确要求「就在当前分支 / 主干上做」。

开场宣布：`Using dev-workspace (mode=<full|simple>, root=<path>, branch=<name>)`。

## Isolation rules

先检测是否已在 linked worktree（`git rev-parse --git-dir` 与 `--git-common-dir` 解析后不同，且不是 submodule）。若已隔离：复用当前环境，跳过创建，仍执行下方 rebase / drift 检查（若刚切到新分支或用户要求同步主干）。

### full

1. 确保仓库根存在可忽略的 `.worktrees/`（本仓库 `.gitignore` 已含；若缺失则补上并单独 commit）
2. 选短横线 topic（来自 spec / 用户说法），分支名建议 `feat/<topic>` 或 `fix/<topic>`
3. 若该 worktree / 分支尚不存在：
   ```bash
   git fetch origin
   git worktree add ".worktrees/<topic>" -b "<branch>" "origin/main"
   ```
   （默认基线为 `origin/main`；若远端默认分支不是 main，用 `origin/HEAD` 解析结果）
4. **继续留在当前 Cursor 窗口**；此后所有 Read / Write / 编辑路径必须使用该 worktree 的**绝对路径**（不要写回主 checkout）
5. Shell 默认 `working_directory` / `cd` 到该 worktree 根

### simple

1. 若当前分支是 `main` / `master`（或用户指定的默认主干）：
   - 若工作区有无关脏改动：先警告并询问（stash / 纳入本任务 / 中止），不要默默夹带
   - 从最新主干建临时分支并检出，例如：
     ```bash
     git fetch origin
     git checkout -b "<branch>" "origin/main"
     ```
2. 若当前已在非主干功能分支：留在该分支，不强制新建 worktree
3. 仍在当前工作树内改文件（无 `.worktrees`），但不得回到主干提交实现，除非用户明确要求

### 用户覆盖

- `就在当前分支做` / `就在主干上做`：跳过新建隔离（仍建议先 fetch；在主干上改必须有用户原话）
- `跳过 worktree`：完整模式也改用「仅建分支」策略（等同 simple 的分支规则）

## Rebase and drift check

**凡新建了 worktree 或新建了分支**，实现前必须：

```bash
git fetch origin
git rebase origin/main
```

（基线同 Isolation；冲突则停下解决或询问，禁止 `--force` 覆盖他人历史。）

rebase 完成后做**结构漂移检查**（对照已确认的意图 / spec）：

| 信号 | 处理 |
|---|---|
| spec 点名的路径/模块消失或大幅搬迁 | 暂停实现 → 回到 `dev-brainstorm`（full 时必要时改 `dev-spec`） |
| 同文件区域出现与设计冲突的主干变更 | 同上 |
| 依赖/入口/包布局与设计假设不一致 | 同上 |
| 仅小冲突或无关文件变化 | 解决冲突后继续 `dev-exec` |

宣布结果：`workspace ready at <abs-root> on <branch>` 或 `drift detected — returning to brainstorm`。

## Hard rules

- 未完成本 skill（或用户明确跳过隔离）前，不要开始 `dev-exec` 写生产代码
- 完整模式 worktree：禁止把实现写进主 checkout 路径
- 不要嵌套创建 worktree（已在 worktree 内再 `git worktree add`）
- `dev-exec` 每次改文件前须再检 workspace 脏状态（见该 skill 的 Preflight）；本 skill 只做进入实现前的初始隔离
- 不提交密钥、本机绝对路径到仓库文档（对话里可报告 abs path）
