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
  assert_contains "$out" "--upgrade" "help mentions --upgrade"
  pass "tmux setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_unknown_flag() {
  local rc=0
  bash "$SETUP_SH" --not-a-real-flag >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "unknown flag should exit 1"
  pass "tmux setup unknown flag ($DEVTOOLS_TEST_PROFILE)"
}

test_dry_run_default_no_upgrade() {
  # No fake tmux present in the hermetic PATH -> treated as missing/old.
  # Without --upgrade the script must NOT force a binary install/rebuild.
  local out
  out="$(bash "$SETUP_SH" --dry-run --install-bin-only 2>&1)" || {
    echo "FAIL: tmux dry-run (no upgrade) failed: $out" >&2
    return 1
  }

  assert_contains "$out" "--upgrade" "hints at --upgrade when tmux missing/old"
  assert_not_contains "$out" "configure --prefix=" "no source rebuild without --upgrade"
  assert_not_contains "$out" "brew install tmux" "no brew install without --upgrade"
  assert_not_contains "$out" "brew upgrade tmux" "no brew upgrade without --upgrade"
  pass "tmux dry-run default (no --upgrade) skips forced install ($DEVTOOLS_TEST_PROFILE)"
}

test_dry_run_upgrade_branch() {
  local out
  # Avoid TPM / plugin side effects; bin-only still exercises install_tmux branches.
  out="$(bash "$SETUP_SH" --upgrade --dry-run --install-bin-only 2>&1)" || {
    echo "FAIL: tmux --upgrade dry-run failed: $out" >&2
    return 1
  }

  case "$DEVTOOLS_TEST_PROFILE" in
    macos)
      assert_contains "$out" "macos" "detects macos"
      assert_contains "$out" "brew install tmux" "macos brew install"
      ;;
    linux_ubuntu|linux_centos|linux_alinux3|linux_alinux4)
      assert_contains "$out" "linux" "detects linux"
      assert_contains "$out" "试运行" "dry-run marker"
      # Package-manager-first, then fallback to source build intent.
      assert_contains "$out" "包管理器升级" "linux tries package manager first"
      assert_contains "$out" "configure --prefix=" "linux source build dry-run fallback"
      ;;
  esac
  pass "tmux --upgrade dry-run branch ($DEVTOOLS_TEST_PROFILE)"
}

test_no_upgrade_old_tmux_skips_rebuild() {
  # Seed an old managed tmux under TMUX_PREFIX (~/.local by default) to simulate
  # an existing, too-old install. Without --upgrade this must NOT trigger a rebuild.
  local bindir="$HOME/.local/bin"
  mkdir -p "$bindir"
  cat >"$bindir/tmux" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-V" ]]; then echo "tmux 2.7"; exit 0; fi
exit 0
EOF
  chmod +x "$bindir/tmux"

  local out
  out="$(bash "$SETUP_SH" --dry-run --install-bin-only 2>&1)" || {
    echo "FAIL: tmux no-upgrade old-tmux dry-run failed: $out" >&2
    rm -f "$bindir/tmux"
    return 1
  }

  assert_contains "$out" "2.7" "detects existing old tmux version"
  assert_contains "$out" "--upgrade" "points to --upgrade for the old tmux"
  assert_not_contains "$out" "configure --prefix=" "old tmux without --upgrade does not force source rebuild"
  assert_not_contains "$out" "brew install tmux" "old tmux without --upgrade does not force brew install"
  assert_not_contains "$out" "brew upgrade tmux" "old tmux without --upgrade does not force brew upgrade"

  rm -f "$bindir/tmux"
  pass "tmux no-upgrade + old tmux skips rebuild ($DEVTOOLS_TEST_PROFILE)"
}

test_no_upgrade_already_target_skips_install() {
  # Seed a managed tmux already at/above target -> should skip entirely, no flags needed.
  local bindir="$HOME/.local/bin"
  mkdir -p "$bindir"
  cat >"$bindir/tmux" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-V" ]]; then echo "tmux 3.7b"; exit 0; fi
exit 0
EOF
  chmod +x "$bindir/tmux"

  local out
  out="$(bash "$SETUP_SH" --dry-run --install-bin-only 2>&1)" || {
    echo "FAIL: tmux already-target dry-run failed: $out" >&2
    rm -f "$bindir/tmux"
    return 1
  }

  assert_contains "$out" "已满足目标" "reports target already satisfied"
  assert_not_contains "$out" "configure --prefix=" "already-target does not rebuild"
  assert_not_contains "$out" "brew install tmux" "already-target does not brew install"
  assert_not_contains "$out" "brew upgrade tmux" "already-target does not brew upgrade"

  rm -f "$bindir/tmux"
  pass "tmux already at target skips install ($DEVTOOLS_TEST_PROFILE)"
}

test_cache_hit_no_curl() {
  # Cache hit only applies to Linux source installs, which now require --upgrade.
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
      bash "$SETUP_SH" --upgrade --dry-run --install-bin-only 2>&1
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

  assert_file_exists "$HOME/.tmux.conf" "tmux.conf should exist"
  if [[ -L "$HOME/.tmux.conf" ]]; then
    echo "FAIL: tmux.conf should be a regular file, not a symlink" >&2
    return 1
  fi
  assert_eq "$(cat "$HOME/.tmux.conf")" "$(cat "$TMUX_CONF")" "copied content matches source"
  local backups
  backups="$(find "$HOME" -maxdepth 1 -name '.tmux.conf.bak.*' | wc -l | tr -d ' ')"
  assert_eq "$backups" "1" "exactly one backup created"
  pass "tmux deploy_config backup+copy ($DEVTOOLS_TEST_PROFILE)"
}

test_clipboard_bindings() {
  local conf
  conf="$(cat "$TMUX_CONF")"
  assert_contains "$conf" 'uname | grep -qi Darwin' "clipboard binding is OS-conditional"
  assert_contains "$conf" 'copy-pipe-and-cancel "pbcopy"' "macOS path uses pbcopy"
  assert_contains "$conf" 'set -s set-clipboard on' "Linux path enables OSC52"
  assert_contains "$conf" 'copy-selection-and-cancel' "Linux path uses copy-selection"
  pass "tmux.conf clipboard OS split ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_unknown_flag
test_clipboard_bindings
test_dry_run_default_no_upgrade
test_dry_run_upgrade_branch
test_no_upgrade_old_tmux_skips_rebuild
test_no_upgrade_already_target_skips_install
test_cache_hit_no_curl
test_deploy_config

echo "PASS: tmux suite complete ($DEVTOOLS_TEST_PROFILE)"
