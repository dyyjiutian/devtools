#!/usr/bin/env bash
# Deprecated thin wrapper: GitHub CLI / git setup regression tests now live
# under Bazel as //tools/git:git_*_test (see tools/git/tests/git_suite.sh).
#
# Prefer:
#   bazel test //tools/git:git_linux_centos_test
#   bazel test //tools/git/...
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v bazel >/dev/null 2>&1; then
  exec bazel test //tools/git:git_linux_centos_test
fi

# Fallback when Bazel is unavailable: run the centos profile suite directly.
exec bash "$ROOT/testing/lib/run_module_test.sh" \
  --profile linux_centos \
  --suite tools/git/tests/git_suite.sh \
  --module-root tools/git/setup.sh
