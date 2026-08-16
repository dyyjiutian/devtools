#!/usr/bin/env bash
# Python installer CLI / dry-run suite (fake OS profile).
set -euo pipefail

SETUP_SH="$MODULE_ROOT/setup.sh"

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "dry-run" "python setup --help mentions dry-run"
  assert_contains "$out" "--skip-pyenv" "python setup --help mentions skip-pyenv"
  assert_contains "$out" "--skip-uv" "python setup --help mentions skip-uv"
  pass "python setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_unknown_flag() {
  local rc=0
  bash "$SETUP_SH" --not-a-real-flag >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "unknown flag should exit 1"
  pass "python setup unknown flag ($DEVTOOLS_TEST_PROFILE)"
}

test_dry_run() {
  local out
  out="$(bash "$SETUP_SH" --dry-run --skip-ai-packages 2>&1)" || {
    echo "FAIL: python setup --dry-run failed: $out" >&2
    return 1
  }
  assert_contains "$out" "DRY-RUN" "python dry-run announces preview mode"
  pass "python setup --dry-run ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_unknown_flag
test_dry_run
echo "PASS: python suite complete ($DEVTOOLS_TEST_PROFILE)"
