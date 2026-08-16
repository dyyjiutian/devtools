#!/usr/bin/env bash
# Module integration tests for Ubuntu and Alibaba Cloud Linux setup scripts.
set -euo pipefail

UBUNTU_SETUP="$MODULE_ROOT/setup_ubuntu.sh"
ALINUX_SETUP="$MODULE_ROOT/setup_centos.sh"

bash -n "$UBUNTU_SETUP"
bash -n "$ALINUX_SETUP"

case "$DEVTOOLS_TEST_PROFILE" in
  linux_ubuntu)
    assert_contains "$(cat "$OS_RELEASE_FILE")" "ID=ubuntu" "Ubuntu profile os-release"

    ubuntu_dry="$(bash "$UBUNTU_SETUP" --dry-run --packages-only 2>&1)"
    assert_contains "$ubuntu_dry" "[dry-run] docker" "Ubuntu dry-run includes Docker"
    assert_contains "$ubuntu_dry" "[dry-run] lazygit" "Ubuntu dry-run includes lazygit"
    assert_contains "$ubuntu_dry" "[dry-run] glow" "Ubuntu dry-run includes glow"

    ubuntu_check="$(bash "$UBUNTU_SETUP" --check 2>&1)"
    assert_contains "$ubuntu_check" "summary:" "Ubuntu check summary"
    if ! grep -Eq 'installed|missing' <<<"$ubuntu_check"; then
      echo "FAIL: Ubuntu check has no status column" >&2
      return 1
    fi

    ubuntu_filter="$(bash "$UBUNTU_SETUP" --dry-run --packages-only --kind tui 2>&1)"
    assert_contains "$ubuntu_filter" "[dry-run] tmux" "Ubuntu TUI filter includes tmux"
    assert_contains "$ubuntu_filter" "[dry-run] glow" "Ubuntu TUI filter includes glow"
    assert_not_contains "$ubuntu_filter" "[dry-run] docker" "Ubuntu TUI filter excludes Docker"

    ubuntu_skip="$(bash "$UBUNTU_SETUP" --dry-run --packages-only --skip-tools 2>&1)"
    assert_not_contains "$ubuntu_skip" "[dry-run] glow" "Ubuntu --skip-tools excludes glow"
    ;;

  linux_alinux3|linux_alinux4)
    expected_version="${DEVTOOLS_TEST_PROFILE#linux_alinux}"
    assert_contains "$(cat "$OS_RELEASE_FILE")" "ID=alinux" "ALinux profile os-release"
    assert_contains "$(cat "$OS_RELEASE_FILE")" "VERSION_ID=$expected_version" \
      "ALinux profile version"

    alinux_dry="$(bash "$ALINUX_SETUP" --dry-run --packages-only 2>&1)"
    assert_contains "$alinux_dry" "[dry-run] docker" "ALinux dry-run includes Docker"
    assert_contains "$alinux_dry" "[dry-run] yazi" "ALinux dry-run includes yazi"
    assert_contains "$alinux_dry" "[dry-run] glow" "ALinux dry-run includes glow"
    assert_contains "$alinux_dry" "packages.centos.list" "ALinux uses RPM package manifest"

    alinux_check="$(bash "$ALINUX_SETUP" --check 2>&1)"
    assert_contains "$alinux_check" "NAME" "ALinux check name column"
    assert_contains "$alinux_check" "KIND" "ALinux check kind column"
    assert_contains "$alinux_check" "TAGS" "ALinux check tags column"
    assert_contains "$alinux_check" "summary:" "ALinux check summary"

    alinux_kind="$(bash "$ALINUX_SETUP" --check --kind tui 2>&1)"
    assert_contains "$alinux_kind" "tmux" "ALinux TUI filter includes tmux"
    assert_contains "$alinux_kind" "yazi" "ALinux TUI filter includes yazi"
    assert_contains "$alinux_kind" "glow" "ALinux TUI filter includes glow"
    assert_not_contains "$alinux_kind" "docker" "ALinux TUI filter excludes Docker"

    alinux_tag="$(bash "$ALINUX_SETUP" --check --tag diagnostic 2>&1)"
    assert_contains "$alinux_tag" "rg" "ALinux diagnostic filter includes rg"
    assert_contains "$alinux_tag" "cloc" "ALinux diagnostic filter includes cloc"
    assert_not_contains "$alinux_tag" "lazygit" "ALinux diagnostic filter excludes lazygit"

    alinux_install_one="$(bash "$ALINUX_SETUP" --install bat --dry-run 2>&1)"
    assert_contains "$alinux_install_one" "[dry-run] bat" "ALinux single install includes bat"
    assert_not_contains "$alinux_install_one" "[dry-run] docker" \
      "ALinux single install excludes Docker"

    alinux_skip="$(bash "$ALINUX_SETUP" --dry-run --packages-only --skip-tools 2>&1)"
    assert_not_contains "$alinux_skip" "[dry-run] glow" "ALinux --skip-tools excludes glow"
    ;;

  *)
    echo "FAIL: unsupported Linux integration profile: $DEVTOOLS_TEST_PROFILE" >&2
    return 1
    ;;
esac

pass "Linux setup integration ($DEVTOOLS_TEST_PROFILE)"
