#!/usr/bin/env bash
# E2E runner: build an official OS image and run real setup.sh + ops suite.
# Does not inject fake uname / package managers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_COMMON_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

_is_repo_root() {
  local candidate="$1"
  [[ -f "$candidate/tests/common/lib/run_e2e_test.sh" &&
     -f "$candidate/tests/common/lib/assert.sh" ]]
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
  echo "run_e2e_in_docker.sh: cannot resolve repository root" >&2
  return 1
}

resolve_source_root() {
  local runfiles_root="$1"
  local marker="$runfiles_root/tests/common/lib/run_e2e_test.sh"
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
    echo "run_e2e_in_docker.sh: docker not found on PATH=$PATH" >&2
    return 1
  fi
  export PATH="$(dirname "$docker_bin"):/usr/bin:/bin:${PATH:-}"

  if [[ -z "${DOCKER_HOST:-}" && -S /var/run/docker.sock ]]; then
    export DOCKER_HOST="unix:///var/run/docker.sock"
  fi

  if docker info >/dev/null 2>&1; then
    return 0
  fi

  if [[ "${DEVTOOLS_DOCKER_SG:-}" != "1" ]] && command -v sg >/dev/null 2>&1 && _user_in_docker_group; then
    quoted="$(printf '%q ' "$0" "$@")"
    export DEVTOOLS_DOCKER_SG=1
    exec sg docker -c "export DEVTOOLS_DOCKER_SG=1; export DOCKER_HOST=$(printf '%q' "$DOCKER_HOST"); export PATH=$(printf '%q' "$PATH"); export TEST_SRCDIR=$(printf '%q' "${TEST_SRCDIR:-}"); export TEST_WORKSPACE=$(printf '%q' "${TEST_WORKSPACE:-}"); export BUILD_WORKSPACE_DIRECTORY=$(printf '%q' "${BUILD_WORKSPACE_DIRECTORY:-}"); ${quoted}"
  fi

  err="$(docker info 2>&1 || true)"
  echo "run_e2e_in_docker.sh: docker daemon not available" >&2
  echo "  docker=$docker_bin" >&2
  echo "  DOCKER_HOST=${DOCKER_HOST:-<unset>}" >&2
  echo "  docker info: $err" >&2
  return 1
}

ORIGINAL_ARGS=("$@")
PROFILE=""
SUITE_PATH=""
MODULE_ROOT=""
SETUP_ARGS=()
BUILD_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --suite) SUITE_PATH="${2:-}"; shift 2 ;;
    --module-root) MODULE_ROOT="${2:-}"; shift 2 ;;
    --setup-arg) SETUP_ARGS+=("${2:-}"); shift 2 ;;
    --build-only) BUILD_ONLY=true; shift ;;
    -h|--help)
      echo "Usage: run_e2e_in_docker.sh --profile PROFILE --suite PATH --module-root PATH [--setup-arg ARG]... [--build-only]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PROFILE" ]] || { ! $BUILD_ONLY && [[ -z "$SUITE_PATH" || -z "$MODULE_ROOT" ]]; }; then
  echo "run_e2e_in_docker.sh: --profile, --suite, and --module-root are required (--build-only needs just --profile)" >&2
  exit 1
fi

case "$PROFILE" in
  linux_ubuntu) DOCKERFILE="Dockerfile.e2e.ubuntu"; IMAGE_TAG="devtools-e2e:ubuntu" ;;
  linux_alinux3) DOCKERFILE="Dockerfile.e2e.alinux3"; IMAGE_TAG="devtools-e2e:alinux3" ;;
  linux_alinux4) DOCKERFILE="Dockerfile.e2e.alinux4"; IMAGE_TAG="devtools-e2e:alinux4" ;;
  *)
    echo "run_e2e_in_docker.sh: profile '$PROFILE' has no E2E image" >&2
    exit 1
    ;;
esac

ensure_docker "${ORIGINAL_ARGS[@]}"

RUNFILES_ROOT="$(resolve_repo_root)"
SOURCE_ROOT="$(resolve_source_root "$RUNFILES_ROOT")"

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
  echo "run_e2e_in_docker.sh: missing $DOCKERFILE" >&2
  exit 1
fi
if [[ ! -f "$DOCKER_DIR/ipv4.sh" ]]; then
  echo "run_e2e_in_docker.sh: missing $DOCKER_DIR/ipv4.sh" >&2
  exit 1
fi
# shellcheck source=ipv4.sh
source "$DOCKER_DIR/ipv4.sh"

src_dockerfile="$DOCKER_DIR/$DOCKERFILE"
if image_matches_dockerfile "$IMAGE_TAG" "$src_dockerfile"; then
  echo "==> reusing $IMAGE_TAG (dockerfile unchanged)"
else
  BUILD_CTX="$(mktemp -d "${TMPDIR:-/tmp}/devtools-e2e-build.XXXXXX")"
  trap 'rm -rf "$BUILD_CTX"' EXIT
  stage_e2e_dockerfile "$src_dockerfile" "$BUILD_CTX" "$SOURCE_ROOT"
  dockerfile_sha="$(file_sha256 "$src_dockerfile")"
  echo "==> building $IMAGE_TAG from $src_dockerfile (platform=linux/amd64, IPv4)"
  docker_build_ipv4 "$BUILD_CTX/Dockerfile" \
    -f "$BUILD_CTX/Dockerfile" \
    --label "devtools.dockerfile.sha=${dockerfile_sha}" \
    -t "$IMAGE_TAG" \
    "$BUILD_CTX"
fi

# CI pre-builds images in a separate step so a slow mirror build (alinux3 can
# take 30min from US runners) never eats into a test's bazel timeout budget.
if $BUILD_ONLY; then
  echo "==> build-only: $IMAGE_TAG ready"
  exit 0
fi

run_args=(
  bash /workspace/tests/common/lib/run_e2e_test.sh
  --suite "$rel_suite"
  --module-root "$rel_module"
)
if [[ ${#SETUP_ARGS[@]} -gt 0 ]]; then
  for arg in "${SETUP_ARGS[@]}"; do
    run_args+=(--setup-arg "$arg")
  done
fi

echo "==> running E2E in $IMAGE_TAG (profile=$PROFILE, platform=linux/amd64)"
docker run --rm --platform linux/amd64 \
  -v "$SOURCE_ROOT:/workspace:ro" \
  -w /workspace \
  -e DEVTOOLS_TEST_PROFILE="$PROFILE" \
  -e DEVTOOLS_CACHE_DIR=/workspace/cache \
  -e NVIM_SETUP_STRICT=1 \
  "$IMAGE_TAG" \
  "${run_args[@]}"
