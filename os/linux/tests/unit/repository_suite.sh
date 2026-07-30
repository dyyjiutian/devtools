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
assert_contains "$alinux3_repo" '$releasever' \
  "ALinux 3 keeps releasever"

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
assert_contains "$centos_repo" '$releasever' \
  "the internal CentOS adapter keeps releasever"

pass "ALinux Docker repository rendering"
