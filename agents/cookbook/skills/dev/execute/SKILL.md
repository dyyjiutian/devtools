---
name: dev-execute
description: >-
  Use when implementing an already-clarified intent or approved short design
  in the dev-loop workflow. Triggers: 实现, execute, exec, 按 design 做, 开始写代码.
---

# Dev Execute

按已确认意图/design 实现。保持仓库模块边界；根入口不塞具体平台细节。

前提：已完成 `dev-workspace`（或用户明确跳过隔离）。完整模式若使用 `.worktrees/`，所有编辑必须落在该 worktree 绝对路径下。

## Preflight

**每次**准备改文件之前（含开写第一批、长任务中途休息后再改、切换子任务前），在**当前 workspace 根**检测是否有「非本会话预期」的变动：

```bash
git status --short
git diff --stat
git diff --cached --stat
```

| 情况 | 处理 |
|---|---|
| 干净，或仅有本会话已知未提交改动 | 继续 |
| 出现未知/他人/其它工具改动的文件 | **先停下**：列出路径，对照意图；询问纳入、还原，或重读后再改 |
| 预期要改的文件内容与上次读取不一致（被外部改写） | **先停下**：重新 Read，必要时退回 `dev-ask` / 调整方案 |

不要在未确认的脏状态上继续 Write，避免与外部改动叠成不一致。

## Process

1. 确认工作根与分支与 `dev-workspace` 宣布的一致
2. 跑 Preflight；异常则停，不开始改
3. 若 full 且任务明显多步：可先写短 plan（可选），再动手
4. 行为/逻辑改动：先走 `dev-verify` 的 TDD 要求（先失败测试）
5. 配置/文档/幂等脚本：直接最小改动，稍后用 `dev-verify` 做实现后验证
6. 改动保持可重入；遵循目标模块 README / AGENTS
7. 每轮较大编辑前可再跑一次 Preflight
8. 完成后：full → **必须** Read 并遵循 `dev-simply`（除非用户跳过）→ `dev-verify`；simple → `dev-verify`（simple 无 simply，但 verify 不可跳过）

## When to stop

- Preflight 发现未知改动或目标文件被外部改写 → 停下询问
- 需求缺口、验证反复失败、指令不清 → 停下询问
- 发现实现根目录仍是主干 checkout 且 mode=full 已建 worktree → 停下纠正路径
- 不要扩大到无关重构
