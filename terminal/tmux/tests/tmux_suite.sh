#!/usr/bin/env bash
# tmux module suite — expects run_module_test.sh environment.
set -euo pipefail

SETUP_SH="$MODULE_ROOT/setup.sh"
TMUX_CONF="$MODULE_ROOT/tmux.conf"

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "install-bin-only" "help mentions --install-bin-only"
  assert_contains "$out" "dry-run" "help mentions dry-run"
  pass "tmux setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_unknown_flag() {
  local rc=0
  bash "$SETUP_SH" --not-a-real-flag >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "unknown flag should exit 1"
  pass "tmux setup unknown flag ($DEVTOOLS_TEST_PROFILE)"
}

test_dry_run_branch() {
  local out
  # Avoid TPM / plugin side effects; bin-only still exercises install_tmux branches.
  out="$(bash "$SETUP_SH" --dry-run --install-bin-only 2>&1)" || {
    echo "FAIL: tmux dry-run failed: $out" >&2
    return 1
  }

  case "$DEVTOOLS_TEST_PROFILE" in
    macos)
      assert_contains "$out" "macos" "detects macos"
      assert_contains "$out" "brew install tmux" "macos brew install"
      ;;
    linux_ubuntu|linux_centos)
      assert_contains "$out" "linux" "detects linux"
      assert_contains "$out" "试运行" "dry-run marker"
      # Source build path prints configure/make intent when cache miss
      assert_contains "$out" "configure --prefix=" "linux source build dry-run"
      ;;
  esac
  pass "tmux dry-run branch ($DEVTOOLS_TEST_PROFILE)"
}

test_cache_hit_no_curl() {
  # Cache hit only applies to Linux source installs.
  if [[ "$DEVTOOLS_TEST_PROFILE" == "macos" ]]; then
    pass "tmux cache hit skipped on macos"
    return 0
  fi

  local tarball="tmux-3.7b.tar.gz"
  # Minimal fake archive content is enough for dry-run (no extract).
  : >"$DEVTOOLS_CACHE_DIR/binaries/$tarball"

  local out
  out="$(
    TMUX_VERSION=3.7b \
      DEVTOOLS_CACHE_DIR="$DEVTOOLS_CACHE_DIR" \
      bash "$SETUP_SH" --dry-run --install-bin-only 2>&1
  )" || {
    echo "FAIL: cache-hit dry-run failed: $out" >&2
    return 1
  }
  assert_contains "$out" "使用本地缓存" "mentions local cache"
  assert_not_contains "$out" "curl -fL" "should not curl on cache hit"
  pass "tmux cache hit avoids curl ($DEVTOOLS_TEST_PROFILE)"
}

test_deploy_config() {
  local out
  # Seed an existing non-symlink config to exercise backup.
  printf 'old-config\n' >"$HOME/.tmux.conf"

  out="$(
    SETUP_NO_MAIN=1 /bin/bash -c '
      setup="$1"
      set -- --dry-run
      # shellcheck disable=SC1090
      source "$setup"
      DRY_RUN=false
      deploy_config
    ' _ "$SETUP_SH" 2>&1
  )" || {
    echo "FAIL: deploy_config failed: $out" >&2
    return 1
  }

  assert_symlink "$HOME/.tmux.conf" "tmux.conf should be symlink"
  local target
  target="$(readlink "$HOME/.tmux.conf")"
  assert_eq "$target" "$TMUX_CONF" "symlink target"
  local backups
  backups="$(find "$HOME" -maxdepth 1 -name '.tmux.conf.bak.*' | wc -l | tr -d ' ')"
  assert_eq "$backups" "1" "exactly one backup created"
  pass "tmux deploy_config backup+symlink ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_unknown_flag
test_dry_run_branch
test_cache_hit_no_curl
test_deploy_config

echo "PASS: tmux suite complete ($DEVTOOLS_TEST_PROFILE)"
