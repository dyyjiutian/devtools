#!/usr/bin/env bash
# Contract tests for languages/java/setup.sh (no real SDKMAN install).
set -euo pipefail

SETUP="${REPO_ROOT}/languages/java/setup.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$SETUP" ]] || fail "missing $SETUP"
bash -n "$SETUP" || fail "java setup.sh failed bash -n"

help_out="$("$SETUP" --help)"
assert_contains "$help_out" "dry-run" "java --help mentions dry-run"
assert_contains "$help_out" "SDKMan" "java --help mentions SDKMan"

setup="$(cat "$SETUP")"
assert_contains "$setup" "source_sdkman_init" "java setup isolates sdkman-init.sh"
assert_contains "$setup" "run_sdk" "java setup wraps sdk commands for set -u"
assert_contains "$setup" "set +u" "java setup disables nounset around SDKMAN"
assert_contains "$setup" 'version" == "latest"' \
  "java setup omits the literal latest version that SDKMAN 5.x rejects"
assert_contains "$setup" '"$HOME/.bashrc" "$HOME/.zshrc"' \
  "java setup writes SDKMAN init to bashrc and zshrc"

ops="$(cat "${REPO_ROOT}/languages/java/tests/e2e/java_ops_suite.sh")"
assert_contains "$ops" "set +u" "java E2E sources sdkman-init.sh without nounset"

# Fresh sdkman-init.sh reads SDKMAN_CANDIDATES_API without a default.
SDKMAN_DIR="$HOME/.sdkman"
mkdir -p "$SDKMAN_DIR/bin"
cat >"$SDKMAN_DIR/bin/sdkman-init.sh" <<'EOF'
echo "api=${SDKMAN_CANDIDATES_API}"
EOF

if (
  set -u
  # shellcheck source=/dev/null
  source "$SDKMAN_DIR/bin/sdkman-init.sh"
) >/dev/null 2>&1; then
  fail "expected unbound SDKMAN_CANDIDATES_API under set -u"
fi

set +u
# shellcheck source=/dev/null
source "$SDKMAN_DIR/bin/sdkman-init.sh" >/dev/null
set -u

echo "PASS: java setup contract"
