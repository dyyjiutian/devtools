#!/usr/bin/env bash
# Contract tests for CI layer selection (no GitHub, no Docker).
set -euo pipefail

SCRIPT="$REPO_ROOT/tests/common/ci/select_layers.sh"

assert_file_exists "$SCRIPT" "select_layers.sh exists"
bash -n "$SCRIPT"

run_select() {
  SELECT_LAYERS_MESSAGE="$1" bash "$SCRIPT"
}

out="$(run_select "")"
assert_contains "$out" "l1=true" "empty message enables L1"
assert_contains "$out" "l2=true" "empty message enables L2"
assert_contains "$out" "l3=true" "empty message enables L3"

out="$(run_select "docs: tweak help text")"
assert_contains "$out" "l1=true" "unmarked commit enables L1"
assert_contains "$out" "l2=true" "unmarked commit enables L2"
assert_contains "$out" "l3=true" "unmarked commit enables L3"

out="$(run_select "fix: help text L1")"
assert_contains "$out" "l1=true" "L1 token enables L1"
assert_contains "$out" "l2=false" "L1-only skips L2"
assert_contains "$out" "l3=false" "L1-only skips L3"

out="$(run_select "[L2] docker fake regression")"
assert_contains "$out" "l1=false" "L2-only skips L1"
assert_contains "$out" "l2=true" "L2 token enables L2"
assert_contains "$out" "l3=false" "L2-only skips L3"

out="$(run_select "test: L1 L3")"
assert_contains "$out" "l1=true" "L1+L3 enables L1"
assert_contains "$out" "l2=false" "L1+L3 skips L2"
assert_contains "$out" "l3=true" "L1+L3 enables L3"

out="$(run_select "refactor LAYER helpers")"
assert_contains "$out" "l1=true" "LAYER does not count as L1"
assert_contains "$out" "l2=true" "LAYER does not count as L2"
assert_contains "$out" "l3=true" "LAYER does not count as L3"

echo "PASS: select_layers contract"
