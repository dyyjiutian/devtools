#!/usr/bin/env bash
# Unit tests for os/lib/dnf_mirrors.sh.
set -euo pipefail

MIRRORS_LIB="$REPO_ROOT/os/lib/dnf_mirrors.sh"
EPEL8_REPO="$REPO_ROOT/os/lib/repos/epel-8-aliyun.repo"
TMP_ROOT="$HOME/dnf-mirrors"

# shellcheck disable=SC1090
source "$MIRRORS_LIB"

mkdir -p "$TMP_ROOT"

assert_eq "$(dnf_mirrors_aliyun_base)" "https://mirrors.aliyun.com" \
  "default Aliyun public mirror"

assert_eq \
  "$(dnf_mirrors_rewrite_url 'https://download.docker.com/linux/centos/8/x86_64/stable')" \
  "https://mirrors.aliyun.com/docker-ce/linux/centos/8/x86_64/stable" \
  "rewrites Docker CE baseurl to Aliyun"

assert_eq \
  "$(dnf_mirrors_rewrite_url 'https://download.docker.com/linux/centos/gpg')" \
  "https://mirrors.aliyun.com/docker-ce/linux/centos/gpg" \
  "rewrites Docker CE gpgkey to Aliyun"

if dnf_mirrors_rewrite_url 'https://cli.github.com/packages/rpm' >/dev/null; then
  echo "FAIL: GitHub CLI has no Aliyun RPM mapping" >&2
  exit 1
fi
if dnf_mirrors_rewrite_url 'https://rpm.nodesource.com/pub_20.x/el/8/x86_64' >/dev/null; then
  echo "FAIL: NodeSource has no Aliyun RPM mapping" >&2
  exit 1
fi

cat >"$TMP_ROOT/docker-ce.repo" <<'EOF'
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=https://download.docker.com/linux/centos/8/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/centos/gpg
EOF

dnf_mirrors_render_companion_repo "$TMP_ROOT/docker-ce.repo" "$TMP_ROOT/docker-ce-aliyun.repo"
companion="$(cat "$TMP_ROOT/docker-ce-aliyun.repo")"
assert_contains "$companion" "[docker-ce-stable-aliyun]" "companion renames the repo id"
assert_contains "$companion" "mirrors.aliyun.com/docker-ce/linux/centos/8/" \
  "companion uses the Aliyun Docker CE tree"
assert_contains "$companion" "mirrors.aliyun.com/docker-ce/linux/centos/gpg" \
  "companion uses the Aliyun Docker CE gpg key"
assert_not_contains "$companion" "download.docker.com" \
  "companion drops the official Docker host"

cat >"$TMP_ROOT/gh-cli.repo" <<'EOF'
[gh-cli]
name=packages for gh
baseurl=https://cli.github.com/packages/rpm
enabled=1
gpgkey=https://cli.github.com/packages/rpm/gpg.key
EOF

if dnf_mirrors_render_companion_repo "$TMP_ROOT/gh-cli.repo" "$TMP_ROOT/gh-cli-aliyun.repo"; then
  echo "FAIL: gh-cli companion should not be written without an Aliyun mapping" >&2
  exit 1
fi
[[ ! -f "$TMP_ROOT/gh-cli-aliyun.repo" ]] || {
  echo "FAIL: gh-cli companion file should not exist" >&2
  exit 1
}

DOCKER_CE8_REPO="${REPO_ROOT}/os/lib/repos/docker-ce-8.repo"
DOCKER_CE8_ALIYUN="${REPO_ROOT}/os/lib/repos/docker-ce-8-aliyun.repo"
assert_file_exists "$DOCKER_CE8_REPO"
assert_file_exists "$DOCKER_CE8_ALIYUN"
docker_ce8="$(cat "$DOCKER_CE8_REPO")"
docker_ce8_aliyun="$(cat "$DOCKER_CE8_ALIYUN")"
assert_contains "$docker_ce8" "/centos/8/" "official Docker CE repo pins centos/8"
assert_contains "$docker_ce8_aliyun" "mirrors.aliyun.com/docker-ce/linux/centos/8/" \
  "Aliyun Docker CE repo pins centos/8"
if grep -Fq '$releasever' <<<"$docker_ce8$docker_ce8_aliyun"; then
  echo "FAIL: Docker CE el8 repos must pin centos/8, not \$releasever" >&2
  exit 1
fi

dnf_mirrors_write_epel_el8 "$TMP_ROOT/epel.repo"
epel="$(cat "$TMP_ROOT/epel.repo")"
assert_file_exists "$EPEL8_REPO"
assert_contains "$epel" "mirrors.aliyun.com/epel/8/Everything" "EPEL 8 uses Aliyun el8"
assert_contains "$epel" "RPM-GPG-KEY-EPEL-8" "EPEL 8 uses the el8 GPG key"
assert_contains "$epel" "[devtools-epel-8-aliyun]" "EPEL 8 uses a managed repo id"
if grep -Fq '$releasever' <<<"$epel"; then
  echo "FAIL: EPEL 8 repo must pin el8, not \$releasever" >&2
  exit 1
fi

pass "DNF Aliyun companion and EPEL 8 helpers"
