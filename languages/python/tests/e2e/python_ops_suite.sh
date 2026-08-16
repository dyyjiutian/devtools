#!/usr/bin/env bash
# Real uv after setup.sh --skip-pyenv --skip-ai-packages (no pyenv compile).
set -euo pipefail

export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH:-}"

if ! command -v uv >/dev/null 2>&1; then
  echo "FAIL: uv not on PATH after setup" >&2
  exit 1
fi

ver="$(uv --version 2>&1)"
assert_contains "$ver" "uv" "uv --version runs"
pass "python ops: $ver ($DEVTOOLS_TEST_PROFILE)"
echo "PASS: python E2E ops ($DEVTOOLS_TEST_PROFILE)"
