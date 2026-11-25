#!/usr/bin/env bash
# L3 pair runner: docker compose + privileged systemd (server/client).
# Host-side script; must stay Bash 3.2 compatible.
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
  echo "run_compose_e2e.sh: cannot resolve repository root" >&2
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
    echo "run_compose_e2e.sh: docker not found on PATH=$PATH" >&2
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
  echo "run_compose_e2e.sh: docker daemon not available" >&2
  echo "  docker=$docker_bin" >&2
  echo "  DOCKER_HOST=${DOCKER_HOST:-<unset>}" >&2
  echo "  docker info: $err" >&2
  return 1
}

ensure_compose() {
  if docker compose version >/dev/null 2>&1; then
    return 0
  fi
  echo "run_compose_e2e.sh: docker compose (V2 plugin) is required" >&2
  return 1
}

e2e_image_for_profile() {
  case "$1" in
    linux_ubuntu) printf '%s\n' "Dockerfile.e2e.ubuntu" "devtools-e2e:ubuntu" ;;
    linux_alinux3) printf '%s\n' "Dockerfile.e2e.alinux3" "devtools-e2e:alinux3" ;;
    linux_alinux4) printf '%s\n' "Dockerfile.e2e.alinux4" "devtools-e2e:alinux4" ;;
    *)
      echo "run_compose_e2e.sh: profile '$1' has no E2E image" >&2
      return 1
      ;;
  esac
}

build_e2e_image() {
  local dockerfile="$1" image_tag="$2" docker_dir="$3"
  local build_ctx repo_root src dockerfile_sha
  src="$docker_dir/$dockerfile"
  if [[ -n "${SOURCE_ROOT:-}" && -d "${SOURCE_ROOT}/cache/binaries" ]]; then
    repo_root="$SOURCE_ROOT"
  else
    repo_root="$(cd "$docker_dir/../../.." && pwd -P)"
  fi
  if image_matches_dockerfile "$image_tag" "$src"; then
    echo "==> reusing local amd64 $image_tag (dockerfile unchanged)"
    return 0
  fi
  build_ctx="$(mktemp -d "${TMPDIR:-/tmp}/devtools-compose-build.XXXXXX")"
  stage_e2e_dockerfile "$src" "$build_ctx" "$repo_root"
  dockerfile_sha="$(file_sha256 "$src")"
  echo "==> building $image_tag from $src (platform=linux/amd64, IPv4)"
  docker_build_ipv4 "$build_ctx/Dockerfile" \
    -f "$build_ctx/Dockerfile" \
    --label "devtools.dockerfile.sha=${dockerfile_sha}" \
    -t "$image_tag" \
    "$build_ctx"
  rm -rf "$build_ctx"
}

compose_project_name() {
  local raw suffix
  raw="${TEST_TMPDIR:-${TEST_UNDECLARED_OUTPUTS_DIR:-$$}}"
  suffix="$(printf '%s' "$raw" | tr -cd 'a-zA-Z0-9' | tail -c 20)"
  [[ -n "$suffix" ]] || suffix="$$"
  printf 'dtvpn%s\n' "$suffix"
}

wait_systemd() {
  local service="$1" state deadline
  # alinux3's older systemd boots slowly under parallel CI load (docker builds
  # + dnf on --jobs=2). The pair tests are size=enormous (3600s), so give the
  # boot a realistic budget; the old ~240s window timed out under load.
  deadline=$((SECONDS + 600))
  while [[ $SECONDS -lt $deadline ]]; do
    state="$(docker compose -p "$PROJECT" -f "$COMPOSE_FILE" exec -T "$service" \
      systemctl is-system-running 2>/dev/null || true)"
    case "$state" in
      running|degraded)
        echo "==> systemd $service is $state"
        return 0
        ;;
    esac
    sleep 2
  done
  echo "run_compose_e2e.sh: systemd not ready in $service (state=${state:-unknown})" >&2
  # systemd writes to the journal, so console logs are empty; dump the queued
  # jobs and failed units to expose whatever is blocking the boot.
  docker compose -p "$PROJECT" -f "$COMPOSE_FILE" exec -T "$service" \
    systemctl list-jobs --no-pager >&2 || true
  docker compose -p "$PROJECT" -f "$COMPOSE_FILE" exec -T "$service" \
    systemctl --failed --no-pager >&2 || true
  docker compose -p "$PROJECT" -f "$COMPOSE_FILE" logs "$service" >&2 || true
  return 1
}

to_repo_rel() {
  local p="$1"
  [[ "$p" = /* ]] && p="${p#"$RUNFILES_ROOT"/}"
  [[ "$p" = /* ]] && p="${p#"$SOURCE_ROOT"/}"
  printf '%s\n' "$p"
}

ORIGINAL_ARGS=("$@")
COMPOSE_PATH=""
SERVER_PROFILE="linux_alinux3"
CLIENT_PROFILE=""
SERVER_SCRIPT="network/vpn/tests/e2e/pair_server.sh"
CLIENT_SCRIPT="network/vpn/tests/e2e/pair_client.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose) COMPOSE_PATH="${2:-}"; shift 2 ;;
    --server-profile) SERVER_PROFILE="${2:-}"; shift 2 ;;
    --client-profile) CLIENT_PROFILE="${2:-}"; shift 2 ;;
    --server-script) SERVER_SCRIPT="${2:-}"; shift 2 ;;
    --client-script) CLIENT_SCRIPT="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: run_compose_e2e.sh --compose PATH --client-profile PROFILE [--server-profile PROFILE] [--server-script PATH] [--client-script PATH]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$COMPOSE_PATH" || -z "$CLIENT_PROFILE" ]]; then
  echo "run_compose_e2e.sh: --compose and --client-profile are required" >&2
  exit 1
fi

ensure_docker "${ORIGINAL_ARGS[@]}"
ensure_compose

# GitHub ubuntu-latest runs --jobs=2; serialize privileged systemd stacks
# so cgroup contention cannot stall systemctl is-system-running.
if command -v flock >/dev/null 2>&1; then
  exec 9>"${TMPDIR:-/tmp}/devtools-e2e-compose.lock"
  flock 9
fi

RUNFILES_ROOT="$(resolve_repo_root)"
SOURCE_ROOT="$(resolve_source_root "$RUNFILES_ROOT")"

rel_compose="$COMPOSE_PATH"
[[ "$rel_compose" = /* ]] && rel_compose="${rel_compose#"$RUNFILES_ROOT"/}"
[[ "$rel_compose" = /* ]] && rel_compose="${rel_compose#"$SOURCE_ROOT"/}"

COMPOSE_FILE="$SOURCE_ROOT/$rel_compose"
if [[ ! -f "$COMPOSE_FILE" ]]; then
  COMPOSE_FILE="$RUNFILES_ROOT/$rel_compose"
fi
if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "run_compose_e2e.sh: missing compose file $rel_compose" >&2
  exit 1
fi

DOCKER_DIR="$SOURCE_ROOT/tests/common/docker"
if [[ ! -f "$DOCKER_DIR/Dockerfile.e2e.ubuntu" ]]; then
  DOCKER_DIR="$RUNFILES_ROOT/tests/common/docker"
fi
if [[ ! -f "$DOCKER_DIR/ipv4.sh" ]]; then
  echo "run_compose_e2e.sh: missing $DOCKER_DIR/ipv4.sh" >&2
  exit 1
fi
# shellcheck source=ipv4.sh
source "$DOCKER_DIR/ipv4.sh"

server_meta="$(e2e_image_for_profile "$SERVER_PROFILE")"
client_meta="$(e2e_image_for_profile "$CLIENT_PROFILE")"
SERVER_DOCKERFILE="$(printf '%s\n' "$server_meta" | sed -n '1p')"
SERVER_IMAGE="$(printf '%s\n' "$server_meta" | sed -n '2p')"
CLIENT_DOCKERFILE="$(printf '%s\n' "$client_meta" | sed -n '1p')"
CLIENT_IMAGE="$(printf '%s\n' "$client_meta" | sed -n '2p')"

build_e2e_image "$SERVER_DOCKERFILE" "$SERVER_IMAGE" "$DOCKER_DIR"
if [[ "$CLIENT_IMAGE" != "$SERVER_IMAGE" ]]; then
  build_e2e_image "$CLIENT_DOCKERFILE" "$CLIENT_IMAGE" "$DOCKER_DIR"
fi

export DEVTOOLS_REPO_ROOT="$SOURCE_ROOT"
export SERVER_IMAGE
export CLIENT_IMAGE

PROJECT="$(compose_project_name)"
cleanup() {
  docker compose -p "$PROJECT" -f "$COMPOSE_FILE" down -v --remove-orphans --timeout 20 >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> compose up project=$PROJECT server=$SERVER_IMAGE client=$CLIENT_IMAGE"
docker compose -p "$PROJECT" -f "$COMPOSE_FILE" up -d --force-recreate

wait_systemd server
wait_systemd client

rel_server="$(to_repo_rel "$SERVER_SCRIPT")"
rel_client="$(to_repo_rel "$CLIENT_SCRIPT")"

echo "==> installing server via $rel_server"
docker compose -p "$PROJECT" -f "$COMPOSE_FILE" exec -T server \
  bash "/workspace/$rel_server"

client_env_file="$(docker compose -p "$PROJECT" -f "$COMPOSE_FILE" exec -T server \
  cat /tmp/devtools-e2e-client.env 2>/dev/null | tr -d '\r' || true)"
if [[ -z "$client_env_file" ]]; then
  vless="$(docker compose -p "$PROJECT" -f "$COMPOSE_FILE" exec -T server \
    cat /tmp/devtools-e2e-vless.txt 2>/dev/null | tr -d '\r\n' || true)"
  [[ -n "$vless" ]] && client_env_file="VLESS_LINK=${vless}"
fi
if [[ -z "$client_env_file" ]]; then
  echo "run_compose_e2e.sh: server did not write /tmp/devtools-e2e-client.env" >&2
  exit 1
fi

client_env_args=()
while IFS= read -r line; do
  case "$line" in
    *=*) client_env_args+=(-e "$line") ;;
  esac
done <<EOF
$client_env_file
EOF

echo "==> installing client via $rel_client"
docker compose -p "$PROJECT" -f "$COMPOSE_FILE" exec -T \
  "${client_env_args[@]}" \
  client bash "/workspace/$rel_client"

echo "PASS: compose pair ($SERVER_PROFILE server, $CLIENT_PROFILE client)"
