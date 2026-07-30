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
  "dev/workspace/SKILL.md"
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
    */workspace/*) assert_heading "$f" "Isolation rules"; assert_heading "$f" "Rebase and drift check" ;;
    */exec/*) assert_heading "$f" "Preflight"; assert_heading "$f" "Process"; assert_heading "$f" "When to stop" ;;
    */simply/*) assert_heading "$f" "Default actions"; assert_heading "$f" "Ask first" ;;
    */test/*) assert_heading "$f" "Strategy"; assert_heading "$f" "Evidence" ;;
  esac
done

if [[ "$fail" -ne 0 ]]; then
  echo "skills_structure_test: FAILED" >&2
  exit 1
fi
echo "skills_structure_test: OK"
