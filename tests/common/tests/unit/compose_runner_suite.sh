#!/usr/bin/env bash
# Contract tests for the Compose pair E2E runner (no Docker daemon).
set -euo pipefail

DOCKER_DIR="$REPO_ROOT/tests/common/docker"
RUNNER="$DOCKER_DIR/run_compose_e2e.sh"
IPV4="$DOCKER_DIR/ipv4.sh"
COMPOSE="$DOCKER_DIR/compose/vpn-pair.yml"
PROXY_COMPOSE="$DOCKER_DIR/compose/proxy-pair.yml"
RULES="$REPO_ROOT/tests/common/rules/devtools_tests.bzl"

assert_file_exists "$RUNNER" "Compose E2E runner exists"
assert_file_exists "$IPV4" "IPv4 pull helper exists"
assert_file_exists "$COMPOSE" "VPN pair compose file exists"
assert_file_exists "$PROXY_COMPOSE" "proxy pair compose file exists"
assert_file_exists "$RULES" "devtools_tests.bzl exists"

bash -n "$RUNNER"
bash -n "$IPV4"
bash -n "$REPO_ROOT/network/vpn/tests/e2e/pair_server.sh"
bash -n "$REPO_ROOT/network/vpn/tests/e2e/pair_client.sh"
bash -n "$REPO_ROOT/network/proxy/tests/e2e/pair_server.sh"
bash -n "$REPO_ROOT/network/proxy/tests/e2e/pair_client.sh"

runner="$(cat "$RUNNER")"
assert_contains "$runner" "docker compose" "uses Compose V2"
assert_contains "$runner" "privileged systemd" "uses privileged systemd pair"
assert_contains "$runner" "linux_alinux3" "maps ALinux 3 server image"
assert_contains "$runner" "devtools-e2e:ubuntu" "maps Ubuntu client image"
assert_contains "$runner" "--server-script" "accepts a server installer path"
assert_contains "$runner" "--client-script" "accepts a client installer path"
assert_contains "$runner" "devtools-e2e-client.env" "loads client env from the server"
assert_contains "$runner" "compose_project_name" "isolates compose project names"
assert_contains "$runner" "docker_build_ipv4" "builds images with IPv4-first pull"
assert_not_contains "$runner" "setup_os_profile" "Compose E2E does not inject OS fakes"

# shellcheck source=../../docker/ipv4.sh
source "$IPV4"
assert_eq "$(docker_hub_ipv4_mirror ubuntu:24.04)" \
  "docker.m.daocloud.io/library/ubuntu:24.04" \
  "Ubuntu Docker Hub pulls fall back to an IPv4 mirror"
assert_contains "$(cat "$IPV4")" "linux/amd64" "IPv4 helper pins amd64"

compose="$(cat "$COMPOSE")"
assert_contains "$compose" "privileged: true" "server and client are privileged"
assert_contains "$compose" "/sbin/init" "PID 1 is systemd"
assert_contains "$compose" "hostname: vpn-exit" "server hostname is vpn-exit"
assert_contains "$compose" "cgroup: host" "cgroup=host for systemd"
assert_contains "$compose" "enable_ipv6: false" "compose network is IPv4-only"
assert_contains "$compose" "disable_ipv6=1" "containers disable IPv6"
assert_contains "$compose" "pull_policy: never" "does not pull local devtools-e2e tags"

proxy_compose="$(cat "$PROXY_COMPOSE")"
assert_contains "$proxy_compose" "hostname: proxy-sni" "proxy server hostname is proxy-sni"
assert_contains "$proxy_compose" "privileged: true" "proxy pair is privileged"
assert_contains "$proxy_compose" "pull_policy: never" "proxy pair does not pull local tags"

rules="$(cat "$RULES")"
assert_contains "$rules" "def devtools_compose_e2e_tests" "macro exists"
assert_contains "$rules" "server_script" "macro accepts server_script"
assert_contains "$rules" '"l3"' "compose targets are L3"

echo "PASS: compose runner contract"
