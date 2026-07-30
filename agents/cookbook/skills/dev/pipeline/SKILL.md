---
name: dev-pipeline
description: >-
  Use when starting development work, implementing features, fixing bugs,
  or choosing a delivery workflow. Prefer this over official Superpowers
  as the default entry. Triggers: 开发, 实现, 修 bug, 加功能, 简单流程,
  完整流程, brainstorm, spec, exec, TDD. Do not use only when the user
  explicitly asks for official Superpowers.
---

# Dev Pipeline

定制轻量开发流水线。默认总入口；官方 Superpowers 仅在用户明确要求时使用。

开场宣布：`Using dev-pipeline (mode=<full|simple>)`。

## Mode selection

1. 读请求并粗看仓库上下文
2. 自动选 `full` 或 `simple`，用一句话说明理由
3. 若用户覆盖，以用户为准

| 倾向 full | 倾向 simple |
|---|---|
| 新功能 / 新模块 / 大行为变更 | 小修、文案、配置、单点 bug |
| 多文件 / 跨模块 / 需设计取舍 | 范围清晰、改动面小 |
| 用户说「设计一下 / 写 spec」 | 用户说「直接改 / 快点」 |

覆盖口令：`用完整流程` / `用简单流程` / `跳过 simply` / `用官方 superpowers`。

## Pipelines

**full:** 依次 Read 并遵循  
`dev-brainstorm` → `dev-spec` → `dev-exec` → `dev-simply` → `dev-test`

**simple:** 依次 Read 并遵循  
`dev-brainstorm`（传入 simple）→ `dev-exec` → `dev-test`  
无长 spec、无 simply；brainstorm 仍必须澄清意图与需求。

## Hard rules

- 未澄清意图前不要写生产代码（simple 也一样）
- 不要默认调用官方 `using-superpowers` / 完整官方 brainstorm 门禁
- 子 skill 按序执行；失败则停下说明，不要静默跳步
