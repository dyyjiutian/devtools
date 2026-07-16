#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1" expected="$2"
  [[ "$haystack" == *"$expected"* ]] || fail "expected '$expected' in output: $haystack"
}

printf '#!/bin/bash\nexit 0\n' > "$TMP_DIR/dnf"
chmod +x "$TMP_DIR/dnf"
printf '#!/bin/bash\nprintf "Linux\\n"\n' > "$TMP_DIR/uname"
printf '#!/bin/bash\nexit 0\n' > "$TMP_DIR/head"
printf '#!/bin/bash\nexit 0\n' > "$TMP_DIR/grep"
printf '#!/bin/bash\nprintf "%%s\\n" "${1%%/*}"\n' > "$TMP_DIR/dirname"
chmod +x "$TMP_DIR/uname" "$TMP_DIR/head" "$TMP_DIR/grep" "$TMP_DIR/dirname"

output=$(PATH="$TMP_DIR" SETUP_NO_MAIN=1 /bin/bash -c '
  setup="$1"
  set -- --dry-run
  source "$setup"
  DRY_RUN=true
  install_gh
' _ "$ROOT/vcs/git/setup.sh" 2>&1) ||
  fail "GitHub CLI dry-run failed: $output"

assert_contains "$output" "cli.github.com/packages/rpm/gh-cli.repo"
assert_contains "$output" "dnf install -y gh"

echo "PASS: Git setup GitHub CLI regression test"
