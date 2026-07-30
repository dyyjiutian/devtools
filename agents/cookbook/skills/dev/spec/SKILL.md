---
name: dev-spec
description: >-
  Use when writing a short design spec after brainstorming in full
  dev-pipeline mode. Triggers: 写 spec, design doc, docs/superpowers/specs.
---

# Dev Spec

仅完整模式。把已确认设计写成短 spec，避免长章节审批。

## Path

`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
（日期用当天；topic 用短横线英文或拼音短语）

## Spec template

文档须包含以下二级标题（顺序固定）：

1. `## 目标`
2. `## 决策摘要`
3. `## 方案 / 边界`
4. `## 测试要点`
5. `## 非目标`

## Process

1. 按模板写入（无 TBD/TODO 占位）
2. 自审：一致性、范围、歧义
3. 请用户过目；通过后进入 `dev-workspace`（再 `dev-exec`）
4. 多步任务可另写短 plan 到 `docs/superpowers/plans/YYYY-MM-DD-<topic>.md`（可选）

不要提交密钥或本机绝对路径。
