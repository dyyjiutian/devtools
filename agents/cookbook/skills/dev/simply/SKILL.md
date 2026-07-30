---
name: dev-simply
description: >-
  Use after implementation in full dev-loop mode to remove over-design
  using Clean Architecture judgment. Triggers: simply, 精简, 过度设计,
  YAGNI, clean architecture.
---

# Dev Simply

仅完整模式，在 `dev-execute` 之后、`dev-verify` 之前。默认自动精简；有争议再问。

对照：CLI/交互 → 用例编排 → 系统/包管理/网络适配；对齐仓库 AGENTS.md。

## Default actions

- 删除未使用抽象、空接口、「为未来预留」的空层
- 合并无真实依赖倒置价值的过度拆分
- 保持用例边界清晰，不把平台细节推回根入口

## Ask first

以下情况先问用户再改：

- 改变对外接口或用户可见行为
- 可能削弱可测性
- 与仓库既有模块边界/模式明显冲突

精简若触及行为或验证面，`dev-verify` 必须覆盖。然后进入 `dev-verify`。
