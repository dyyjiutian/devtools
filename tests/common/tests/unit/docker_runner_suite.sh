#!/usr/bin/env bash
# Contract tests for L2 Docker profile mapping and fixture images.
set -euo pipefail

DOCKER_DIR="$REPO_ROOT/tests/common/docker"
RUNNER="$DOCKER_DIR/run_in_docker.sh"
UBUNTU="$DOCKER_DIR/Dockerfile.ubuntu"
CENTOS="$DOCKER_DIR/Dockerfile.centos"
ALINUX3="$DOCKER_DIR/Dockerfile.alinux3"
ALINUX4="$DOCKER_DIR/Dockerfile.alinux4"

assert_file_exists "$RUNNER" "L2 runner exists"
assert_file_exists "$UBUNTU" "Ubuntu L2 Dockerfile exists"
assert_file_exists "$CENTOS" "CentOS/AlmaLinux L2 Dockerfile exists"
assert_file_exists "$ALINUX3" "ALinux 3 L2 Dockerfile exists"
assert_file_exists "$ALINUX4" "ALinux 4 L2 Dockerfile exists"

bash -n "$RUNNER"

runner="$(cat "$RUNNER")"
assert_contains "$runner" 'linux_ubuntu) DOCKERFILE="Dockerfile.ubuntu"; IMAGE_TAG="devtools-test:ubuntu" ;;' \
  "maps linux_ubuntu to the Ubuntu fixture"
assert_contains "$runner" 'linux_centos) DOCKERFILE="Dockerfile.centos"; IMAGE_TAG="devtools-test:centos" ;;' \
  "maps linux_centos to the AlmaLinux fixture"
assert_contains "$runner" 'linux_alinux3) DOCKERFILE="Dockerfile.alinux3"; IMAGE_TAG="devtools-test:alinux3" ;;' \
  "maps linux_alinux3 to the ALinux 3 fixture"
assert_contains "$runner" 'linux_alinux4) DOCKERFILE="Dockerfile.alinux4"; IMAGE_TAG="devtools-test:alinux4" ;;' \
  "maps linux_alinux4 to the ALinux 4 fixture"
assert_contains "$runner" "has no Docker image" "unknown profiles still fail closed"

ubuntu="$(cat "$UBUNTU")"
assert_contains "$ubuntu" "FROM ubuntu:24.04" "Ubuntu fixture uses Ubuntu 24.04"

centos="$(cat "$CENTOS")"
assert_contains "$centos" "FROM almalinux:9" "CentOS fixture uses AlmaLinux 9"
assert_contains "$centos" "not an ALinux" "AlmaLinux fixture does not claim ALinux compatibility"

alinux3="$(cat "$ALINUX3")"
assert_contains "$alinux3" \
  "FROM alibaba-cloud-linux-3-registry.cn-hangzhou.cr.aliyuncs.com/alinux3/alinux3:latest" \
  "ALinux 3 fixture uses the official Hangzhou ACR image"
assert_contains "$alinux3" "mirrors.aliyun.com" "ALinux 3 fixture rewrites cloud-internal repos"
assert_contains "$alinux3" "git tar gzip" "ALinux 3 fixture installs git and archive tools"
assert_contains "$alinux3" "not an E2E" "ALinux 3 fixture stays an L2 portability image"

alinux4="$(cat "$ALINUX4")"
assert_contains "$alinux4" \
  "FROM alibaba-cloud-linux-4-registry.cn-hangzhou.cr.aliyuncs.com/alinux4/alinux4:latest" \
  "ALinux 4 fixture uses the official Hangzhou ACR image"
assert_contains "$alinux4" "mirrors.aliyun.com" "ALinux 4 fixture rewrites cloud-internal repos"
assert_contains "$alinux4" "git tar gzip" "ALinux 4 fixture installs git and archive tools"
assert_contains "$alinux4" "not an E2E" "ALinux 4 fixture stays an L2 portability image"

echo "PASS: docker runner L2 image contract"
