---
name: dev-exec
description: >-
  Use when implementing an already-clarified intent or approved short spec
  in the dev-pipeline workflow. Triggers: 实现, exec, 按 spec 做, 开始写代码.
---

# Dev Exec

按已确认意图/spec 实现。保持仓库模块边界；根入口不塞具体平台细节。

## Process

1. 若 full 且任务明显多步：可先写短 plan（可选），再动手
2. 行为/逻辑改动：先走 `dev-test` 的 TDD 要求（先失败测试）
3. 配置/文档/幂等脚本：直接最小改动，稍后用 `dev-test` 做实现后验证
4. 改动保持可重入；遵循目标模块 README / AGENTS
5. 完成后：full → `dev-simply`；simple → `dev-test`

## When to stop

- 需求缺口、验证反复失败、指令不清 → 停下询问
- 不要扩大到无关重构
