#!/usr/bin/env bash
# Real Go toolchain after setup.sh --skip-tools.
set -euo pipefail

export PATH="/usr/local/go/bin:${HOME}/go/bin:${PATH:-}"

if ! command -v go >/dev/null 2>&1; then
  echo "FAIL: go not on PATH after setup" >&2
  exit 1
fi

ver="$(go version 2>&1)"
assert_contains "$ver" "go version" "go version runs"
pass "go ops: $ver ($DEVTOOLS_TEST_PROFILE)"
echo "PASS: go E2E ops ($DEVTOOLS_TEST_PROFILE)"
