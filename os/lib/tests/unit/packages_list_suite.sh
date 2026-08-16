#!/usr/bin/env bash
# Unit tests for os/lib/packages_list.sh.
set -euo pipefail

PACKAGES_LIB="$REPO_ROOT/os/lib/packages_list.sh"
CENTOS_LIST="$REPO_ROOT/os/linux/packages.centos.list"
UBUNTU_LIST="$REPO_ROOT/os/linux/packages.ubuntu.list"
MACOS_LIST="$REPO_ROOT/os/macos/packages.list"

# shellcheck disable=SC1090
source "$PACKAGES_LIB"

assert_eq "$(packages_list_get_version "$CENTOS_LIST" yazi)" "0.3.3" \
  "CentOS yazi version"
assert_eq "$(packages_list_get_version "$CENTOS_LIST" tmux)" "3.7b" \
  "CentOS tmux version"

packages_list_has "$MACOS_LIST" git ||
  { echo "FAIL: macOS packages.list missing git" >&2; return 1; }
packages_list_has "$UBUNTU_LIST" docker ||
  { echo "FAIL: Ubuntu packages.list missing docker" >&2; return 1; }
packages_list_has "$CENTOS_LIST" jq ||
  { echo "FAIL: CentOS packages.list missing jq" >&2; return 1; }
packages_list_has "$CENTOS_LIST" bat ||
  { echo "FAIL: CentOS packages.list missing bat" >&2; return 1; }
packages_list_has "$CENTOS_LIST" rg ||
  { echo "FAIL: CentOS packages.list missing rg" >&2; return 1; }
packages_list_has "$UBUNTU_LIST" bat ||
  { echo "FAIL: Ubuntu packages.list missing bat" >&2; return 1; }
packages_list_has "$MACOS_LIST" rg ||
  { echo "FAIL: macOS packages.list missing rg" >&2; return 1; }
packages_list_has "$MACOS_LIST" glow ||
  { echo "FAIL: macOS packages.list missing glow" >&2; return 1; }
packages_list_has "$UBUNTU_LIST" glow ||
  { echo "FAIL: Ubuntu packages.list missing glow" >&2; return 1; }
packages_list_has "$CENTOS_LIST" glow ||
  { echo "FAIL: CentOS packages.list missing glow" >&2; return 1; }
assert_eq "$(packages_list_get_version "$CENTOS_LIST" glow)" "2.1.2" \
  "CentOS glow version"
assert_eq "$(packages_list_get_version "$UBUNTU_LIST" glow)" "2.1.2" \
  "Ubuntu glow version"

assert_eq "$(packages_list_brew_formula rg)" "ripgrep" "rg Homebrew formula"
assert_eq "$(packages_list_sys_pkg rg)" "ripgrep" "rg system package"

pass "packages.list parser and repository manifests"
