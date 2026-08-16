#!/usr/bin/env bash
# Real rustc after setup.sh --skip-cargo-tools.
set -euo pipefail

if [[ -f "${HOME}/.cargo/env" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.cargo/env"
fi
export PATH="${HOME}/.cargo/bin:${PATH:-}"

if ! command -v rustc >/dev/null 2>&1; then
  echo "FAIL: rustc not on PATH after setup" >&2
  exit 1
fi

ver="$(rustc --version 2>&1)"
assert_contains "$ver" "rustc" "rustc --version runs"
pass "rust ops: $ver ($DEVTOOLS_TEST_PROFILE)"
echo "PASS: rust E2E ops ($DEVTOOLS_TEST_PROFILE)"
