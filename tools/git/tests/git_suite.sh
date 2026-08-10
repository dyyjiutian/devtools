#!/usr/bin/env bash
# Git module suite — expects run_module_test.sh environment:
#   MODULE_ROOT, HOME, DEVTOOLS_TEST_PROFILE, assert helpers, profile fakes on PATH
set -euo pipefail

SETUP_SH="$MODULE_ROOT/setup.sh"
SUBCMD_SH="$MODULE_ROOT/scripts/sub-command.sh"
CONFIG_SH="$MODULE_ROOT/scripts/config.sh"
GIT_BC="$MODULE_ROOT/bin/git-bc"

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "dry-run" "setup --help mentions dry-run"
  assert_contains "$out" "--skip-gh" "setup --help mentions skip-gh"
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
    linux_centos|linux_alinux3|linux_alinux4)
      assert_contains "$out" "cli.github.com/packages/rpm/gh-cli.repo" "dnf gh repo"
      assert_contains "$out" "dnf install -y gh" "dnf install gh"
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

test_skip_gh() {
  local out
  out="$(bash "$SETUP_SH" --dry-run --skip-gh --skip-delta --skip-subcmd --skip-config --skip-alias 2>&1)" || {
    echo "FAIL: setup --skip-gh failed: $out" >&2
    return 1
  }
  assert_contains "$out" "跳过 GitHub CLI (gh) 安装" "skip-gh message"
  assert_not_contains "$out" "install -y gh" "skip-gh must avoid Linux gh install"
  assert_not_contains "$out" "brew install gh" "skip-gh must avoid macOS gh install"
  pass "git setup --skip-gh ($DEVTOOLS_TEST_PROFILE)"
}

test_install_delta_branch() {
  local out
  local os_release="$HOME/os-release-delta-branch"

  case "$DEVTOOLS_TEST_PROFILE" in
    linux_centos)
      printf 'ID=centos\nVERSION_ID=9\n' >"$os_release"
      ;;
    linux_alinux3)
      printf 'ID=alinux\nVERSION_ID=3\n' >"$os_release"
      ;;
    linux_alinux4)
      printf 'ID=alinux\nVERSION_ID=4\n' >"$os_release"
      ;;
    linux_ubuntu)
      printf 'ID=ubuntu\nVERSION_ID=24.04\nVERSION_CODENAME=noble\n' >"$os_release"
      ;;
    macos)
      : >"$os_release"
      ;;
  esac

  out="$(
    PATH="$PATH" SETUP_NO_MAIN=1 OS_RELEASE_FILE="$os_release" /bin/bash -c '
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
      assert_contains "$out" "mirrors.aliyun.com/epel/9/Everything" "centos aliyun EPEL"
      assert_contains "$out" "dnf" "centos dnf install delta"
      ;;
    linux_alinux3|linux_alinux4)
      assert_contains "$out" "dnf install -y git-delta" "ALinux dnf install delta"
      assert_not_contains "$out" "mirrors.aliyun.com/epel" "ALinux does not use CentOS EPEL mapping"
      ;;
    linux_ubuntu)
      assert_contains "$out" "mirrors.aliyun.com/ubuntu" "ubuntu aliyun APT"
      assert_contains "$out" "apt-get" "ubuntu apt install delta"
      assert_contains "$out" "Dir::State::lists=" "ubuntu temporary APT lists"
      ;;
    macos)
      assert_contains "$out" "brew install git-delta" "macos brew install delta"
      ;;
  esac
  pass "git install_delta branch ($DEVTOOLS_TEST_PROFILE)"
}

make_alt_linux_bin() {
  local alt_bin="$1"
  mkdir -p "$alt_bin"
  cp -R "$FAKE_BIN/." "$alt_bin/"
  rm -f "$alt_bin"/{apt,apt-get,dnf,yum,pacman,zypper,cargo,curl,sudo}
}

write_os_release() {
  local path="$1" id="$2" version="$3" codename="${4:-}"
  {
    printf 'ID=%s\n' "$id"
    printf 'VERSION_ID=%s\n' "$version"
    if [[ -n "$codename" ]]; then
      printf 'VERSION_CODENAME=%s\n' "$codename"
    fi
  } >"$path"
}

test_linux_ignores_other_package_managers() {
  case "$DEVTOOLS_TEST_PROFILE" in
    macos) return 0 ;;
  esac

  local alt_bin="$HOME/other-package-managers"
  local os_release="$HOME/os-release-other"
  local out
  make_alt_linux_bin "$alt_bin"
  write_os_release "$os_release" arch 1
  for tool in pacman zypper cargo; do
    _devtools_write_exec "$alt_bin/$tool" 'printf "UNEXPECTED package manager: %s\n" "$0" >&2; exit 97'
  done
  _devtools_write_exec "$alt_bin/uname" '
if [[ "${1:-}" == "-m" ]]; then printf "aarch64\n"; else printf "Linux\n"; fi
'

  out="$(
    PATH="$alt_bin" SETUP_NO_MAIN=1 OS_RELEASE_FILE="$os_release" DEVTOOLS_ARCH=aarch64 /bin/bash -c '
      setup="$1"
      set --
      # shellcheck disable=SC1090
      source "$setup"
      install_gh
      install_delta
    ' _ "$SETUP_SH" 2>&1
  )" || {
    echo "FAIL: alternative package manager test failed: $out" >&2
    return 1
  }

  assert_not_contains "$out" "UNEXPECTED package manager" "Linux must ignore pacman/zypper/cargo"
  assert_not_contains "$out" "pacman" "Linux output must not report pacman"
  assert_not_contains "$out" "zypper" "Linux output must not report zypper"
  assert_not_contains "$out" "cargo" "Linux output must not report cargo"
  pass "git Linux package managers limited to apt/dnf/yum ($DEVTOOLS_TEST_PROFILE)"
}

make_delta_install_bin() {
  local alt_bin="$1"
  make_alt_linux_bin "$alt_bin"
  _devtools_write_exec "$alt_bin/sudo" '
if [[ "${1:-}" == "install" && "${5:-}" == "/usr/local/bin/delta" ]]; then
  exec install -m 0755 "$4" "$HOME/installed-delta"
fi
exec "$@"
'
}

test_centos7_prefers_valid_delta_cache() {
  [[ "$DEVTOOLS_TEST_PROFILE" == "linux_centos" ]] || return 0

  local fixture="$REPO_ROOT/cache/binaries/delta-0.19.2-x86_64-unknown-linux-musl.tar.gz"
  local alt_bin="$HOME/centos7-cache-bin"
  local os_release="$HOME/os-release-centos7-cache"
  local out
  assert_file_exists "$fixture" "git-delta cache fixture"
  cp "$fixture" "$DEVTOOLS_CACHE_DIR/binaries/"
  make_delta_install_bin "$alt_bin"
  _devtools_write_exec "$alt_bin/yum" 'printf "yum %s\n" "$*" >&2; exit 1'
  _devtools_write_exec "$alt_bin/curl" 'touch "$HOME/curl-was-called"; exit 1'
  write_os_release "$os_release" centos 7

  out="$(
    PATH="$alt_bin" SETUP_NO_MAIN=1 OS_RELEASE_FILE="$os_release" DEVTOOLS_ARCH=x86_64 /bin/bash -c '
      setup="$1"
      set --
      # shellcheck disable=SC1090
      source "$setup"
      install_delta
    ' _ "$SETUP_SH" 2>&1
  )" || {
    echo "FAIL: CentOS 7 cached delta install failed: $out" >&2
    return 1
  }

  assert_contains "$out" "使用本地缓存" "CentOS 7 cache priority"
  assert_file_exists "$HOME/installed-delta" "cached delta installed"
  assert_contains "$("$HOME/installed-delta" --version)" "0.19.2" "installed delta version"
  [[ ! -e "$HOME/curl-was-called" ]] || {
    echo "FAIL: valid cache unexpectedly accessed network" >&2
    return 1
  }
  pass "git CentOS 7 prefers valid delta cache"
}

make_delta_download_curl() {
  local alt_bin="$1"
  _devtools_write_exec "$alt_bin/curl" '
printf "%s\n" "$*" >>"$HOME/curl.log"
out=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    out="$2"
    shift 2
  else
    shift
  fi
done
[[ -n "$out" ]]
cp "$DELTA_FIXTURE_ARCHIVE" "$out"
'
}

run_centos7_download_case() {
  local cache_state="$1"
  local fixture="$REPO_ROOT/cache/binaries/delta-0.19.2-x86_64-unknown-linux-musl.tar.gz"
  local alt_bin="$HOME/centos7-${cache_state}-bin"
  local os_release="$HOME/os-release-centos7-${cache_state}"
  local archive="$DEVTOOLS_CACHE_DIR/binaries/delta-0.19.2-x86_64-unknown-linux-musl.tar.gz"
  local out
  rm -f "$HOME/installed-delta" "$HOME/curl.log" "$archive"
  if [[ "$cache_state" == "corrupt" ]]; then
    printf 'corrupt\n' >"$archive"
  fi
  make_delta_install_bin "$alt_bin"
  _devtools_write_exec "$alt_bin/yum" 'printf "yum %s\n" "$*" >&2; exit 1'
  make_delta_download_curl "$alt_bin"
  write_os_release "$os_release" centos 7

  out="$(
    PATH="$alt_bin" SETUP_NO_MAIN=1 OS_RELEASE_FILE="$os_release" DEVTOOLS_ARCH=x86_64 \
      DELTA_FIXTURE_ARCHIVE="$fixture" /bin/bash -c '
        setup="$1"
        set --
        # shellcheck disable=SC1090
        source "$setup"
        install_delta
      ' _ "$SETUP_SH" 2>&1
  )" || {
    echo "FAIL: CentOS 7 ${cache_state} cache download failed: $out" >&2
    return 1
  }

  if [[ "$cache_state" == "corrupt" ]]; then
    assert_contains "$out" "校验失败" "corrupt cache rejection"
  fi
  assert_contains "$(cat "$HOME/curl.log")" \
    "https://github.com/dandavison/delta/releases/download/0.19.2/delta-0.19.2-x86_64-unknown-linux-musl.tar.gz" \
    "fixed git-delta download URL"
  assert_file_exists "$HOME/installed-delta" "downloaded delta installed"
  assert_contains "$("$HOME/installed-delta" --version)" "0.19.2" "downloaded delta version"
}

test_centos7_rejects_corrupt_cache_then_downloads() {
  [[ "$DEVTOOLS_TEST_PROFILE" == "linux_centos" ]] || return 0
  run_centos7_download_case corrupt
  pass "git CentOS 7 rejects corrupt delta cache"
}

test_centos7_downloads_when_cache_missing() {
  [[ "$DEVTOOLS_TEST_PROFILE" == "linux_centos" ]] || return 0
  run_centos7_download_case missing
  pass "git CentOS 7 downloads delta when cache is missing"
}

test_centos7_non_x86_skips_static_delta() {
  [[ "$DEVTOOLS_TEST_PROFILE" == "linux_centos" ]] || return 0

  local alt_bin="$HOME/centos7-arm-bin"
  local os_release="$HOME/os-release-centos7-arm"
  local out
  make_alt_linux_bin "$alt_bin"
  _devtools_write_exec "$alt_bin/yum" 'printf "yum %s\n" "$*" >&2; exit 1'
  _devtools_write_exec "$alt_bin/curl" 'touch "$HOME/arm-curl-was-called"; exit 1'
  _devtools_write_exec "$alt_bin/sudo" 'exec "$@"'
  write_os_release "$os_release" centos 7

  out="$(
    PATH="$alt_bin" SETUP_NO_MAIN=1 OS_RELEASE_FILE="$os_release" DEVTOOLS_ARCH=aarch64 /bin/bash -c '
      setup="$1"
      set --
      # shellcheck disable=SC1090
      source "$setup"
      install_delta
    ' _ "$SETUP_SH" 2>&1
  )" || {
    echo "FAIL: CentOS 7 non-x86 delta fallback failed: $out" >&2
    return 1
  }
  [[ ! -e "$HOME/arm-curl-was-called" ]] || {
    echo "FAIL: non-x86 architecture used x86_64 static archive" >&2
    return 1
  }
  pass "git CentOS 7 non-x86 skips x86_64 static delta"
}

test_epel_failure_falls_back_to_system_repo() {
  [[ "$DEVTOOLS_TEST_PROFILE" == "linux_centos" ]] || return 0

  local alt_bin="$HOME/epel-fallback-bin"
  local os_release="$HOME/os-release-epel-fallback"
  local tmp_root="$HOME/epel-tmp"
  local out log
  make_alt_linux_bin "$alt_bin"
  mkdir -p "$tmp_root"
  _devtools_write_exec "$alt_bin/dnf" '
printf "%s\n" "$*" >>"$HOME/dnf.log"
if [[ "$*" == *"--setopt=reposdir="* ]]; then exit 1; fi
exit 0
'
  _devtools_write_exec "$alt_bin/sudo" 'exec "$@"'
  write_os_release "$os_release" rocky 9

  out="$(
    PATH="$alt_bin" TMPDIR="$tmp_root" SETUP_NO_MAIN=1 OS_RELEASE_FILE="$os_release" /bin/bash -c '
      setup="$1"
      set --
      # shellcheck disable=SC1090
      source "$setup"
      install_delta
    ' _ "$SETUP_SH" 2>&1
  )" || {
    echo "FAIL: EPEL fallback test failed: $out" >&2
    return 1
  }
  log="$(cat "$HOME/dnf.log")"
  assert_contains "$log" "--setopt=reposdir=" "temporary EPEL repo attempt"
  assert_contains "$log" "install -y git-delta" "system repository fallback"
  if find "$tmp_root" -mindepth 1 -print -quit | grep -q .; then
    echo "FAIL: temporary EPEL files were not cleaned up" >&2
    return 1
  fi
  pass "git EPEL failure falls back and cleans temporary files"
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
    linux_ubuntu|linux_centos|linux_alinux3|linux_alinux4)
      assert_contains "$out" "credential.helper = cache --timeout=86400" "linux cache helper"
      assert_contains "$out" "apt / dnf / yum" "Linux delta install hint"
      assert_not_contains "$out" "cargo install" "Linux delta hint excludes cargo"
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

# Regression: git-bc used declare -A (Bash 4+), which fails under macOS Bash 3.2.
# Build a repo with a merged branch and a worktree branch; both must be handled.
test_bc_skips_worktree_and_flags_merged() {
  local work out
  work="$(mktemp -d "${TMPDIR:-/tmp}/git-bc.XXXXXX")"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  git init -q --bare "$work/origin.git"
  git init -q "$work/repo"
  git -C "$work/repo" config user.email "test@example.com"
  git -C "$work/repo" config user.name "Test"
  git -C "$work/repo" remote add origin "$work/origin.git"
  git -C "$work/repo" checkout -q -b main
  printf 'a\n' >"$work/repo/f"
  git -C "$work/repo" add f
  git -C "$work/repo" commit -qm init
  git -C "$work/repo" push -q -u origin main
  git -C "$work/repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

  # Branch checked out in a worktree must be skipped.
  git -C "$work/repo" checkout -q -b wt-branch
  printf 'c\n' >"$work/repo/h"
  git -C "$work/repo" add h
  git -C "$work/repo" commit -qm wt
  git -C "$work/repo" push -q origin wt-branch
  git -C "$work/repo" checkout -q main
  git -C "$work/repo" worktree add -q "$work/wt" wt-branch

  # Merged branch must be listed for deletion.
  git -C "$work/repo" checkout -q -b feature1
  printf 'b\n' >"$work/repo/g"
  git -C "$work/repo" add g
  git -C "$work/repo" commit -qm feature1
  git -C "$work/repo" checkout -q main
  git -C "$work/repo" merge -q --no-ff feature1 -m merge-feature1
  git -C "$work/repo" push -q origin main
  git -C "$work/repo" checkout -q main

  out="$(cd "$work/repo" && bash "$GIT_BC" --dry-run 2>&1)" || {
    echo "FAIL: git bc --dry-run failed: $out" >&2
    rm -rf "$work"
    return 1
  }
  assert_contains "$out" "feature1  (merged)" "merged branch is listed"
  assert_contains "$out" "wt-branch →" "worktree branch is skipped"
  rm -rf "$work"
  pass "git bc skips worktree & flags merged ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_unknown_flag
test_install_gh_branch
test_skip_gh
test_install_delta_branch
test_linux_ignores_other_package_managers
test_epel_failure_falls_back_to_system_repo
test_centos7_prefers_valid_delta_cache
test_centos7_rejects_corrupt_cache_then_downloads
test_centos7_downloads_when_cache_missing
test_centos7_non_x86_skips_static_delta
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
test_bc_skips_worktree_and_flags_merged

echo "PASS: git suite complete ($DEVTOOLS_TEST_PROFILE)"
