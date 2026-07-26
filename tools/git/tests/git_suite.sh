#!/usr/bin/env bash
# Git module suite — expects run_module_test.sh environment:
#   MODULE_ROOT, HOME, DEVTOOLS_TEST_PROFILE, assert helpers, profile fakes on PATH
set -euo pipefail

SETUP_SH="$MODULE_ROOT/setup.sh"
SUBCMD_SH="$MODULE_ROOT/scripts/sub-command.sh"
CONFIG_SH="$MODULE_ROOT/scripts/config.sh"

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "dry-run" "setup --help mentions dry-run"
  pass "git setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_unknown_flag() {
  local rc=0
  bash "$SETUP_SH" --not-a-real-flag >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "unknown flag should exit 1"
  pass "git setup unknown flag ($DEVTOOLS_TEST_PROFILE)"
}

test_install_gh_branch() {
  local out
  out="$(
    PATH="$PATH" SETUP_NO_MAIN=1 /bin/bash -c '
      setup="$1"
      set -- --dry-run
      # shellcheck disable=SC1090
      source "$setup"
      DRY_RUN=true
      install_gh
    ' _ "$SETUP_SH" 2>&1
  )" || {
    echo "FAIL: install_gh dry-run failed: $out" >&2
    return 1
  }

  case "$DEVTOOLS_TEST_PROFILE" in
    linux_centos)
      assert_contains "$out" "cli.github.com/packages/rpm/gh-cli.repo" "centos gh repo"
      assert_contains "$out" "dnf install -y gh" "centos dnf install gh"
      ;;
    linux_ubuntu)
      assert_contains "$out" "apt-get install -y gh" "ubuntu apt install gh"
      ;;
    macos)
      assert_contains "$out" "brew install gh" "macos brew install gh"
      ;;
  esac
  pass "git install_gh branch ($DEVTOOLS_TEST_PROFILE)"
}

test_install_delta_branch() {
  local out
  out="$(
    PATH="$PATH" SETUP_NO_MAIN=1 /bin/bash -c '
      setup="$1"
      set -- --dry-run
      # shellcheck disable=SC1090
      source "$setup"
      DRY_RUN=true
      SKIP_DELTA=false
      install_delta
    ' _ "$SETUP_SH" 2>&1
  )" || {
    echo "FAIL: install_delta dry-run failed: $out" >&2
    return 1
  }

  case "$DEVTOOLS_TEST_PROFILE" in
    linux_centos)
      assert_contains "$out" "dnf install -y git-delta" "centos dnf install delta"
      ;;
    linux_ubuntu)
      assert_contains "$out" "apt-get install -y git-delta" "ubuntu apt install delta"
      ;;
    macos)
      assert_contains "$out" "brew install git-delta" "macos brew install delta"
      ;;
  esac
  pass "git install_delta branch ($DEVTOOLS_TEST_PROFILE)"
}

test_setup_dry_run_skip_writes() {
  local out
  out="$(bash "$SETUP_SH" --dry-run --skip-delta --skip-subcmd --skip-config --skip-alias 2>&1)" || {
    echo "FAIL: setup dry-run failed: $out" >&2
    return 1
  }
  assert_contains "$out" "试运行" "dry-run banner"
  # Should not create git config under isolated HOME
  if [[ -f "$HOME/.gitconfig" ]]; then
    echo "FAIL: dry-run wrote $HOME/.gitconfig" >&2
    return 1
  fi
  pass "git setup dry-run skips writes ($DEVTOOLS_TEST_PROFILE)"
}

test_subcmd_dry_run() {
  local out
  out="$(bash "$SUBCMD_SH" --dry-run 2>&1)" || {
    echo "FAIL: sub-command dry-run failed: $out" >&2
    return 1
  }
  assert_contains "$out" "DRY RUN" "subcmd dry-run marker"
  [[ ! -e "$HOME/.local/bin/git-rb" ]] || {
    echo "FAIL: dry-run installed git-rb" >&2
    return 1
  }
  pass "git sub-command --dry-run ($DEVTOOLS_TEST_PROFILE)"
}

test_subcmd_install_idempotent() {
  bash "$SUBCMD_SH" >/dev/null
  assert_file_exists "$HOME/.local/bin/git-rb"
  assert_file_exists "$HOME/.local/bin/git-review"
  bash "$SUBCMD_SH" >/dev/null
  assert_file_exists "$HOME/.local/bin/git-wc"
  pass "git sub-command install idempotent ($DEVTOOLS_TEST_PROFILE)"
}

test_config_credential_helper() {
  local out
  # config.sh prompts for name/email even in dry-run; feed defaults.
  out="$(printf '\n\n' | bash "$CONFIG_SH" --dry-run 2>&1)" || {
    echo "FAIL: config dry-run failed: $out" >&2
    return 1
  }
  case "$DEVTOOLS_TEST_PROFILE" in
    macos)
      assert_contains "$out" "credential.helper = osxkeychain" "macos keychain helper"
      ;;
    linux_ubuntu|linux_centos)
      assert_contains "$out" "credential.helper = cache --timeout=86400" "linux cache helper"
      ;;
  esac
  if [[ -f "$HOME/.gitconfig" ]]; then
    echo "FAIL: config dry-run wrote $HOME/.gitconfig" >&2
    return 1
  fi
  pass "git config credential.helper ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_unknown_flag
test_install_gh_branch
test_install_delta_branch
test_setup_dry_run_skip_writes
test_subcmd_dry_run
test_subcmd_install_idempotent
test_config_credential_helper

echo "PASS: git suite complete ($DEVTOOLS_TEST_PROFILE)"
