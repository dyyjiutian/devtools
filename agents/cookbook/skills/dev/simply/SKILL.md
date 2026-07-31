---
name: dev-simply
description: >-
  Use after implementation in full dev-loop mode to simplify code without
  sacrificing behavior or readability—prefer simpler, more elegant
  implementations. Triggers: simply, 精简, 过度设计, YAGNI, clean architecture,
  简单优雅.
---

# Dev Simply

仅完整模式，在 `dev-execute` 之后、`dev-verify` 之前。
`dev-loop` / `dev-execute` 必须**显式**进入本 skill（除非用户说「跳过 simply」）。
默认自动精简；有争议再问。

## Goal

在**不牺牲功能与可读性**的前提下精简实现：删掉过度设计，用更简单、更优雅的方式表达同一行为。
不是为精简而压缩可读性，也不是借机改需求。

对照：CLI/交互 → 用例编排 → 系统/包管理/网络适配；对齐仓库 AGENTS.md。

## Default actions

- 删除未使用抽象、空接口、「为未来预留」的空层
- 合并无真实依赖倒置价值的过度拆分
- 用更直接的结构替换绕弯实现（行为不变）
- 保持用例边界清晰，不把平台细节推回根入口
- 保留（或略提升）可读性：命名、局部性、必要注释不因「短」而变差

## Ask first

以下情况先问用户再改：

- 改变对外接口或用户可见行为
- 可能削弱可测性
- 与仓库既有模块边界/模式明显冲突

精简若触及行为或验证面，`dev-verify` 必须覆盖。然后进入 `dev-verify`。
