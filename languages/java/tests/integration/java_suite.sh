#!/usr/bin/env bash
# Java installer CLI / dry-run suite (fake OS profile).
set -euo pipefail

SETUP_SH="$MODULE_ROOT/setup.sh"

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "dry-run" "java setup --help mentions dry-run"
  assert_contains "$out" "--skip-maven" "java setup --help mentions skip-maven"
  assert_contains "$out" "--skip-gradle" "java setup --help mentions skip-gradle"
  pass "java setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_unknown_flag() {
  local rc=0
  bash "$SETUP_SH" --not-a-real-flag >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "unknown flag should exit 1"
  pass "java setup unknown flag ($DEVTOOLS_TEST_PROFILE)"
}

test_dry_run() {
  local out
  out="$(bash "$SETUP_SH" --dry-run --skip-maven --skip-gradle 2>&1)" || {
    echo "FAIL: java setup --dry-run failed: $out" >&2
    return 1
  }
  assert_contains "$out" "DRY-RUN" "java dry-run announces preview mode"
  pass "java setup --dry-run ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_unknown_flag
test_dry_run
echo "PASS: java suite complete ($DEVTOOLS_TEST_PROFILE)"
