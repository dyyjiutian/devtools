#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
IMAGE="${DEVTOOLS_TEST_IMAGE:-devtools-alinux3:test}"
TEST_UID="${TEST_UID:-1001}"
TEST_GID="${TEST_GID:-1001}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -x "${ROOT_DIR}/containers/alinux3/entrypoint.sh" ]] || \
  fail "missing executable entrypoint.sh"
[[ -x "${ROOT_DIR}/containers/alinux3/user-sync.sh" ]] || \
  fail "missing executable user-sync.sh"

bash -n "${ROOT_DIR}/containers/alinux3/entrypoint.sh"
bash -n "${ROOT_DIR}/containers/alinux3/user-sync.sh"

docker image inspect "$IMAGE" >/dev/null 2>&1 || \
  fail "Docker image is not available: ${IMAGE}"

WORKSPACE="$(mktemp -d)"
cleanup() {
  rm -rf "$WORKSPACE"
}
trap cleanup EXIT

docker run --rm \
  --user root \
  --env DEV_UID="$TEST_UID" \
  --env DEV_GID="$TEST_GID" \
  --volume "${WORKSPACE}:/workspace" \
  "$IMAGE" \
  bash -lc '
    test "$(id -un)" = admin
    test "$(id -u)" = "${DEV_UID}"
    test "$(id -g)" = "${DEV_GID}"
    test "$HOME" = /home/admin
    printf "%s\n" "$(id -u):$(id -g)" > /workspace/created-by-container
  '

if stat -f '%u:%g' "${WORKSPACE}/created-by-container" >/dev/null 2>&1; then
  OWNER="$(stat -f '%u:%g' "${WORKSPACE}/created-by-container")"
else
  OWNER="$(stat -c '%u:%g' "${WORKSPACE}/created-by-container")"
fi

[[ "$OWNER" == "${TEST_UID}:${TEST_GID}" ]] || \
  fail "workspace file owner ${OWNER} != ${TEST_UID}:${TEST_GID}"

echo "PASS: ${IMAGE} runtime user and workspace ownership"
