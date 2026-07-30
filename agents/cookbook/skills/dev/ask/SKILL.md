---
name: dev-ask
description: >-
  Use when clarifying intent and requirements before implementation in the
  dev-loop workflow (full or simple mode). Triggers: ask, brainstorm, 澄清需求,
  意图, 设计取舍.
---

# Dev Ask

把意图和需求问清楚。simple 与 full 都必须做；差异只在深度与是否落盘。

## Modes

**simple**
- 默认 ≤3 个关键问题（一次一个）；其中应覆盖「怎么验证」或把它并进成功标准
- 对话内确认目标/约束/成功标准/**验证方式**即可
- 默认不写 design 文件；用户要求再落盘
- 确认后交给 `dev-workspace`（再 `dev-execute`）

**full**
- 可多轮；必要时给 2–3 个方案与取舍（YAGNI）
- 必须明确验证策略后再交给 `dev-design` 落盘（见 Testing strategy）
- 不做 visual companion；不做冗长逐章审批

## Testing strategy

设计阶段就要定清「如何证明做对了」，不要留到实现后再猜。至少对齐：

| 维度 | 要明确的内容 |
|---|---|
| 层级 | 仅 UT / 需要场景或功能测试 / 两者都要 |
| 夹具 | 是否要特定场景、fixture、mock、假命令、临时目录 |
| 环境 | 是否依赖特定 OS、Docker、网络、sudo、真实安装（默认避免） |
| 特别点 | 兼容性（bash 版本、平台）、性能/超时、幂等、回滚、安全敏感路径 |

simple：用一两句话确认默认策略（例如「结构测试 + `bash -n`」或「补一条回归」）。
full：在复述结论里写清上表；写入 design 的 `## 测试要点`。

## Checklist

1. 粗看相关文件 / README / 近期约定
2. 澄清目的、约束、成功标准（一次一问）
3. 澄清验证策略（层级、夹具/环境、特别注意点）
4. 需要时提出简短方案对比与推荐
5. 复述已确认结论（含验证策略），等用户认可
6. 按 mode 进入 `dev-design` 或 `dev-workspace`
7. 若因 rebase 结构漂移而退回：重新评估设计与验证假设，再走后续步骤

## Drift re-entry

从 `dev-workspace` 因主干结构漂移退回时：对照新树重新核对边界、方案与验证策略，更新结论（full 时改 design），再交给 `dev-workspace`。

## Hard gate

未得到用户对意图/需求/**验证策略**的认可前，禁止实现代码。
