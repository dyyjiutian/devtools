#!/usr/bin/env bash
# L2 runner: build/run an OS image and execute the same module suite inside it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_COMMON_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

_is_repo_root() {
  local candidate="$1"
  [[ -f "$candidate/tests/common/lib/run_module_test.sh" &&
     -f "$candidate/tests/common/lib/profile.sh" ]]
}

resolve_repo_root() {
  local candidate
  if [[ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]] && _is_repo_root "$BUILD_WORKSPACE_DIRECTORY"; then
    printf '%s\n' "$BUILD_WORKSPACE_DIRECTORY"
    return 0
  fi
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
  echo "run_in_docker.sh: cannot resolve repository root" >&2
  return 1
}

# Bazel runfiles often symlink into the real workspace. Docker bind-mounts must
# use that real tree so in-container paths resolve (symlinks to host abs paths
# are invisible inside the container unless the target tree is mounted).
resolve_source_root() {
  local runfiles_root="$1"
  local marker="$runfiles_root/tests/common/lib/run_module_test.sh"
  local real candidate

  if [[ -n "${BUILD_WORKSPACE_DIRECTORY:-}" ]] && _is_repo_root "$BUILD_WORKSPACE_DIRECTORY"; then
    printf '%s\n' "$BUILD_WORKSPACE_DIRECTORY"
    return 0
  fi

  if [[ -L "$marker" || -f "$marker" ]]; then
    real="$(readlink -f "$marker" 2>/dev/null || true)"
    if [[ -n "$real" ]]; then
      candidate="$(cd "$(dirname "$real")/../../.." && pwd)"
      if _is_repo_root "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  fi

  printf '%s\n' "$runfiles_root"
}

_user_in_docker_group() {
  local user="${USER:-$(id -un 2>/dev/null || true)}"
  local members
  members="$(getent group docker 2>/dev/null | cut -d: -f4 || true)"
  [[ -n "$user" && -n "$members" ]] || return 1
  [[ ",${members}," == *",${user},"* ]]
}

ensure_docker() {
  local docker_bin="" err quoted
  if command -v docker >/dev/null 2>&1; then
    docker_bin="$(command -v docker)"
  elif [[ -x /usr/bin/docker ]]; then
    docker_bin=/usr/bin/docker
  elif [[ -x /bin/docker ]]; then
    docker_bin=/bin/docker
  fi

  if [[ -z "$docker_bin" ]]; then
    echo "run_in_docker.sh: docker not found on PATH=$PATH" >&2
    return 1
  fi
  export PATH="$(dirname "$docker_bin"):/usr/bin:/bin:${PATH:-}"

  # Prefer the standard socket when unset (Bazel test env is often sparse).
  if [[ -z "${DOCKER_HOST:-}" && -S /var/run/docker.sock ]]; then
    export DOCKER_HOST="unix:///var/run/docker.sock"
  fi

  if docker info >/dev/null 2>&1; then
    return 0
  fi

  # Bazel test processes often drop supplementary groups (e.g. docker).
  # Re-exec under `sg docker` when the user is a docker-group member.
  if [[ "${DEVTOOLS_DOCKER_SG:-}" != "1" ]] && command -v sg >/dev/null 2>&1 && _user_in_docker_group; then
    quoted="$(printf '%q ' "$0" "$@")"
    export DEVTOOLS_DOCKER_SG=1
    exec sg docker -c "export DEVTOOLS_DOCKER_SG=1; export DOCKER_HOST=$(printf '%q' "$DOCKER_HOST"); export PATH=$(printf '%q' "$PATH"); export TEST_SRCDIR=$(printf '%q' "${TEST_SRCDIR:-}"); export TEST_WORKSPACE=$(printf '%q' "${TEST_WORKSPACE:-}"); export BUILD_WORKSPACE_DIRECTORY=$(printf '%q' "${BUILD_WORKSPACE_DIRECTORY:-}"); ${quoted}"
  fi

  err="$(docker info 2>&1 || true)"
  echo "run_in_docker.sh: docker daemon not available" >&2
  echo "  docker=$docker_bin" >&2
  echo "  DOCKER_HOST=${DOCKER_HOST:-<unset>}" >&2
  echo "  id=$(id 2>/dev/null || true)" >&2
  echo "  sock=$(ls -l /var/run/docker.sock 2>&1 || true)" >&2
  echo "  docker info: $err" >&2
  return 1
}

ORIGINAL_ARGS=("$@")
PROFILE=""
SUITE_PATH=""
MODULE_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --suite) SUITE_PATH="${2:-}"; shift 2 ;;
    --module-root) MODULE_ROOT="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: run_in_docker.sh --profile PROFILE --suite PATH --module-root PATH"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PROFILE" || -z "$SUITE_PATH" || -z "$MODULE_ROOT" ]]; then
  echo "run_in_docker.sh: --profile, --suite, and --module-root are required" >&2
  exit 1
fi

case "$PROFILE" in
  linux_ubuntu) DOCKERFILE="Dockerfile.ubuntu"; IMAGE_TAG="devtools-test:ubuntu" ;;
  linux_centos) DOCKERFILE="Dockerfile.centos"; IMAGE_TAG="devtools-test:centos" ;;
  linux_alinux3) DOCKERFILE="Dockerfile.alinux3"; IMAGE_TAG="devtools-test:alinux3" ;;
  linux_alinux4) DOCKERFILE="Dockerfile.alinux4"; IMAGE_TAG="devtools-test:alinux4" ;;
  *)
    echo "run_in_docker.sh: profile '$PROFILE' has no Docker image (macOS is L1-only)" >&2
    exit 1
    ;;
esac

# Pass original argv so ensure_docker can re-exec under `sg docker` if needed.
ensure_docker "${ORIGINAL_ARGS[@]}"

RUNFILES_ROOT="$(resolve_repo_root)"
SOURCE_ROOT="$(resolve_source_root "$RUNFILES_ROOT")"

# rootpath args are workspace-relative; normalize before bind-mount execution.
rel_suite="$SUITE_PATH"
rel_module="$MODULE_ROOT"
[[ "$rel_suite" = /* ]] && rel_suite="${rel_suite#"$RUNFILES_ROOT"/}"
[[ "$rel_module" = /* ]] && rel_module="${rel_module#"$RUNFILES_ROOT"/}"
[[ "$rel_suite" = /* ]] && rel_suite="${rel_suite#"$SOURCE_ROOT"/}"
[[ "$rel_module" = /* ]] && rel_module="${rel_module#"$SOURCE_ROOT"/}"

DOCKER_DIR="$SOURCE_ROOT/tests/common/docker"
if [[ ! -f "$DOCKER_DIR/$DOCKERFILE" ]]; then
  DOCKER_DIR="$RUNFILES_ROOT/tests/common/docker"
fi
if [[ ! -f "$DOCKER_DIR/$DOCKERFILE" ]]; then
  echo "run_in_docker.sh: missing $DOCKERFILE (source=$SOURCE_ROOT runfiles=$RUNFILES_ROOT)" >&2
  exit 1
fi

# Materialize build context so Docker does not need to follow runfiles symlinks.
BUILD_CTX="$(mktemp -d "${TMPDIR:-/tmp}/devtools-docker-build.XXXXXX")"
trap 'rm -rf "$BUILD_CTX"' EXIT
cp -L "$DOCKER_DIR/$DOCKERFILE" "$BUILD_CTX/Dockerfile"

echo "==> building $IMAGE_TAG from $DOCKER_DIR/$DOCKERFILE (source_root=$SOURCE_ROOT)"
docker build -f "$BUILD_CTX/Dockerfile" -t "$IMAGE_TAG" "$BUILD_CTX"

echo "==> running suite in $IMAGE_TAG (profile=$PROFILE)"
docker run --rm \
  -v "$SOURCE_ROOT:/workspace:ro" \
  -w /workspace \
  -e DEVTOOLS_TEST_PROFILE="$PROFILE" \
  "$IMAGE_TAG" \
  bash /workspace/tests/common/lib/run_module_test.sh \
    --profile "$PROFILE" \
    --suite "$rel_suite" \
    --module-root "$rel_module"
