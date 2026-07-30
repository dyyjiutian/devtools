#!/usr/bin/env bash
# Bazel/host runner for hermetic shell unit suites.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_COMMON_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

_is_repo_root() {
  local candidate="$1"
  [[ -f "$candidate/tests/common/lib/run_unit_test.sh" &&
     -f "$candidate/tests/common/lib/assert.sh" ]]
}

resolve_repo_root() {
  local candidate
  if [[ -n "${TEST_SRCDIR:-}" ]]; then
    for candidate in \
      "${TEST_SRCDIR}/${TEST_WORKSPACE:-_main}" \
      "${TEST_SRCDIR}/_main" \
      "${TEST_SRCDIR}/devtools"; do
      if _is_repo_root "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  fi

  candidate="$(cd "$TEST_COMMON_ROOT/../.." && pwd)"
  if _is_repo_root "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  if _is_repo_root "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  echo "run_unit_test.sh: cannot resolve repository root" >&2
  return 1
}

usage() {
  echo "Usage: run_unit_test.sh --suite REL_OR_ABS"
}

SUITE_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite)
      SUITE_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ -n "$SUITE_PATH" ]] || {
  echo "run_unit_test.sh: --suite is required" >&2
  usage >&2
  exit 1
}

REPO_ROOT="$(resolve_repo_root)"
export REPO_ROOT
TEST_COMMON_LIB="$REPO_ROOT/tests/common/lib"
export TEST_COMMON_LIB

if [[ "$SUITE_PATH" != /* ]]; then
  if [[ -e "$REPO_ROOT/$SUITE_PATH" ]]; then
    SUITE_PATH="$REPO_ROOT/$SUITE_PATH"
  elif [[ -e "$SUITE_PATH" ]]; then
    SUITE_PATH="$(cd "$(dirname "$SUITE_PATH")" && pwd)/$(basename "$SUITE_PATH")"
  else
    echo "run_unit_test.sh: suite not found: $SUITE_PATH" >&2
    exit 1
  fi
fi

TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/devtools-unit-home.XXXXXX")"
TMP_CACHE="$(mktemp -d "${TMPDIR:-/tmp}/devtools-unit-cache.XXXXXX")"
trap 'rm -rf "$TMP_HOME" "$TMP_CACHE"' EXIT

export HOME="$TMP_HOME"
export DEVTOOLS_CACHE_DIR="$TMP_CACHE"
export DEVTOOLS_TEST_ARCH="x86_64"
export DEVTOOLS_ARCH="x86_64"

# shellcheck source=tests/common/lib/assert.sh
source "$TEST_COMMON_LIB/assert.sh"
# shellcheck disable=SC1090
source "$SUITE_PATH"
