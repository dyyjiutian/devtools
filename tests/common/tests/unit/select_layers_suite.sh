#!/usr/bin/env bash
# Contract tests for CI layer selection (no GitHub, no Docker).
set -euo pipefail

SCRIPT="$REPO_ROOT/tests/common/ci/select_layers.sh"

assert_file_exists "$SCRIPT" "select_layers.sh exists"
bash -n "$SCRIPT"

run_select() {
  SELECT_LAYERS_MESSAGE="$1" bash "$SCRIPT"
}

assert_layers() {
  local out="$1" want_l1="$2" want_l2="$3" want_l3="$4" label="$5"
  assert_contains "$out" "l1=${want_l1}" "${label}: l1=${want_l1}"
  assert_contains "$out" "l2=${want_l2}" "${label}: l2=${want_l2}"
  assert_contains "$out" "l3=${want_l3}" "${label}: l3=${want_l3}"
  assert_contains "$out" "ut=${want_l1}" "${label}: ut=${want_l1}"
  assert_contains "$out" "it=${want_l2}" "${label}: it=${want_l2}"
  assert_contains "$out" "e2e=${want_l3}" "${label}: e2e=${want_l3}"
}

out="$(run_select "")"
assert_layers "$out" true true true "empty message"

out="$(run_select "docs: tweak help text")"
assert_layers "$out" true true true "unmarked commit"

out="$(run_select "fix: help text L1")"
assert_layers "$out" true true true "bare L1 is not a selector"

out="$(run_select "[L2] docker fake regression")"
assert_layers "$out" true true true "legacy [L2] is not a selector"

out="$(run_select "feat: add L1/L2/L3 layers")"
assert_layers "$out" true true true "prose L1/L2/L3 is not a selector"

out="$(run_select "feat: hosts [test#L1]")"
assert_layers "$out" true false false "[test#L1] runs only L1"

out="$(run_select "feat: docker [test#L1,L2]")"
assert_layers "$out" true true false "[test#L1,L2] runs L1 and L2"

out="$(run_select "feat: spaces [test#L1, L2]")"
assert_layers "$out" true true false "[test#L1, L2] allows spaces"

out="$(run_select "feat: all [test#L1,L2,L3]")"
assert_layers "$out" true true true "[test#L1,L2,L3] runs all layers"

out="$(run_select "feat: skip ci [test#skip]")"
assert_layers "$out" false false false "[test#skip] skips all layers"

out="$(run_select "feat: skip wins [test#L1] [test#skip]")"
assert_layers "$out" false false false "[test#skip] wins over other tags"

out="$(run_select "feat: skip mixed [test#L1,skip]")"
assert_layers "$out" false false false "[test#L1,skip] skips all layers"

out="$(run_select "feat: aliases [test#ut]")"
assert_layers "$out" true false false "[test#ut] is L1"

out="$(run_select "feat: aliases [test#it]")"
assert_layers "$out" false true false "[test#it] is L2"

out="$(run_select "feat: aliases [test#e2e]")"
assert_layers "$out" false false true "[test#e2e] is L3"

out="$(run_select "feat: mixed aliases [test#ut,e2e]")"
assert_layers "$out" true false true "[test#ut,e2e] runs L1 and L3"

out="$(run_select "feat: mixed names [test#L1,it]")"
assert_layers "$out" true true false "[test#L1,it] mixes canonical and alias"

out="$(run_select "feat: case [TEST#Ut,E2E]")"
assert_layers "$out" true false true "selector is case-insensitive"

out="$(run_select "feat: union [test#L1] [test#e2e]")"
assert_layers "$out" true false true "multiple tags are unioned"

out="$(run_select "feat: empty [test#]")"
assert_layers "$out" false false false "empty [test#] skips all layers"

out="$(run_select "feat: unknown [test#foo]")"
assert_layers "$out" false false false "unknown tokens skip all layers"

echo "PASS: select_layers contract"
