#!/usr/bin/env bash
# Unit tests for ALinux/CentOS repository rendering helpers.
set -euo pipefail

SETUP_CENTOS="$REPO_ROOT/os/linux/setup_centos.sh"
TMP_ROOT="$HOME/repository-render"
mkdir -p "$TMP_ROOT"

export SETUP_CENTOS_NO_MAIN=1
export OS_RELEASE_FILE="$TMP_ROOT/os-release"
# shellcheck disable=SC1090
source "$SETUP_CENTOS"

cat >"$TMP_ROOT/docker-ce.repo" <<'EOF'
[docker-ce-stable]
baseurl=https://download.docker.com/linux/centos/$releasever/$basearch/stable
EOF

printf 'ID=alinux\nVERSION_ID=3\n' >"$OS_RELEASE_FILE"
render_docker_repo "$TMP_ROOT/docker-ce.repo" "$TMP_ROOT/alinux3.repo"
alinux3_repo="$(cat "$TMP_ROOT/alinux3.repo")"
assert_contains "$alinux3_repo" "https://download.docker.com/linux/centos" \
  "ALinux 3 keeps the upstream Docker repository"
assert_contains "$alinux3_repo" "/centos/8/" \
  "ALinux 3 pins Docker CE to the el8 tree"
assert_not_contains "$alinux3_repo" '$releasever' \
  "ALinux 3 must not pass its releasever to the CentOS repository"

dnf_mirrors_render_companion_repo "$TMP_ROOT/alinux3.repo" "$TMP_ROOT/alinux3-aliyun.repo"
alinux3_aliyun="$(cat "$TMP_ROOT/alinux3-aliyun.repo")"
assert_contains "$alinux3_aliyun" "mirrors.aliyun.com/docker-ce/linux/centos/8/" \
  "ALinux 3 also gets an Aliyun Docker CE companion"
assert_contains "$alinux3_aliyun" "[docker-ce-stable-aliyun]" \
  "ALinux 3 Aliyun companion uses a distinct repo id"

dnf_mirrors_write_epel_el8 "$TMP_ROOT/alinux3-epel.repo"
alinux3_epel="$(cat "$TMP_ROOT/alinux3-epel.repo")"
assert_contains "$alinux3_epel" "mirrors.aliyun.com/epel/8/Everything" \
  "ALinux 3 gets Aliyun EPEL 8"

printf 'ID=alinux\nVERSION_ID=4\n' >"$OS_RELEASE_FILE"
render_docker_repo "$TMP_ROOT/docker-ce.repo" "$TMP_ROOT/alinux4.repo"
alinux4_repo="$(cat "$TMP_ROOT/alinux4.repo")"
assert_contains "$alinux4_repo" "mirrors.cloud.aliyuncs.com/docker-ce/linux/centos" \
  "ALinux 4 uses the Alibaba Cloud mirror"
assert_contains "$alinux4_repo" "/centos/9/" \
  "ALinux 4 pins a compatible Docker repository version"
assert_not_contains "$alinux4_repo" '$releasever' \
  "ALinux 4 must not pass its releasever to the CentOS repository"
assert_not_contains "$alinux4_repo" "/centos/4/" \
  "ALinux 4 must not use its own major version as a CentOS version"

printf 'ID=centos\nVERSION_ID=9\n' >"$OS_RELEASE_FILE"
render_docker_repo "$TMP_ROOT/docker-ce.repo" "$TMP_ROOT/centos.repo"
centos_repo="$(cat "$TMP_ROOT/centos.repo")"
assert_contains "$centos_repo" "https://download.docker.com/linux/centos" \
  "CentOS keeps the upstream Docker repository"
assert_contains "$centos_repo" '$releasever' \
  "the internal CentOS adapter keeps releasever"

dnf_mirrors_render_companion_repo "$TMP_ROOT/centos.repo" "$TMP_ROOT/centos-aliyun.repo"
centos_aliyun="$(cat "$TMP_ROOT/centos-aliyun.repo")"
assert_contains "$centos_aliyun" "mirrors.aliyun.com/docker-ce/linux/centos" \
  "CentOS also gets an Aliyun Docker CE companion"
assert_contains "$centos_aliyun" '$releasever' \
  "CentOS Aliyun companion keeps releasever"

pass "ALinux Docker repository rendering"
