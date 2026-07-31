---
name: dev-loop
description: >-
  Use when starting development work, implementing features, fixing known
  bugs, or choosing a delivery workflow. Prefer this over official Superpowers
  as the default entry for implementation. Triggers: 开发, 实现, 修 bug,
  加功能, 简单流程, 完整流程, dev-loop, ask, design, execute, verify,
  submit, TDD, worktree. Do not use as the forced path for open-ended
  debugging or root-cause investigation; leave that to native agent judgment.
  Do not use only when the user explicitly asks for official Superpowers.
---

# Dev Loop

轻量开发闭环（快速迭代）。**实现类任务**的默认总入口；官方 Superpowers 仅在用户明确要求时使用。

开场宣布：`Using dev-loop (mode=<full|simple>)`，或在分流后宣布不进入本闭环。

## Task triage

在 Mode selection 之前先判断任务类型：

| 类型 | 行为 |
|---|---|
| 实现 / 已知缺陷修复 / 加功能 / 改配置或文档 | 进入本闭环（选 full 或 simple） |
| debug / 排查 / 原因不明的异常或测试失败 / 根因尚未清楚 | **不要进入** ask→execute 实现闭环；交给**原生 agent 自行判断**排查路径（不强制官方 Superpowers，也不禁止在判断后选用） |
| 根因已清楚且需要改代码 | 再进入本闭环做修复（含 verify） |

用户明确要求「用官方 superpowers / systematic-debugging」时，从其要求。

## Mode selection

1. 读请求并粗看仓库上下文（且已通过 Task triage）
2. 自动选 `full` 或 `simple`，用一句话说明理由
3. 若用户覆盖，以用户为准

| 倾向 full | 倾向 simple |
|---|---|
| 新功能 / 新模块 / 大行为变更 | 小修、文案、配置、单点已知 bug |
| 多文件 / 跨模块 / 需设计取舍 | 范围清晰、改动面小 |
| 用户说「设计一下 / 写 design」 | 用户说「直接改 / 快点」 |

覆盖口令：`用完整流程` / `用简单流程` / `跳过 simply` / `跳过 worktree` / `就在当前分支做` / `用官方 superpowers`。

## Loops

**full:** 依次 Read 并遵循
`dev-ask` → `dev-design` → `dev-workspace` → `dev-execute` → `dev-simply` → `dev-verify` → `dev-submit`

**simple:** 依次 Read 并遵循
`dev-ask`（传入 simple）→ `dev-workspace` → `dev-execute` → `dev-verify` → `dev-submit`
无长 design 文档、无 simply；ask 仍必须澄清意图与需求；**必须有** verify（按改动选回归老用例或补新用例）。

`dev-simply`（仅 full，除非用户「跳过 simply」）：execute 之后**必须**显式 Read 并执行；在不牺牲功能与可读性的前提下精简，用更简单优雅的实现。

`dev-submit`：验证通过后询问是否整理 commit；默认不自动提交（除非本轮已授权）；先确认 `local`（仅本地 commit）或 `remote`（rebase + 开 PR/MR），细节委托 `git-submit`。

`dev-workspace` 负责：完整模式建 `.worktrees/`；简单模式在主干时建临时分支；新建隔离后 rebase 主干；结构漂移大则退回 `dev-ask`。

## Hard rules

- 未澄清意图前不要写生产代码（simple 也一样）
- 未完成 `dev-workspace`（或用户明确跳过隔离）前不要 `dev-execute`
- 默认不在主干上实现，除非用户明确要求
- full 在 execute 之后必须进入 `dev-simply`（除非用户跳过）
- simple 与 full 都必须经过 `dev-verify`，不得用「改动很小」跳过
- 不要默认调用官方 `using-superpowers` / 完整官方 brainstorm 门禁
- 子 skill 按序执行；失败则停下说明，不要静默跳步
