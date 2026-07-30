---
name: dev-brainstorm
description: >-
  Use when clarifying intent and requirements before implementation in the
  dev-pipeline workflow (full or simple mode). Triggers: brainstorm, 澄清需求,
  意图, 设计取舍.
---

# Dev Brainstorm

把意图和需求问清楚。simple 与 full 都必须做；差异只在深度与是否落盘。

## Modes

**simple**
- 默认 ≤3 个关键问题（一次一个）
- 对话内确认目标/约束/成功标准即可
- 默认不写 spec 文件；用户要求再落盘
- 确认后交给 `dev-exec`

**full**
- 可多轮；必要时给 2–3 个方案与取舍（YAGNI）
- 设计要点确认后交给 `dev-spec` 落盘
- 不做 visual companion；不做冗长逐章审批

## Checklist

1. 粗看相关文件 / README / 近期约定
2. 澄清目的、约束、成功标准（一次一问）
3. 需要时提出简短方案对比与推荐
4. 复述已确认结论，等用户认可
5. 按 mode 进入 `dev-spec` 或 `dev-exec`

## Hard gate

未得到用户对意图/需求的认可前，禁止实现代码。
