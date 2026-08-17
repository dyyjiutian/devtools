#!/usr/bin/env bash
# Real rustc after setup.sh --skip-cargo-tools.
set -euo pipefail

cargo_home="${CARGO_HOME:-${HOME}/.cargo}"
if [[ -f "${cargo_home}/env" ]]; then
  set +u
  # shellcheck source=/dev/null
  source "${cargo_home}/env"
  set -u
elif [[ -f "${HOME}/.cargo/env" ]]; then
  set +u
  # shellcheck source=/dev/null
  source "${HOME}/.cargo/env"
  set -u
fi
export PATH="${cargo_home}/bin:${HOME}/.cargo/bin:${PATH:-}"

if ! command -v rustc >/dev/null 2>&1; then
  echo "FAIL: rustc not on PATH after setup" >&2
  echo "HOME=$HOME CARGO_HOME=${CARGO_HOME:-} RUSTUP_HOME=${RUSTUP_HOME:-}" >&2
  echo "PATH=$PATH" >&2
  ls -la "${cargo_home}/bin" >&2 || true
  exit 1
fi

ver="$(rustc --version 2>&1)"
assert_contains "$ver" "rustc" "rustc --version runs"
pass "rust ops: $ver ($DEVTOOLS_TEST_PROFILE)"
echo "PASS: rust E2E ops ($DEVTOOLS_TEST_PROFILE)"
