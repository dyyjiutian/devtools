#!/usr/bin/env bash
# vim module suite — expects run_module_test.sh environment.
set -euo pipefail

SETUP_SH="$MODULE_ROOT/setup.sh"
# Install a fake vim that reports a given major.minor (and optional patch).
install_fake_vim() {
  local major_minor="$1"
  local patch="${2:-0}"
  mkdir -p "$FAKE_BIN"
  cat >"$FAKE_BIN/vim" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  cat <<VER
VIM - Vi IMproved ${major_minor} (fake for tests)
Included patches: 1-${patch}
VER
  exit 0
fi
exit 0
EOF
  chmod +x "$FAKE_BIN/vim"
  export PATH="$FAKE_BIN:$PATH"
}

source_setup() {
  # shellcheck disable=SC1090
  SETUP_NO_MAIN=1 source "$SETUP_SH"
}

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "--upgrade" "help mentions --upgrade"
  assert_contains "$out" "dry-run" "help mentions dry-run"
  pass "vim setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_unknown_flag() {
  local rc=0
  bash "$SETUP_SH" --not-a-real-flag >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "unknown flag should exit 1"
  pass "vim setup unknown flag ($DEVTOOLS_TEST_PROFILE)"
}

test_resolve_targets() {
  local target

  install_fake_vim "8.0" "1"
  source_setup
  target="$(resolve_vim_target)"
  assert_eq "$target" "8.2.5172" "8.x maps to VIM_8_TARGET"

  install_fake_vim "9.0" "1"
  # Re-source not required; resolve reads live vim
  target="$(resolve_vim_target)"
  assert_eq "$target" "9.2.0782" "9.x maps to VIM_9_TARGET"

  install_fake_vim "7.4" "1"
  target="$(resolve_vim_target)"
  assert_eq "$target" "9.2.0782" "<8 maps to VIM_9_TARGET"

  pass "vim resolve_vim_target ($DEVTOOLS_TEST_PROFILE)"
}

test_dry_run_upgrade_old_vim() {
  local out
  install_fake_vim "8.0" "1"

  out="$(
    DEVTOOLS_CACHE_DIR="${DEVTOOLS_CACHE_DIR:-$HOME/cache}" \
      bash "$SETUP_SH" --dry-run --upgrade 2>&1
  )" || {
    echo "FAIL: dry-run --upgrade failed: $out" >&2
    return 1
  }

  assert_contains "$out" "试运行" "dry-run marker"
  assert_contains "$out" "8.2.5172" "targets 8.2.5172 for Vim 8.0"

  case "$DEVTOOLS_TEST_PROFILE" in
    macos)
      assert_contains "$out" "brew" "macos tries brew"
      ;;
    linux_ubuntu)
      assert_contains "$out" "apt-get" "ubuntu tries apt-get"
      ;;
    linux_centos|linux_alinux3|linux_alinux4)
      # dnf or yum upgrade path
      if ! echo "$out" | grep -qE 'dnf|yum'; then
        echo "FAIL: expected dnf/yum in output" >&2
        return 1
      fi
      ;;
  esac

  assert_contains "$out" "configure --prefix=" "falls back to source build dry-run"
  assert_contains "$out" "[试运行] tar xf" "source extract is dry-run"

  pass "vim dry-run --upgrade old 8.0 ($DEVTOOLS_TEST_PROFILE)"
}

test_skip_coc_without_upgrade() {
  local out
  install_fake_vim "7.4" "1"

  out="$(bash "$SETUP_SH" --dry-run 2>&1)" || {
    echo "FAIL: dry-run without upgrade failed: $out" >&2
    return 1
  }

  assert_contains "$out" "Skipping coc.nvim" "skips coc when old and no --upgrade"
  assert_contains "$out" "--upgrade" "hints at --upgrade"
  assert_not_contains "$out" "configure --prefix=" "does not source-build without --upgrade"

  pass "vim skip coc without --upgrade ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_unknown_flag
test_resolve_targets
test_dry_run_upgrade_old_vim
test_skip_coc_without_upgrade

echo "PASS: vim suite complete ($DEVTOOLS_TEST_PROFILE)"
