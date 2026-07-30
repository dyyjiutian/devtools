---
name: dev-loop
description: >-
  Use when starting development work, implementing features, fixing bugs,
  or choosing a delivery workflow. Prefer this over official Superpowers
  as the default entry. Triggers: 开发, 实现, 修 bug, 加功能, 简单流程,
  完整流程, dev-loop, ask, design, execute, verify, TDD, worktree.
  Do not use only when the user explicitly asks for official Superpowers.
---

# Dev Loop

轻量开发闭环（快速迭代）。默认总入口；官方 Superpowers 仅在用户明确要求时使用。

开场宣布：`Using dev-loop (mode=<full|simple>)`。

## Mode selection

1. 读请求并粗看仓库上下文
2. 自动选 `full` 或 `simple`，用一句话说明理由
3. 若用户覆盖，以用户为准

| 倾向 full | 倾向 simple |
|---|---|
| 新功能 / 新模块 / 大行为变更 | 小修、文案、配置、单点 bug |
| 多文件 / 跨模块 / 需设计取舍 | 范围清晰、改动面小 |
| 用户说「设计一下 / 写 design」 | 用户说「直接改 / 快点」 |

覆盖口令：`用完整流程` / `用简单流程` / `跳过 simply` / `跳过 worktree` / `就在当前分支做` / `用官方 superpowers`。

## Loops

**full:** 依次 Read 并遵循
`dev-ask` → `dev-design` → `dev-workspace` → `dev-execute` → `dev-simply` → `dev-verify`

**simple:** 依次 Read 并遵循
`dev-ask`（传入 simple）→ `dev-workspace` → `dev-execute` → `dev-verify`
无长 design 文档、无 simply；ask 仍必须澄清意图与需求。

`dev-workspace` 负责：完整模式建 `.worktrees/`；简单模式在主干时建临时分支；新建隔离后 rebase 主干；结构漂移大则退回 `dev-ask`。

## Hard rules

- 未澄清意图前不要写生产代码（simple 也一样）
- 未完成 `dev-workspace`（或用户明确跳过隔离）前不要 `dev-execute`
- 默认不在主干上实现，除非用户明确要求
- 不要默认调用官方 `using-superpowers` / 完整官方 brainstorm 门禁
- 子 skill 按序执行；失败则停下说明，不要静默跳步
