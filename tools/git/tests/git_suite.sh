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

SPARSE_CLONE="$MODULE_ROOT/bin/git-sparse-clone"

make_sparse_fixture() {
  # Creates bare remote at $1 with README, devtools/a.txt, scripts/b.txt
  local bare="$1"
  local src
  src="$(mktemp -d "${TMPDIR:-/tmp}/sparse-src.XXXXXX")"
  mkdir -p "$src/devtools" "$src/scripts"
  printf 'root\n' >"$src/README"
  printf 'a\n' >"$src/devtools/a.txt"
  printf 'b\n' >"$src/scripts/b.txt"
  git -C "$src" init -b main >/dev/null
  git -C "$src" config user.email "test@example.com"
  git -C "$src" config user.name "Test"
  git -C "$src" add .
  git -C "$src" commit -m init >/dev/null
  git clone --bare "$src" "$bare" >/dev/null 2>&1
  rm -rf "$src"
}

test_sparse_clone_help() {
  local out
  out="$(bash "$SPARSE_CLONE" --help 2>&1)"
  assert_contains "$out" "sparse-clone" "help mentions sparse-clone"
  assert_contains "$out" "--append" "help mentions append"
  pass "git sparse-clone --help ($DEVTOOLS_TEST_PROFILE)"
}

test_sparse_clone_rejects_glob() {
  local rc=0
  bash "$SPARSE_CLONE" --dry-run "https://example.com/repo.git" 'src/**' >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "glob path should fail"
  pass "git sparse-clone rejects glob ($DEVTOOLS_TEST_PROFILE)"
}

test_sparse_clone_rejects_negation() {
  local rc=0
  bash "$SPARSE_CLONE" --dry-run "https://example.com/repo.git" '!*.jar' >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "negation path should fail"
  pass "git sparse-clone rejects negation ($DEVTOOLS_TEST_PROFILE)"
}

test_sparse_clone_append_requires_paths() {
  local rc=0
  bash "$SPARSE_CLONE" --append >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" "append without paths should fail"
  pass "git sparse-clone append requires paths ($DEVTOOLS_TEST_PROFILE)"
}

test_sparse_clone_dry_run_no_dir() {
  local bare dest out
  bare="$(mktemp -d "${TMPDIR:-/tmp}/sparse-bare.XXXXXX")/repo.git"
  mkdir -p "$(dirname "$bare")"
  make_sparse_fixture "$bare"
  dest="$(mktemp -d "${TMPDIR:-/tmp}/sparse-dest.XXXXXX")/out"
  out="$(bash "$SPARSE_CLONE" --dry-run --dir "$dest" "$bare" devtools 2>&1)" || {
    echo "FAIL: dry-run failed: $out" >&2
    return 1
  }
  assert_contains "$out" "DRY RUN" "dry-run marker"
  [[ ! -e "$dest" ]] || {
    echo "FAIL: dry-run created $dest" >&2
    return 1
  }
  rm -rf "$(dirname "$bare")" "$(dirname "$dest")"
  pass "git sparse-clone --dry-run ($DEVTOOLS_TEST_PROFILE)"
}

test_sparse_clone_root_only_and_paths_and_append() {
  local bare work root_only with_paths
  bare="$(mktemp -d "${TMPDIR:-/tmp}/sparse-bare.XXXXXX")/repo.git"
  mkdir -p "$(dirname "$bare")"
  make_sparse_fixture "$bare"
  work="$(mktemp -d "${TMPDIR:-/tmp}/sparse-work.XXXXXX")"

  root_only="$work/root-only"
  bash "$SPARSE_CLONE" --dir "$root_only" --force "$bare" >/dev/null 2>&1
  assert_file_exists "$root_only/README"
  [[ ! -e "$root_only/devtools" ]] || {
    echo "FAIL: root-only clone should omit subdirs" >&2
    return 1
  }

  with_paths="$work/with-paths"
  bash "$SPARSE_CLONE" --dir "$with_paths" --force "$bare" devtools >/dev/null 2>&1
  assert_file_exists "$with_paths/devtools/a.txt"
  [[ ! -e "$with_paths/scripts" ]] || {
    echo "FAIL: path clone should omit scripts/" >&2
    return 1
  }

  bash "$SPARSE_CLONE" --append --dir "$with_paths" scripts >/dev/null 2>&1
  assert_file_exists "$with_paths/scripts/b.txt"

  rm -rf "$(dirname "$bare")" "$work"
  pass "git sparse-clone clone/append ($DEVTOOLS_TEST_PROFILE)"
}

test_subcmd_installs_sparse_clone() {
  bash "$SUBCMD_SH" >/dev/null
  assert_file_exists "$HOME/.local/bin/git-sparse-clone"
  assert_file_exists "$HOME/.local/share/man/man1/git-sparse-clone.1"
  pass "git sub-command installs sparse-clone ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_unknown_flag
test_install_gh_branch
test_install_delta_branch
test_setup_dry_run_skip_writes
test_subcmd_dry_run
test_subcmd_install_idempotent
test_config_credential_helper
test_sparse_clone_help
test_sparse_clone_rejects_glob
test_sparse_clone_rejects_negation
test_sparse_clone_append_requires_paths
test_sparse_clone_dry_run_no_dir
test_sparse_clone_root_only_and_paths_and_append
test_subcmd_installs_sparse_clone

echo "PASS: git suite complete ($DEVTOOLS_TEST_PROFILE)"
