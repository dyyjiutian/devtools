---
name: dev-design
description: >-
  Use when writing a short design doc after ask in full dev-loop mode.
  Triggers: 写 design, 写 spec, design doc, docs/superpowers/specs.
---

# Dev Design

仅完整模式。把已确认设计写成短 design 文档，避免长章节审批。

## Path

`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
（日期用当天；topic 用短横线英文或拼音短语）

## Design template

文档须包含以下二级标题（顺序固定）：

1. `## 目标`
2. `## 决策摘要`
3. `## 方案 / 边界`
4. `## 测试要点`
5. `## 非目标`

### `## 测试要点` 必填内容

不可只写「加测试」；须写清：

- **层级：** UT 是否足够；是否需要功能/场景测试
- **方法：** 具体命令或测试文件意图；所需 mock / fixture / 假命令 / 临时目录
- **环境：** OS profile、Docker、网络、是否允许真实副作用（默认 dry-run / 假环境）
- **特别注意：** 兼容性（如 bash 3.2、linux_centos/macos）、性能/超时、幂等、回滚、权限/安全
- **完成证据：** `dev-verify` 阶段要跑哪些检查才算过关

## Process

1. 按模板写入（无 TBD/TODO 占位；测试要点按上表填满）
2. 自审：一致性、范围、歧义；验证策略是否可执行
3. 请用户过目；通过后进入 `dev-workspace`（再 `dev-execute`）
4. 多步任务可另写短 plan 到 `docs/superpowers/plans/YYYY-MM-DD-<topic>.md`（可选）

不要提交密钥或本机绝对路径。
