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

printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_DIR/dnf"
chmod +x "$TMP_DIR/dnf"

output=$(PATH="$TMP_DIR:/usr/bin:/bin" SETUP_NO_MAIN=1 bash -c '
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
