#!/usr/bin/env bash
# Real JDK after setup.sh --skip-maven --skip-gradle.
set -euo pipefail

if [[ -s "${HOME}/.sdkman/bin/sdkman-init.sh" ]]; then
  set +u
  # shellcheck source=/dev/null
  source "${HOME}/.sdkman/bin/sdkman-init.sh"
  set -u
fi
export PATH="${HOME}/.sdkman/candidates/java/current/bin:${PATH:-}"

if ! command -v java >/dev/null 2>&1; then
  echo "FAIL: java not on PATH after setup" >&2
  exit 1
fi

ver="$(java -version 2>&1)"
assert_contains "$ver" "version" "java -version runs"
pass "java ops: $(printf '%s' "$ver" | head -1) ($DEVTOOLS_TEST_PROFILE)"
echo "PASS: java E2E ops ($DEVTOOLS_TEST_PROFILE)"
