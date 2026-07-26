---
name: git-submit
description: >-
  Organize local changes into one or more Conventional Commits (feat/fix/docs/test/...),
  rebase onto the remote default branch, then open a merge request or pull request.
  Use when the user asks to submit, push for review, create an MR/PR, or run a
  commit-rebase-review flow (including 提交、整理 commit、开 MR).
---

# Git Submit

本地整理提交 → rebase 主干 → 创建 review（MR/PR）。优先使用本机已安装的 `git rb` / `git review`。

## When to use

- 用户明确要求提交、整理 commit、rebase 后开 MR/PR
- 用户说「按规范提交并 review」「submit」「创建 merge request」等

未明确要求提交时，不要主动 commit 或 push。

## Workflow

严格按顺序执行；任一步失败则停止并说明原因，不要跳过 rebase 直接 review。

### 1. Inspect

并行查看：

```bash
git status --short
git diff
git diff --cached
git log -8 --oneline
git rev-parse --abbrev-ref HEAD
git remote show origin 2>/dev/null | head -n 20
```

确认：

- 在 git 仓库内，且不在 detached HEAD（除非用户明确要求）
- 当前分支不是主干（`main` / `master` 等）；若在主干，先与用户确认是否建新分支
- 无秘密文件（`.env`、`credentials.json`、私钥等）；若用户坚持提交，先警告

### 2. Plan commits

按**逻辑变更**拆成一个或若干个 commit（不要按文件机械切开）：

| 情况 | 策略 |
|------|------|
| 单一意图 | 一个 commit |
| 多个无关意图（如 feat + 无关 docs/test） | 多个 commit |
| 纯格式/重命名与行为变更混在一起 | 尽量拆开 |

每个 commit 选用 Conventional Commits 类型：

| Type | 用途 |
|------|------|
| `feat` | 新功能 |
| `fix` | 缺陷修复 |
| `docs` | 仅文档 |
| `test` | 仅测试 |
| `refactor` | 重构（无行为变化） |
| `perf` | 性能 |
| `ci` | CI 配置 |
| `build` | 构建/依赖 |
| `chore` | 杂项维护 |
| `style` | 纯格式（不影响语义） |
| `revert` | 回滚 |

标题格式：

```text
<type>(optional-scope): <imperative summary>
```

要求：

- 英文 type 前缀；summary 简洁，聚焦 **why**，不超过约 72 字符
- 正文可选：说明动机、突破性变更、测试说明
- 跟随仓库既有 `git log` 风格（中文/英文摘要均可，但 type 保持英文）

示例：

```text
feat(cookbook): add git-submit skill for commit and review flow

docs: clarify git rb and git review usage in cookbook README
```

### 3. Commit

对每个计划中的 commit：

1. 只 stage 该 commit 相关文件（`git add` 路径或 `-p`）
2. 用 HEREDOC 写 message（避免 shell 转义问题）：

```bash
git commit -m "$(cat <<'EOF'
feat(scope): summary

Optional body.

EOF
)"
```

安全约束：

- 不要 `git config`
- 不要 `--no-verify` / `--no-gpg-sign`（除非用户明确要求）
- 不要 force push
- 避免 `commit --amend`，除非用户明确要求且符合仓库 amend 条件（你创建的 HEAD、未推送、钩子未拒绝）
- 提交失败（含 hook 拒绝）时：修复后打 **新** commit，不要 amend 被拒提交
- 若无可提交变更，不要空 commit

提交后 `git status` 确认干净或仅剩有意留下的未跟踪文件。

### 4. Rebase onto default branch

优先：

```bash
git rb
```

若 `git rb` 不可用：

```bash
git fetch origin
# 默认分支以 origin/HEAD 为准，缺省 main
git rebase "origin/$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo main)"
```

有冲突：解决 → 相关测试/校验 → `git rebase --continue`。不要 `rebase --skip` 除非用户同意。用户未授权时不要 `--force` 推送。

### 5. Open merge request / review

优先：

```bash
git review
```

若 `git review` 不可用，按 `origin` URL 回退：

| 平台 | 回退 |
|------|------|
| GitHub | `git push -u origin HEAD` 后 `gh pr create --fill --base <default>` |
| GitLab | `git push -u origin HEAD -o merge_request.create -o merge_request.target=<default>` |
| 其他 | push 当前分支，并告知用户需手动开 MR；不要编造 MR 链接 |

将 MR/PR URL 或 push 结果返回给用户。

## Done checklist

- [ ] commit message 使用 `feat`/`fix`/`docs`/`test` 等前缀
- [ ] 无关变更已拆成多个 commit（或确认只需一个）
- [ ] 已 rebase 远端主干（`git rb` 或等价命令）
- [ ] 已创建 review（`git review` 或等价回退）
- [ ] 未强制推送、未擅自跳过 hooks、未提交秘密文件
