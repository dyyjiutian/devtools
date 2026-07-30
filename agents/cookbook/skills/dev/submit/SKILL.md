---
name: dev-submit
description: >-
  Use after dev-verify succeeds in the dev-loop workflow to optionally
  organize commits and open a PR/MR. Triggers: submit, 提交, 开 PR, 开 MR,
  git-submit, commit and review. Do not auto-commit unless the user already
  asked to submit when done.
---

# Dev Submit

`dev-verify` 通过后的可选收尾：整理 commit，并按范围决定是否 rebase + 开 PR/MR。
具体提交动作委托 `git-submit`；本 skill 只负责门禁、范围确认与冲突边界。

## Gate

默认**不**主动 commit / push。

| 情况 | 行为 |
|---|---|
| 本轮对话里用户已明确说过「做完自己提交 / 做完开 PR」等 | 可跳过「是否提交」这一问，但仍须确认 Scope |
| 验证通过、用户未预先授权提交 | **先问**是否整理 commit 并进入提交流程；用户拒绝则结束闭环 |
| 验证未通过或仍有阻塞 | 不要进入本 skill |

用户拒绝提交时：报告验证已通过即可，不要偷偷 commit。

## Scope

用户同意进入提交（或已有预先授权）后，**先确认范围**再动手：

| 范围 | 含义 | 委托 |
|---|---|---|
| `local` | 仅整理并本地 commit | Read 并遵循 `git-submit`，执行到 Commit 为止；**不要** rebase / push / 开 PR |
| `remote` | 整理 commit → rebase 主干 → 开 PR/MR | Read 并遵循 `git-submit` 完整流程 |

若用户一句话说清范围（例如「只本地提交」或「提交并开 MR」），可直接采用，不必重复追问。

## Handoff

1. 宣布：`Using dev-submit (scope=<local|remote>)`
2. Read 并遵循 `git-submit`（按 Scope 裁剪步骤）
3. Rebase（仅 `remote`）冲突策略：
   - **可自动处理：** 仅我方改动、纯格式/空白、明显可机械合并且语义清晰
   - **必须停下人工确认：** 双方都改了同逻辑、删改意图不清、测试含义变化、或任何拿不准的情况
   - 自动解决后跑与冲突文件相关的最小校验，再 `git rebase --continue`
   - 不要 `rebase --skip`（除非用户同意）；不要未经授权 force push
4. 完成后回报：本地 commit 摘要；若 `remote`，附上 PR/MR URL 或 push 结果

## Hard rules

- 未通过 `dev-verify`（或用户明确只要提交、跳过验证）前，不要当闭环收尾来跑本 skill
- 不主动、不自动提交，除非 Gate 允许
- 提交前必须有明确 Scope（`local` 或 `remote`）
- 不扩大到无关文件；不提交密钥与本机敏感路径
