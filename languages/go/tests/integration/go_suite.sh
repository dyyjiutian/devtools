#!/usr/bin/env bash
# Go installer CLI / dry-run suite (fake OS profile).
set -euo pipefail

SETUP_SH="$MODULE_ROOT/setup.sh"

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "dry-run" "go setup --help mentions dry-run"
  assert_contains "$out" "--skip-tools" "go setup --help mentions skip-tools"
  pass "go setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_unknown_flag() {
  local rc=0
  bash "$SETUP_SH" --not-a-real-flag >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "unknown flag should exit 1"
  pass "go setup unknown flag ($DEVTOOLS_TEST_PROFILE)"
}

test_dry_run() {
  local out
  out="$(bash "$SETUP_SH" --dry-run --skip-tools 2>&1)" || {
    echo "FAIL: go setup --dry-run failed: $out" >&2
    return 1
  }
  assert_contains "$out" "DRY-RUN" "go dry-run announces preview mode"
  pass "go setup --dry-run ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_unknown_flag
test_dry_run
echo "PASS: go suite complete ($DEVTOOLS_TEST_PROFILE)"
