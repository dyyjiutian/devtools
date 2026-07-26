#!/usr/bin/env bash
# Bazel/host runner: isolate HOME, apply OS profile, execute a module suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTING_LIB="$SCRIPT_DIR"
TESTING_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

_is_repo_root() {
  local candidate="$1"
  # Prefer testing/lib marker; do not require unrelated modules (Bazel runfiles are sparse).
  [[ -f "$candidate/testing/lib/run_module_test.sh" && -f "$candidate/testing/lib/profile.sh" ]]
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

  # Non-Bazel: testing/lib -> repo root
  candidate="$(cd "$TESTING_ROOT/.." && pwd)"
  if _is_repo_root "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  # Script-adjacent fallback (runfiles: .../testing/lib/run_module_test.sh)
  candidate="$(cd "$SCRIPT_DIR/../.." && pwd)"
  if _is_repo_root "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  echo "run_module_test.sh: cannot resolve repository root" >&2
  return 1
}

usage() {
  cat <<'EOF'
Usage: run_module_test.sh --profile PROFILE --suite REL_OR_ABS --module-root REL_OR_ABS

Environment:
  DEVTOOLS_TEST_PROFILE   Optional default profile
EOF
}

PROFILE="${DEVTOOLS_TEST_PROFILE:-}"
SUITE_PATH=""
MODULE_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --suite)
      SUITE_PATH="${2:-}"
      shift 2
      ;;
    --module-root)
      MODULE_ROOT="${2:-}"
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

if [[ -z "$PROFILE" || -z "$SUITE_PATH" || -z "$MODULE_ROOT" ]]; then
  echo "run_module_test.sh: --profile, --suite, and --module-root are required" >&2
  usage >&2
  exit 1
fi

REPO_ROOT="$(resolve_repo_root)"
export REPO_ROOT
TESTING_LIB="$REPO_ROOT/testing/lib"
TESTING_ROOT="$REPO_ROOT/testing"
export TESTING_LIB TESTING_ROOT

resolve_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    printf '%s\n' "$p"
    return 0
  fi
  if [[ -e "$REPO_ROOT/$p" ]]; then
    printf '%s\n' "$REPO_ROOT/$p"
    return 0
  fi
  # Bazel rootpath is relative to execroot / runfiles workspace
  if [[ -n "${TEST_SRCDIR:-}" && -e "${TEST_SRCDIR}/${TEST_WORKSPACE:-_main}/$p" ]]; then
    printf '%s\n' "${TEST_SRCDIR}/${TEST_WORKSPACE:-_main}/$p"
    return 0
  fi
  if [[ -e "$p" ]]; then
    # shellcheck disable=SC2086
    printf '%s\n' "$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
    return 0
  fi
  echo "run_module_test.sh: path not found: $p" >&2
  return 1
}

SUITE_PATH="$(resolve_path "$SUITE_PATH")"
MODULE_ROOT="$(resolve_path "$MODULE_ROOT")"
if [[ -f "$MODULE_ROOT" ]]; then
  MODULE_ROOT="$(cd "$(dirname "$MODULE_ROOT")" && pwd)"
else
  MODULE_ROOT="$(cd "$MODULE_ROOT" && pwd)"
fi

export MODULE_ROOT
export DEVTOOLS_TEST_PROFILE="$PROFILE"

TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/devtools-test-home.XXXXXX")"
FAKE_BIN="$(mktemp -d "${TMPDIR:-/tmp}/devtools-test-fakes.XXXXXX")"
CACHE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devtools-test-cache.XXXXXX")"
trap 'rm -rf "$TMP_HOME" "$FAKE_BIN" "$CACHE_DIR"' EXIT

export HOME="$TMP_HOME"
export DEVTOOLS_CACHE_DIR="$CACHE_DIR"
export FAKE_BIN
mkdir -p "$HOME" "$CACHE_DIR/binaries"

# shellcheck source=testing/lib/profile.sh
source "$TESTING_LIB/profile.sh"
# shellcheck source=testing/lib/assert.sh
source "$TESTING_LIB/assert.sh"

# Sets PATH to $FAKE_BIN only (linked host tools + profile fakes).
setup_os_profile "$PROFILE" "$FAKE_BIN"

echo "==> profile=$PROFILE module=$MODULE_ROOT suite=$SUITE_PATH"
echo "==> HOME=$HOME"

# shellcheck disable=SC1090
source "$SUITE_PATH"
