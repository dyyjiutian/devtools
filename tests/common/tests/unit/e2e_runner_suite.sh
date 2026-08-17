#!/usr/bin/env bash
# Contract tests for E2E Docker runner mapping (no fake OS profile).
set -euo pipefail

DOCKER_DIR="$REPO_ROOT/tests/common/docker"
LIB_DIR="$REPO_ROOT/tests/common/lib"
RUNNER="$DOCKER_DIR/run_e2e_in_docker.sh"
HOST_RUNNER="$LIB_DIR/run_e2e_test.sh"
UBUNTU="$DOCKER_DIR/Dockerfile.e2e.ubuntu"
ALINUX3="$DOCKER_DIR/Dockerfile.e2e.alinux3"
ALINUX4="$DOCKER_DIR/Dockerfile.e2e.alinux4"

assert_file_exists "$RUNNER" "E2E docker runner exists"
assert_file_exists "$HOST_RUNNER" "E2E host runner exists"
assert_file_exists "$UBUNTU" "Ubuntu E2E Dockerfile exists"
assert_file_exists "$ALINUX3" "ALinux 3 E2E Dockerfile exists"
assert_file_exists "$ALINUX4" "ALinux 4 E2E Dockerfile exists"

bash -n "$RUNNER"
bash -n "$HOST_RUNNER"

runner="$(cat "$RUNNER")"
assert_contains "$runner" 'linux_ubuntu) DOCKERFILE="Dockerfile.e2e.ubuntu"; IMAGE_TAG="devtools-e2e:ubuntu" ;;' \
  "maps linux_ubuntu to the Ubuntu E2E image"
assert_contains "$runner" 'linux_alinux3) DOCKERFILE="Dockerfile.e2e.alinux3"; IMAGE_TAG="devtools-e2e:alinux3" ;;' \
  "maps linux_alinux3 to the ALinux 3 E2E image"
assert_contains "$runner" 'linux_alinux4) DOCKERFILE="Dockerfile.e2e.alinux4"; IMAGE_TAG="devtools-e2e:alinux4" ;;' \
  "maps linux_alinux4 to the ALinux 4 E2E image"
assert_contains "$runner" "run_e2e_test.sh" "container invokes the E2E host runner"
assert_contains "$runner" "--platform linux/amd64" "E2E pins the x86_64 compatibility baseline"
assert_contains "$runner" "docker_build_ipv4" "E2E builds with IPv4-first registry pull"
assert_not_contains "$runner" "setup_os_profile" "E2E docker runner does not inject OS fakes"
assert_not_contains "$runner" "run_module_test.sh" "E2E does not reuse the L2 fake runner"

host="$(cat "$HOST_RUNNER")"
assert_contains "$host" "setup.sh" "E2E host runner runs module setup.sh"
assert_not_contains "$host" "setup_os_profile" "E2E host runner does not inject OS fakes"
assert_contains "$host" "DEVTOOLS_E2E_REQUIRE_DARWIN" "host runner can require Darwin for macOS L3"

ubuntu="$(cat "$UBUNTU")"
assert_contains "$ubuntu" "FROM ubuntu:24.04" "Ubuntu E2E uses Ubuntu 24.04"
assert_contains "$ubuntu" "sudo" "Ubuntu E2E provides sudo for installers"
assert_contains "$ubuntu" "systemd" "Ubuntu E2E installs systemd for Compose pair tests"

alinux3="$(cat "$ALINUX3")"
assert_contains "$alinux3" \
  "FROM alibaba-cloud-linux-3-registry.cn-hangzhou.cr.aliyuncs.com/alinux3/alinux3:latest" \
  "ALinux 3 E2E uses the official image"
assert_contains "$alinux3" "mirrors.aliyun.com" "ALinux 3 E2E rewrites cloud-internal repos"

alinux4="$(cat "$ALINUX4")"
assert_contains "$alinux4" \
  "FROM alibaba-cloud-linux-4-registry.cn-hangzhou.cr.aliyuncs.com/alinux4/alinux4:latest" \
  "ALinux 4 E2E uses the official image"
assert_contains "$alinux4" "mirrors.aliyun.com" "ALinux 4 E2E rewrites cloud-internal repos"

echo "PASS: e2e runner contract"
