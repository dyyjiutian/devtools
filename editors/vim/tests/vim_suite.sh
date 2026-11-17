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

# Fake node reporting a given version (empty string = node not installed).
install_fake_node() {
  local version="$1"
  mkdir -p "$FAKE_BIN"
  # The harness links host node into FAKE_BIN; drop the symlink first so we
  # never write through it into the host toolchain.
  rm -f "$FAKE_BIN/node"
  if [[ -z "$version" ]]; then
    return 0
  fi
  cat >"$FAKE_BIN/node" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "-v" || "\${1:-}" == "--version" ]]; then
  echo "${version}"
  exit 0
fi
exit 0
EOF
  chmod +x "$FAKE_BIN/node"
  export PATH="$FAKE_BIN:$PATH"
}

test_check_node_version() {
  local status
  source_setup

  install_fake_node "v18.19.1"
  status="$(check_node_version)"
  assert_eq "$status" "old" "node 18 is too old for coc release"

  install_fake_node "v22.14.9"
  status="$(check_node_version)"
  assert_eq "$status" "old" "node 22.14 is below the 22.15 floor"

  install_fake_node "v22.15.0"
  status="$(check_node_version)"
  assert_eq "$status" "ok" "node 22.15.0 meets the coc floor"

  install_fake_node "v24.1.0"
  status="$(check_node_version)"
  assert_eq "$status" "ok" "node 24 meets the coc floor"

  install_fake_node ""
  status="$(check_node_version)"
  assert_eq "$status" "missing" "absent node is reported as missing"

  pass "vim check_node_version ($DEVTOOLS_TEST_PROFILE)"
}

test_skip_coc_old_node() {
  local out
  install_fake_vim "9.2" "1719"
  install_fake_node "v18.19.1"

  out="$(bash "$SETUP_SH" --dry-run 2>&1)" || {
    echo "FAIL: dry-run with old node failed: $out" >&2
    return 1
  }

  assert_contains "$out" "Skipping coc.nvim" "coc must be skipped when node is too old"
  assert_contains "$out" "22.15" "warn must state the required node version"
  pass "vim skips coc on old node ($DEVTOOLS_TEST_PROFILE)"
}

test_deps_keep_existing_node() {
  if [[ "$DEVTOOLS_TEST_PROFILE" == "macos" ]]; then
    pass "vim deps keep existing node (macos uses brew, skipped)"
    return 0
  fi
  local out
  source_setup
  DRY_RUN=true

  install_fake_node "v22.15.0"
  out="$(install_deps_linux 2>&1)"
  assert_contains "$out" "nodejs already present" "existing node must be kept"
  assert_not_contains "$out" "install -y nodejs" "package manager must not replace an existing node"

  install_fake_node ""
  out="$(install_deps_linux 2>&1)"
  if ! echo "$out" | grep -qE '(apt-get|dnf|yum) install -y nodejs'; then
    echo "FAIL: nodejs should be installed when node is absent: $out" >&2
    DRY_RUN=false
    return 1
  fi

  DRY_RUN=false
  pass "vim deps keep existing node ($DEVTOOLS_TEST_PROFILE)"
}

test_vimrc_coc_node_gate() {
  local vimrc
  vimrc="$(cat "$MODULE_ROOT/vimrc")"
  assert_contains "$vimrc" "g:coc_enabled" "vimrc computes a coc enable flag"
  assert_contains "$vimrc" "node -v" "vimrc inspects the node version"
  assert_contains "$vimrc" "if g:coc_enabled" "coc settings are gated on the flag"
  assert_contains "$vimrc" "AutoComplPop" "fallback completion remains available"
  pass "vimrc gates coc on node version ($DEVTOOLS_TEST_PROFILE)"
}

test_vim_ops_bounded() {
  local ops
  ops="$(cat "$MODULE_ROOT/tests/e2e/vim_ops_suite.sh")"
  assert_contains "$ops" "timeout" "vim e2e invocations must be time-bounded"
  assert_contains "$ops" "run_vim" "vim e2e uses a bounded vim wrapper"
  pass "vim e2e invocations are bounded ($DEVTOOLS_TEST_PROFILE)"
}

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "--upgrade" "help mentions --upgrade"
  assert_contains "$out" "dry-run" "help mentions dry-run"
  pass "vim setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_vimrc_oscyank_linux_only() {
  local vimrc
  vimrc="$(cat "$MODULE_ROOT/vimrc")"
  assert_contains "$vimrc" "ojroques/vim-oscyank" "declares vim-oscyank"
  assert_contains "$vimrc" "has('unix') && !has('macunix')" "oscyank gated to Linux"
  assert_contains "$vimrc" "OSCYankOperator" "maps OSCYank operator"
  pass "vimrc oscyank Linux-only ($DEVTOOLS_TEST_PROFILE)"
}

test_vimrc_git_perf_large_repo() {
  local vimrc
  vimrc="$(cat "$MODULE_ROOT/vimrc")"
  assert_contains "$vimrc" "airline#extensions#branch#enabled = 0" \
    "disables airline branch extension"
  assert_contains "$vimrc" "gitgutter#utility#base_path" \
    "overrides gitgutter base_path"
  assert_contains "$vimrc" "diff --diff-filter=R --name-status" \
    "documents whole-repo rename scan being skipped"
  assert_contains "$vimrc" "gitgutter#utility#repo_path(a:bufnr, 0)" \
    "base_path uses current file path only"
  pass "vimrc git perf for large repos ($DEVTOOLS_TEST_PROFILE)"
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
  assert_eq "$target" "9.2.0782" "8.x maps to VIM_9_TARGET"

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
  assert_contains "$out" "9.2.0782" "targets 9.2.0782 for Vim 8.0"

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

test_version_ge_leading_zeros() {
  # Vim tags zero-pad patches (9.2.0782); --version reports unpadded (9.2.782).
  # ((0782)) is invalid octal in bash — version_ge must force decimal.
  local out rc
  source_setup

  rc=0
  out="$(version_ge "9.2.782" "9.2.0782" 2>&1)" || rc=$?
  assert_eq "$rc" "0" "version_ge should not fail on leading-zero patch"
  assert_eq "$out" "ge" "9.2.782 >= 9.2.0782 (numeric)"

  rc=0
  out="$(version_ge "9.2.0782" "9.2.782" 2>&1)" || rc=$?
  assert_eq "$rc" "0" "version_ge reverse should not fail"
  assert_eq "$out" "ge" "9.2.0782 >= 9.2.782 (numeric)"

  rc=0
  out="$(version_ge "9.2.100" "9.2.0782" 2>&1)" || rc=$?
  assert_eq "$rc" "0" "version_ge lt path should not fail"
  assert_eq "$out" "lt" "9.2.100 < 9.2.0782"

  pass "vim version_ge leading zeros ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_vimrc_oscyank_linux_only
test_vimrc_git_perf_large_repo
test_vimrc_coc_node_gate
test_vim_ops_bounded
test_unknown_flag
test_resolve_targets
test_version_ge_leading_zeros
test_check_node_version
test_dry_run_upgrade_old_vim
test_skip_coc_without_upgrade
test_skip_coc_old_node
test_deps_keep_existing_node

echo "PASS: vim suite complete ($DEVTOOLS_TEST_PROFILE)"
