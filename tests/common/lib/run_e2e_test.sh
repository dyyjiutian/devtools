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

HOST_HOME="${HOME}"
# Keep the machine rustup/cargo homes. Isolated HOME otherwise makes rustup
# write shims into the temp cargo dir that cannot find the host toolchain.
if [[ -z "${CARGO_HOME:-}" && -d "${HOST_HOME}/.cargo" ]]; then
  export CARGO_HOME="${HOST_HOME}/.cargo"
fi
if [[ -z "${RUSTUP_HOME:-}" && -d "${HOST_HOME}/.rustup" ]]; then
  export RUSTUP_HOME="${HOST_HOME}/.rustup"
fi
TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/devtools-e2e-home.XXXXXX")"
cleanup_tmp_home() {
  # Overlayfs (Docker) can fail `rm -rf` on npm caches with "Directory not empty".
  rm -rf "$TMP_HOME" 2>/dev/null || true
}
trap cleanup_tmp_home EXIT
export HOME="$TMP_HOME"
mkdir -p "$HOME/.local/bin"
# Point the isolated HOME at the machine toolchain so setup.sh's
# $HOME/.cargo/env and rustc shims resolve. rm -rf on the temp dir
# removes the symlink, not the host cargo/rustup trees.
if [[ -n "${CARGO_HOME:-}" && -d "$CARGO_HOME" && "$CARGO_HOME" != "$HOME/.cargo" ]]; then
  ln -sfn "$CARGO_HOME" "$HOME/.cargo"
fi
if [[ -n "${RUSTUP_HOME:-}" && -d "$RUSTUP_HOME" && "$RUSTUP_HOME" != "$HOME/.rustup" ]]; then
  ln -sfn "$RUSTUP_HOME" "$HOME/.rustup"
fi
# Some runner images (GitHub macos-26) ship rustup with RUSTUP_HOME but no
# $HOST_HOME/.cargo, so CARGO_HOME stays unset and the cargo shim dir never
# lands on PATH. Ask rustup for the real toolchain bin and expose it as the
# isolated cargo home so rustc/cargo resolve after setup.sh's "rustup already
# installed" path (which only updates the machine toolchain). Include the
# Homebrew dirs in the lookup: bazel sanitizes the test PATH and this runs
# before the PATH export below. Link individual tools (not the whole bin dir)
# so a later `rustup update` writing shims into CARGO_HOME/bin cannot overwrite
# the real toolchain binaries.
if [[ -z "${CARGO_HOME:-}" && ! -e "$HOME/.cargo" ]]; then
  rustc_bin="$(PATH="${PATH:-}:/opt/homebrew/bin:/usr/local/bin:${HOST_HOME}/.local/bin" \
    rustup which --toolchain stable rustc 2>/dev/null || true)"
  if [[ -n "$rustc_bin" && -x "$rustc_bin" ]]; then
    toolchain_bin="$(dirname "$rustc_bin")"
    mkdir -p "$HOME/.cargo/bin"
    ln -sfn "$rustc_bin" "$HOME/.cargo/bin/rustc"
    if [[ -x "${toolchain_bin}/cargo" ]]; then
      ln -sfn "${toolchain_bin}/cargo" "$HOME/.cargo/bin/cargo"
    fi
    export CARGO_HOME="$HOME/.cargo"
  fi
fi

path_prefix="$HOME/.local/bin:$HOME/.cargo/bin"
if [[ -n "${CARGO_HOME:-}" ]]; then
  path_prefix="${path_prefix}:${CARGO_HOME}/bin"
fi
if [[ -n "$HOST_HOME" && "$HOST_HOME" != "$HOME" ]]; then
  path_prefix="${path_prefix}:${HOST_HOME}/.cargo/bin:${HOST_HOME}/.local/bin"
fi
# Apple Silicon / GitHub macos-26 Homebrew lives in /opt/homebrew, not /usr/local.
export PATH="${path_prefix}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
if [[ "$(uname -s)" == Darwin ]]; then
  # Isolated HOME breaks Homebrew bootsnap (sorbet-runtime LoadError).
  export HOMEBREW_NO_AUTO_UPDATE=1
  export HOMEBREW_NO_ANALYTICS=1
  export HOMEBREW_BOOTSNAP=0
  export HOMEBREW_NO_BOOTSNAP=1
  if [[ -d "${HOST_HOME}/Library/Caches/Homebrew" ]]; then
    export HOMEBREW_CACHE="${HOST_HOME}/Library/Caches/Homebrew"
  fi
  # Serialize brew across --jobs=2 so Cellar locks cannot fail sibling tests.
  real_brew="$(command -v brew 2>/dev/null || true)"
  if [[ -n "$real_brew" && "$real_brew" != "$HOME/.local/bin/brew" ]]; then
    cat > "$HOME/.local/bin/brew" <<EOF
#!/usr/bin/env bash
set -euo pipefail
lockdir="\${TMPDIR:-/tmp}/devtools-e2e-brew.lock"
while ! mkdir "\$lockdir" 2>/dev/null; do
  sleep 1
done
trap 'rmdir "\$lockdir" 2>/dev/null || true' EXIT
"$real_brew" "\$@"
EOF
    chmod +x "$HOME/.local/bin/brew"
  fi
fi
export DEVTOOLS_CACHE_DIR="${DEVTOOLS_CACHE_DIR:-$REPO_ROOT/cache}"
export NVIM_SETUP_STRICT="${NVIM_SETUP_STRICT:-1}"
# Headless Lazy/Mason/TSUpdate progress exceeds Bazel's 1MiB UI cap and hides
# the real error. Ops suite does not need compiled parsers.
export NVIM_SETUP_QUIET="${NVIM_SETUP_QUIET:-1}"
export NVIM_SETUP_SKIP_TREESITTER="${NVIM_SETUP_SKIP_TREESITTER:-1}"
export NVIM_SETUP_SKIP_MASON="${NVIM_SETUP_SKIP_MASON:-1}"

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
