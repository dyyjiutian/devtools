#!/usr/bin/env bash
# E2E runner: isolate HOME, run real module setup.sh, then the ops suite.
# Does not inject fake uname / package managers.
set -euo pipefail

if [[ "${DEVTOOLS_E2E_REQUIRE_DARWIN:-}" == "1" && "$(uname -s)" != "Darwin" ]]; then
  echo "run_e2e_test.sh: DEVTOOLS_E2E_REQUIRE_DARWIN=1 requires Darwin" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_COMMON_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

_is_repo_root() {
  local candidate="$1"
  [[ -f "$candidate/tests/common/lib/run_e2e_test.sh" &&
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
  echo "run_e2e_test.sh: cannot resolve repository root" >&2
  return 1
}

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
  if [[ -n "${TEST_SRCDIR:-}" && -e "${TEST_SRCDIR}/${TEST_WORKSPACE:-_main}/$p" ]]; then
    printf '%s\n' "${TEST_SRCDIR}/${TEST_WORKSPACE:-_main}/$p"
    return 0
  fi
  if [[ -e "$p" ]]; then
    printf '%s\n' "$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
    return 0
  fi
  echo "run_e2e_test.sh: path not found: $p" >&2
  return 1
}

SUITE_PATH=""
MODULE_ROOT=""
SETUP_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite) SUITE_PATH="${2:-}"; shift 2 ;;
    --module-root) MODULE_ROOT="${2:-}"; shift 2 ;;
    --setup-arg) SETUP_ARGS+=("${2:-}"); shift 2 ;;
    -h|--help)
      echo "Usage: run_e2e_test.sh --suite PATH --module-root PATH [--setup-arg ARG]..."
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$SUITE_PATH" || -z "$MODULE_ROOT" ]]; then
  echo "run_e2e_test.sh: --suite and --module-root are required" >&2
  exit 1
fi

REPO_ROOT="$(resolve_repo_root)"
export REPO_ROOT
TEST_COMMON_LIB="$REPO_ROOT/tests/common/lib"
export TEST_COMMON_LIB

SUITE_PATH="$(resolve_path "$SUITE_PATH")"
MODULE_ROOT="$(resolve_path "$MODULE_ROOT")"
if [[ -f "$MODULE_ROOT" ]]; then
  MODULE_ROOT="$(cd "$(dirname "$MODULE_ROOT")" && pwd)"
else
  MODULE_ROOT="$(cd "$MODULE_ROOT" && pwd)"
fi
export MODULE_ROOT

TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/devtools-e2e-home.XXXXXX")"
cleanup_tmp_home() {
  # Overlayfs (Docker) can fail `rm -rf` on npm caches with "Directory not empty".
  rm -rf "$TMP_HOME" 2>/dev/null || true
}
trap cleanup_tmp_home EXIT
export HOME="$TMP_HOME"
mkdir -p "$HOME/.local/bin"
# Apple Silicon / GitHub macos-26 Homebrew lives in /opt/homebrew, not /usr/local.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
export DEVTOOLS_CACHE_DIR="${DEVTOOLS_CACHE_DIR:-$REPO_ROOT/cache}"
export NVIM_SETUP_STRICT="${NVIM_SETUP_STRICT:-1}"

# shellcheck source=tests/common/lib/assert.sh
source "$TEST_COMMON_LIB/assert.sh"

SETUP_SH="$MODULE_ROOT/setup.sh"
if [[ ! -f "$SETUP_SH" ]]; then
  echo "run_e2e_test.sh: missing $SETUP_SH" >&2
  exit 1
fi

echo "==> e2e HOME=$HOME module=$MODULE_ROOT"
if [[ ${#SETUP_ARGS[@]} -gt 0 ]]; then
  echo "==> running $SETUP_SH ${SETUP_ARGS[*]}"
else
  echo "==> running $SETUP_SH"
fi
if [[ ${#SETUP_ARGS[@]} -gt 0 ]]; then
  bash "$SETUP_SH" "${SETUP_ARGS[@]}"
else
  bash "$SETUP_SH"
fi

hash -r 2>/dev/null || true
echo "==> running suite $SUITE_PATH"
# shellcheck disable=SC1090
source "$SUITE_PATH"
