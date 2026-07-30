# Dev Pipeline（轻量 Superpowers）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `agents/cookbook` 落地可同步的定制开发流水线 skills，默认覆盖官方 Superpowers 总入口，支持完整/简单双模式与 exec 后的 simply。

**Architecture:** `dev-pipeline` 作路由器（自动选模式 + 用户覆盖），子 skill 各自负责 brainstorm / spec / exec / simply / test；用 skill description + Cursor rule 压住官方 `using-superpowers`；经现有 `setup.sh sync` 链到本机 skills。

**Tech Stack:** Markdown Agent Skills（YAML frontmatter）、Bash（cookbook `setup.sh` + 结构校验测试）、Cursor rules（`.mdc`）。

## Global Constraints

- 存放：`agents/cookbook/skills/`（嵌套目录可，链接名取 frontmatter `name`）
- 完整模式：brainstorm → spec → exec → simply → test
- 简单模式：brainstorm → exec → test（无长 spec、无 simply；brainstorm 仍须澄清意图与需求）
- Spec 路径：`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`（短结构）
- Simply：默认自动精简；接口/可测性/既有模式冲突时询问
- 测试策略：行为/逻辑 → TDD；配置/文档/幂等脚本 → 实现后验证
- 保留官方插件；仅用户明确要求时走官方总流程
- 不提交本机绝对路径、密钥；不强制 worktree / visual companion
- 技能文案以中文为主（与 cookbook / AGENTS 一致），description 可用中英触发词

---

### Task 1: Skills 结构校验测试（先红）

**Files:**
- Create: `agents/cookbook/tests/skills_structure_test.sh`
- Modify: none yet（实现 skills 后变绿）

**Interfaces:**
- Consumes: 无
- Produces: 可执行测试脚本；断言每个 cookbook `SKILL.md` 具备 `name`/`description` frontmatter，且 `dev-*` 技能含约定标题

- [ ] **Step 1: 写入失败测试脚本**

```bash
#!/usr/bin/env bash
# 校验 agents/cookbook/skills 下 SKILL.md 结构（不执行真实 agent）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS="$ROOT/skills"
fail=0

assert_file() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo "FAIL: missing $f" >&2
    fail=1
  fi
}

assert_frontmatter_field() {
  local f="$1" field="$2"
  if ! grep -q "^${field}:" "$f"; then
    echo "FAIL: $f missing frontmatter field: $field" >&2
    fail=1
  fi
}

assert_heading() {
  local f="$1" heading="$2"
  if ! grep -qE "^#+ ${heading}" "$f"; then
    echo "FAIL: $f missing heading: $heading" >&2
    fail=1
  fi
}

REQUIRED_DEV_SKILLS=(
  "dev/pipeline/SKILL.md"
  "dev/brainstorm/SKILL.md"
  "dev/spec/SKILL.md"
  "dev/exec/SKILL.md"
  "dev/simply/SKILL.md"
  "dev/test/SKILL.md"
)

for rel in "${REQUIRED_DEV_SKILLS[@]}"; do
  assert_file "$SKILLS/$rel"
done

# 若文件尚不存在，上面已 fail；对存在的文件继续检查
while IFS= read -r -d '' skill_md; do
  assert_frontmatter_field "$skill_md" "name"
  assert_frontmatter_field "$skill_md" "description"
done < <(find "$SKILLS" -type f -name 'SKILL.md' -print0)

for rel in "${REQUIRED_DEV_SKILLS[@]}"; do
  f="$SKILLS/$rel"
  [[ -f "$f" ]] || continue
  case "$rel" in
    */pipeline/*) assert_heading "$f" "Mode selection"; assert_heading "$f" "Pipelines" ;;
    */brainstorm/*) assert_heading "$f" "Modes"; assert_heading "$f" "Checklist" ;;
    */spec/*) assert_heading "$f" "Spec template"; assert_heading "$f" "Path" ;;
    */exec/*) assert_heading "$f" "Process"; assert_heading "$f" "When to stop" ;;
    */simply/*) assert_heading "$f" "Default actions"; assert_heading "$f" "Ask first" ;;
    */test/*) assert_heading "$f" "Strategy"; assert_heading "$f" "Evidence" ;;
  esac
done

if [[ "$fail" -ne 0 ]]; then
  echo "skills_structure_test: FAILED" >&2
  exit 1
fi
echo "skills_structure_test: OK"
```

- [ ] **Step 2: 跑测试，确认失败**

```bash
bash agents/cookbook/tests/skills_structure_test.sh
```

Expected: FAIL，报 missing `agents/cookbook/skills/dev/.../SKILL.md`

- [ ] **Step 3: Commit 测试**

```bash
git add agents/cookbook/tests/skills_structure_test.sh
git commit -m "$(cat <<'EOF'
test(cookbook): add structure checks for dev-pipeline skills

EOF
)"
```

---

### Task 2: `dev-pipeline` 路由 skill

**Files:**
- Create: `agents/cookbook/skills/dev/pipeline/SKILL.md`

**Interfaces:**
- Consumes: 用户请求；子 skill 名称约定 `dev-brainstorm` / `dev-spec` / `dev-exec` / `dev-simply` / `dev-test`
- Produces: frontmatter `name: dev-pipeline`；编排入口与模式启发式

- [ ] **Step 1: 创建 SKILL.md**

内容必须包含（可微调措辞，不可删节职责）：

```markdown
---
name: dev-pipeline
description: >-
  Use when starting development work, implementing features, fixing bugs,
  or choosing a delivery workflow. Prefer this over official Superpowers
  as the default entry. Triggers: 开发, 实现, 修 bug, 加功能, 简单流程,
  完整流程, brainstorm, spec, exec, TDD. Do not use only when the user
  explicitly asks for official Superpowers.
---

# Dev Pipeline

定制轻量开发流水线。默认总入口；官方 Superpowers 仅在用户明确要求时使用。

开场宣布：`Using dev-pipeline (mode=<full|simple>)`。

## Mode selection

1. 读请求并粗看仓库上下文
2. 自动选 `full` 或 `simple`，用一句话说明理由
3. 若用户覆盖，以用户为准

| 倾向 full | 倾向 simple |
|---|---|
| 新功能 / 新模块 / 大行为变更 | 小修、文案、配置、单点 bug |
| 多文件 / 跨模块 / 需设计取舍 | 范围清晰、改动面小 |
| 用户说「设计一下 / 写 spec」 | 用户说「直接改 / 快点」 |

覆盖口令：`用完整流程` / `用简单流程` / `跳过 simply` / `用官方 superpowers`。

## Pipelines

**full:** 依次 Read 并遵循  
`dev-brainstorm` → `dev-spec` → `dev-exec` → `dev-simply` → `dev-test`

**simple:** 依次 Read 并遵循  
`dev-brainstorm`（传入 simple）→ `dev-exec` → `dev-test`  
无长 spec、无 simply；brainstorm 仍必须澄清意图与需求。

## Hard rules

- 未澄清意图前不要写生产代码（simple 也一样）
- 不要默认调用官方 `using-superpowers` / 完整官方 brainstorm 门禁
- 子 skill 按序执行；失败则停下说明，不要静默跳步
```

- [ ] **Step 2: 确认 frontmatter name 可被 setup 解析**

```bash
sed -n 's/^name:[[:space:]]*//p' agents/cookbook/skills/dev/pipeline/SKILL.md | head -1
```

Expected: `dev-pipeline`

- [ ] **Step 3: Commit**

```bash
git add agents/cookbook/skills/dev/pipeline/SKILL.md
git commit -m "$(cat <<'EOF'
feat(cookbook): add dev-pipeline router skill

EOF
)"
```

---

### Task 3: `dev-brainstorm` skill

**Files:**
- Create: `agents/cookbook/skills/dev/brainstorm/SKILL.md`

**Interfaces:**
- Consumes: `dev-pipeline` 传入的 mode=`full|simple`
- Produces: 已确认的意图/需求；full 时可进入 `dev-spec`

- [ ] **Step 1: 创建 SKILL.md**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add agents/cookbook/skills/dev/brainstorm/SKILL.md
git commit -m "$(cat <<'EOF'
feat(cookbook): add dev-brainstorm skill

EOF
)"
```

---

### Task 4: `dev-spec` skill

**Files:**
- Create: `agents/cookbook/skills/dev/spec/SKILL.md`

**Interfaces:**
- Consumes: brainstorm 已确认结论（full only）
- Produces: `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`

- [ ] **Step 1: 创建 SKILL.md**

```markdown
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

```markdown
# <标题>设计

## 目标
## 决策摘要
## 方案 / 边界
## 测试要点
## 非目标
```

## Process

1. 按模板写入（无 TBD/TODO 占位）
2. 自审：一致性、范围、歧义
3. 请用户过目；通过后进入 `dev-exec`
4. 多步任务可另写短 plan 到 `docs/superpowers/plans/YYYY-MM-DD-<topic>.md`（可选）

不要提交密钥或本机绝对路径。
```

- [ ] **Step 2: Commit**

```bash
git add agents/cookbook/skills/dev/spec/SKILL.md
git commit -m "$(cat <<'EOF'
feat(cookbook): add dev-spec skill

EOF
)"
```

---

### Task 5: `dev-exec` skill

**Files:**
- Create: `agents/cookbook/skills/dev/exec/SKILL.md`

**Interfaces:**
- Consumes: 已确认意图（simple）或已批准 spec（full）
- Produces: 代码/配置改动；随后 full→`dev-simply`，simple→`dev-test`

- [ ] **Step 1: 创建 SKILL.md**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add agents/cookbook/skills/dev/exec/SKILL.md
git commit -m "$(cat <<'EOF'
feat(cookbook): add dev-exec skill

EOF
)"
```

---

### Task 6: `dev-simply` skill

**Files:**
- Create: `agents/cookbook/skills/dev/simply/SKILL.md`

**Interfaces:**
- Consumes: exec 产物（full only）
- Produces: 精简后的代码；再进入 `dev-test`

- [ ] **Step 1: 创建 SKILL.md**

```markdown
---
name: dev-simply
description: >-
  Use after implementation in full dev-pipeline mode to remove over-design
  using Clean Architecture judgment. Triggers: simply, 精简, 过度设计,
  YAGNI, clean architecture.
---

# Dev Simply

仅完整模式，在 `dev-exec` 之后、`dev-test` 之前。默认自动精简；有争议再问。

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

精简若触及行为或测试面，`dev-test` 必须覆盖。然后进入 `dev-test`。
```

- [ ] **Step 2: Commit**

```bash
git add agents/cookbook/skills/dev/simply/SKILL.md
git commit -m "$(cat <<'EOF'
feat(cookbook): add dev-simply skill

EOF
)"
```

---

### Task 7: `dev-test` skill

**Files:**
- Create: `agents/cookbook/skills/dev/test/SKILL.md`

**Interfaces:**
- Consumes: exec（及 full 下 simply）后的改动
- Produces: 有证据的验证结果；未跑的检查如实说明

- [ ] **Step 1: 创建 SKILL.md**

```markdown
---
name: dev-test
description: >-
  Use as the verification gate in dev-pipeline after exec (and simply in
  full mode). Triggers: TDD, 补测, 验证, verification, regression.
---

# Dev Test

两种模式共用的测试门禁。完成前必须有证据；缺工具则说明未跑，不得假称通过。

## Strategy

| 改动类型 | 策略 |
|---|---|
| 行为 / 逻辑 / bugfix | TDD：先写失败测试 → 最小实现 → 转绿 |
| 纯配置 / 文档 / 幂等脚本 | 实现后最小验证（`bash -n`、`--help`、相关回归、`--dry-run`） |

## Evidence

按改动范围选择最小充分检查，例如：

```bash
git diff --check
bash -n path/to/script.sh
bash agents/cookbook/tests/skills_structure_test.sh
```

涉及安装器时优先 `--help` / `--dry-run`，不要为验证跑真实安装。

## Done criteria

- 相关测试/检查已执行并记录结果
- 失败已修复或已向用户说明阻塞
- 未宣称“全部通过”若实际跳过了关键检查
```

- [ ] **Step 2: 跑结构测试，确认转绿**

```bash
bash agents/cookbook/tests/skills_structure_test.sh
```

Expected: `skills_structure_test: OK`

- [ ] **Step 3: Commit**

```bash
git add agents/cookbook/skills/dev/test/SKILL.md
git commit -m "$(cat <<'EOF'
feat(cookbook): add dev-test skill

EOF
)"
```

---

### Task 8: Cursor rule + cookbook README + setup 说明

**Files:**
- Create: `agents/cookbook/rules/prefer-dev-pipeline.mdc`
- Modify: `agents/cookbook/README.md`
- Modify: `agents/cookbook/setup.sh`（仅帮助文案/status 提示 rule 需手动或可选同步；若实现成本低则增加 `rules` 同步到 `~/.cursor/rules/`）

**Interfaces:**
- Consumes: 已存在的六件 `dev-*` skills
- Produces: alwaysApply 风格规则模板；README 表格与同步说明

- [ ] **Step 1: 创建 rule 模板**

`agents/cookbook/rules/prefer-dev-pipeline.mdc`:

```markdown
---
description: Prefer cookbook dev-pipeline over official Superpowers as default entry
alwaysApply: true
---

# Prefer Dev Pipeline

对开发/实现/修 bug/加功能类任务：

1. 优先 Read 并遵循 skill `dev-pipeline`
2. 不要默认走官方 `using-superpowers` 全流程
3. 仅当用户明确说「用官方 superpowers」时才使用官方总入口
4. 用户可覆盖模式：`用完整流程` / `用简单流程` / `跳过 simply`
```

- [ ] **Step 2: 扩展 `setup.sh` 同步 rules（符号链接到 `~/.cursor/rules/`）**

在现有 skills sync 旁增加：

- 源：`$SCRIPT_DIR/rules/*.mdc`
- 目标：`${CURSOR_RULES_DIR:-$HOME/.cursor/rules}/<basename>`
- `sync` / `status` / `unlink` 均覆盖；`--dry-run` 可用
- Claude 目标可跳过 rules（或同样链到若存在的 claude rules 路径；默认只做 Cursor）

保持幂等：已是指向同源的链接则跳过；非 cookbook 链接不覆盖目录。

- [ ] **Step 3: 更新 README**

在「现有 skills」表增加六行 `dev-*`，并增加「Rules」小节说明 `prefer-dev-pipeline` 与 `sync` 行为。

- [ ] **Step 4: 语法与结构校验**

```bash
bash -n agents/cookbook/setup.sh
bash agents/cookbook/tests/skills_structure_test.sh
bash agents/cookbook/setup.sh sync --dry-run
bash agents/cookbook/setup.sh status
```

Expected: 均成功；dry-run 列出六个 `dev-*` 链接与 rule 链接意图

- [ ] **Step 5: Commit**

```bash
git add agents/cookbook/rules/prefer-dev-pipeline.mdc agents/cookbook/README.md agents/cookbook/setup.sh
git commit -m "$(cat <<'EOF'
feat(cookbook): prefer dev-pipeline rule and document sync

EOF
)"
```

---

### Task 9: 本机生效与手工冒烟

**Files:**
- None in repo（本机链接）

**Interfaces:**
- Consumes: Task 1–8 产物
- Produces: `~/.cursor/skills/dev-*` 与 `~/.cursor/rules/prefer-dev-pipeline.mdc` 链接

- [ ] **Step 1: 同步到本机**

```bash
bash agents/cookbook/setup.sh sync
bash agents/cookbook/setup.sh status
```

Expected: 六个 `dev-*` 已链接；rule 已链接或按实现显示状态

- [ ] **Step 2: 冒烟（人工/下一会话）**

用一句话任务验证路由，例如：「给 README 加一个无关紧要的空格」应选 **simple**；「设计一个新的 cookbook command 入口」应选 **full**。在回复中应看到 `Using dev-pipeline (mode=...)`。

- [ ] **Step 3: 若用户要求，再整理 commit / review**（使用 `git-submit`，勿擅自 push）

---

## Spec coverage checklist

| Spec 要求 | Task |
|---|---|
| Router + 薄包装 | 2–7 |
| 自动选模式 + 覆盖 | 2 |
| full / simple 流水线 | 2, 3, 5–7 |
| simple brainstorm 澄清意图 | 3 |
| 中等 spec 落盘 | 4 |
| simply 默认自动 / 争议再问 | 6 |
| 测试策略分流 | 5, 7 |
| 覆盖官方入口 | 2, 8 |
| cookbook sync | 8, 9 |
| 结构可验证 | 1, 7 |

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-30-dev-pipeline.md`. Two execution options:

**1. Subagent-Driven (recommended)** — 每个 Task 派生子代理，Task 间回顾  
**2. Inline Execution** — 本会话按 `executing-plans` 连续做，关键点停顿  

Which approach?
