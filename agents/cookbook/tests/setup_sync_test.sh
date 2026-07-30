#!/usr/bin/env bash
# 校验 agents/cookbook/setup.sh 的多 Agent target 同步（临时目录，不改本机）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETUP="$ROOT/setup.sh"
fail=0

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CURSOR_SKILLS="$TMP_DIR/cursor/skills"
CLAUDE_SKILLS="$TMP_DIR/claude/skills"
CODEX_SKILLS="$TMP_DIR/agents/skills"
CURSOR_RULES="$TMP_DIR/cursor/rules"

export CURSOR_SKILLS_DIR="$CURSOR_SKILLS"
export CLAUDE_SKILLS_DIR="$CLAUDE_SKILLS"
export CODEX_SKILLS_DIR="$CODEX_SKILLS"
export CURSOR_RULES_DIR="$CURSOR_RULES"

pass() { echo "PASS: $*"; }
fail_msg() { echo "FAIL: $*" >&2; fail=1; }

assert_link() {
  local dest="$1" src="$2"
  if [[ ! -L "$dest" ]]; then
    fail_msg "expected symlink: $dest"
    return
  fi
  local resolved
  resolved="$(readlink "$dest")"
  if [[ "$resolved" != "$src" ]]; then
    fail_msg "symlink target mismatch: $dest -> $resolved (want $src)"
  fi
}

assert_missing() {
  local dest="$1"
  if [[ -e "$dest" || -L "$dest" ]]; then
    fail_msg "expected missing: $dest"
  fi
}

# 取一个已知 skill 名与源目录
SAMPLE_NAME=""
SAMPLE_SRC=""
while IFS=$'\t' read -r name src; do
  SAMPLE_NAME="$name"
  SAMPLE_SRC="$src"
  break
done < <(
  # 复用 setup 的发现逻辑：找第一个 SKILL.md
  find "$ROOT/skills" -type f -name 'SKILL.md' -print0 | sort -z | while IFS= read -r -d '' skill_md; do
    skill_dir="$(cd "$(dirname "$skill_md")" && pwd)"
    name="$(sed -n 's/^name:[[:space:]]*//p' "$skill_md" | head -n 1 | tr -d '\r')"
    [[ -n "$name" ]] || name="$(basename "$skill_dir")"
    printf '%s\t%s\n' "$name" "$skill_dir"
  done
)

if [[ -z "$SAMPLE_NAME" || -z "$SAMPLE_SRC" ]]; then
  echo "FAIL: no SKILL.md found under $ROOT/skills" >&2
  exit 1
fi

RULE_SAMPLE=""
if [[ -d "$ROOT/rules" ]]; then
  RULE_SAMPLE="$(find "$ROOT/rules" -type f -name '*.mdc' | sort | head -n 1 || true)"
fi

# help 应列出 codex
help_out="$TMP_DIR/help.out"
bash "$SETUP" --help >"$help_out" 2>&1 || true
if grep -q 'codex' "$help_out"; then
  pass "help mentions codex"
else
  fail_msg "help should mention codex target"
fi

# 未知 target 应失败
if bash "$SETUP" sync --target nope >"$TMP_DIR/bad.out" 2>&1; then
  fail_msg "unknown --target should fail"
else
  pass "unknown --target fails"
fi

# --target codex：只写 Codex skills，不写 Cursor rules
rm -rf "$CURSOR_SKILLS" "$CLAUDE_SKILLS" "$CODEX_SKILLS" "$CURSOR_RULES"
bash "$SETUP" sync --target codex >"$TMP_DIR/codex.out" 2>&1 || {
  fail_msg "sync --target codex failed: $(cat "$TMP_DIR/codex.out")"
}
assert_link "$CODEX_SKILLS/$SAMPLE_NAME" "$SAMPLE_SRC"
assert_missing "$CURSOR_SKILLS/$SAMPLE_NAME"
assert_missing "$CLAUDE_SKILLS/$SAMPLE_NAME"
if [[ -n "$RULE_SAMPLE" ]]; then
  assert_missing "$CURSOR_RULES/$(basename "$RULE_SAMPLE")"
fi
if [[ "$fail" -eq 0 ]]; then
  pass "sync --target codex"
fi

# --target all：三端 skills + Cursor rules
rm -rf "$CURSOR_SKILLS" "$CLAUDE_SKILLS" "$CODEX_SKILLS" "$CURSOR_RULES"
bash "$SETUP" sync --target all >"$TMP_DIR/all.out" 2>&1 || {
  fail_msg "sync --target all failed: $(cat "$TMP_DIR/all.out")"
}
assert_link "$CURSOR_SKILLS/$SAMPLE_NAME" "$SAMPLE_SRC"
assert_link "$CLAUDE_SKILLS/$SAMPLE_NAME" "$SAMPLE_SRC"
assert_link "$CODEX_SKILLS/$SAMPLE_NAME" "$SAMPLE_SRC"
if [[ -n "$RULE_SAMPLE" ]]; then
  assert_link "$CURSOR_RULES/$(basename "$RULE_SAMPLE")" "$RULE_SAMPLE"
fi
if [[ "$fail" -eq 0 ]]; then
  pass "sync --target all"
fi

# 幂等：再跑一次仍成功
bash "$SETUP" sync --target all >"$TMP_DIR/all2.out" 2>&1 || {
  fail_msg "idempotent sync --target all failed: $(cat "$TMP_DIR/all2.out")"
}
assert_link "$CODEX_SKILLS/$SAMPLE_NAME" "$SAMPLE_SRC"
if [[ "$fail" -eq 0 ]]; then
  pass "sync --target all idempotent"
fi

# unlink --target all
bash "$SETUP" unlink --target all >"$TMP_DIR/unlink.out" 2>&1 || {
  fail_msg "unlink --target all failed: $(cat "$TMP_DIR/unlink.out")"
}
assert_missing "$CURSOR_SKILLS/$SAMPLE_NAME"
assert_missing "$CLAUDE_SKILLS/$SAMPLE_NAME"
assert_missing "$CODEX_SKILLS/$SAMPLE_NAME"
if [[ -n "$RULE_SAMPLE" ]]; then
  assert_missing "$CURSOR_RULES/$(basename "$RULE_SAMPLE")"
fi
if [[ "$fail" -eq 0 ]]; then
  pass "unlink --target all"
fi

# dry-run 不创建文件
rm -rf "$CURSOR_SKILLS" "$CLAUDE_SKILLS" "$CODEX_SKILLS" "$CURSOR_RULES"
bash "$SETUP" sync --target all --dry-run >"$TMP_DIR/dry.out" 2>&1 || {
  fail_msg "sync --dry-run failed: $(cat "$TMP_DIR/dry.out")"
}
assert_missing "$CODEX_SKILLS/$SAMPLE_NAME"
if grep -q '\[dry-run\]' "$TMP_DIR/dry.out"; then
  pass "dry-run preview"
else
  fail_msg "dry-run output missing [dry-run] markers"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "setup_sync_test: FAILED" >&2
  exit 1
fi
echo "setup_sync_test: OK"
