#!/usr/bin/env bash
# Python installer CLI / dry-run suite (fake OS profile).
set -euo pipefail

SETUP_SH="$MODULE_ROOT/setup.sh"

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "dry-run" "python setup --help mentions dry-run"
  assert_contains "$out" "--skip-pyenv" "python setup --help mentions skip-pyenv"
  assert_contains "$out" "--skip-uv" "python setup --help mentions skip-uv"
  pass "python setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_unknown_flag() {
  local rc=0
  bash "$SETUP_SH" --not-a-real-flag >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "unknown flag should exit 1"
  pass "python setup unknown flag ($DEVTOOLS_TEST_PROFILE)"
}

test_dry_run() {
  local out
  out="$(bash "$SETUP_SH" --dry-run --skip-ai-packages 2>&1)" || {
    echo "FAIL: python setup --dry-run failed: $out" >&2
    return 1
  }
  assert_contains "$out" "DRY-RUN" "python dry-run announces preview mode"
  pass "python setup --dry-run ($DEVTOOLS_TEST_PROFILE)"
}

source_setup() {
  # shellcheck disable=SC1090
  SETUP_NO_MAIN=1 source "$SETUP_SH"
}

PYENV_MARKER='# pyenv init (added by devtools/languages/python/setup.sh)'

test_pyenv_rc_both_shells() {
  local fakehome
  fakehome="$(mktemp -d)"
  (
    export HOME="$fakehome"
    DRY_RUN=false
    source_setup
    printf '# existing bashrc\n' > "$HOME/.bashrc"
    printf '# existing zshrc\n' > "$HOME/.zshrc"
    configure_pyenv_shell >/dev/null
    assert_contains "$(cat "$HOME/.bashrc")" "$PYENV_MARKER" "pyenv init written to .bashrc"
    assert_contains "$(cat "$HOME/.zshrc")" "$PYENV_MARKER" "pyenv init written to .zshrc"
    # rerun must not duplicate the managed block
    configure_pyenv_shell >/dev/null
    assert_eq "$(grep -cF "$PYENV_MARKER" "$HOME/.bashrc")" "1" "bashrc block not duplicated"
    assert_eq "$(grep -cF "$PYENV_MARKER" "$HOME/.zshrc")" "1" "zshrc block not duplicated"
  ) || { rm -rf "$fakehome"; return 1; }
  rm -rf "$fakehome"
  pass "pyenv init covers bashrc+zshrc idempotently ($DEVTOOLS_TEST_PROFILE)"
}

test_pyenv_rc_bash_only() {
  local fakehome
  fakehome="$(mktemp -d)"
  (
    export HOME="$fakehome"
    DRY_RUN=false
    source_setup
    printf '# existing bashrc\n' > "$HOME/.bashrc"
    configure_pyenv_shell >/dev/null
    assert_contains "$(cat "$HOME/.bashrc")" "$PYENV_MARKER" "pyenv init written to .bashrc"
    assert_eq "$([[ -f "$HOME/.zshrc" ]] && echo yes || echo no)" "no" "no .zshrc created on bash-only host"
  ) || { rm -rf "$fakehome"; return 1; }
  rm -rf "$fakehome"
  pass "pyenv init on bash-only host ($DEVTOOLS_TEST_PROFILE)"
}

test_pyenv_rc_dry_run_no_write() {
  local fakehome
  fakehome="$(mktemp -d)"
  (
    export HOME="$fakehome"
    DRY_RUN=true
    source_setup
    printf '# existing bashrc\n' > "$HOME/.bashrc"
    configure_pyenv_shell >/dev/null
    assert_eq "$(grep -cF "$PYENV_MARKER" "$HOME/.bashrc" || true)" "0" "dry-run must not touch rc files"
  ) || { rm -rf "$fakehome"; return 1; }
  rm -rf "$fakehome"
  pass "pyenv rc dry-run leaves files untouched ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_unknown_flag
test_dry_run
test_pyenv_rc_both_shells
test_pyenv_rc_bash_only
test_pyenv_rc_dry_run_no_write
echo "PASS: python suite complete ($DEVTOOLS_TEST_PROFILE)"
