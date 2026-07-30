#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_contains() {
  local file="$1" expected="$2"
  grep -Fq -- "$expected" "$file" || fail "expected '$expected' in $file"
}

assert_not_contains() {
  local file="$1" unexpected="$2"
  ! grep -Fq -- "$unexpected" "$file" || fail "did not expect '$unexpected' in $file"
}

# Starship cache must be used before the online installer.
mkdir -p "$TMP_DIR/cache/binaries" "$TMP_DIR/home/.local/share/blesh" "$TMP_DIR/bin"
touch "$TMP_DIR/home/.local/share/blesh/ble.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_DIR/bin/git"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_DIR/bin/zoxide"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_DIR/bin/fzf"
cat > "$TMP_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
touch "$CURL_FAILURE_MARKER"
exit 97
EOF
chmod +x "$TMP_DIR/bin/git" "$TMP_DIR/bin/zoxide" "$TMP_DIR/bin/fzf" "$TMP_DIR/bin/curl"

mkdir -p "$TMP_DIR/starship-payload"
printf '#!/usr/bin/env bash\necho cached-starship\n' > "$TMP_DIR/starship-payload/starship"
chmod +x "$TMP_DIR/starship-payload/starship"
tar -czf "$TMP_DIR/cache/binaries/starship-x86_64-unknown-linux-musl.tar.gz"   -C "$TMP_DIR/starship-payload" starship

CURL_FAILURE_MARKER="$TMP_DIR/curl-called" PATH="$TMP_DIR/bin:/usr/bin:/bin" HOME="$TMP_DIR/home" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" bash "$ROOT/shell/bash/setup.sh" > "$TMP_DIR/starship.log" 2>&1 ||
  fail "Starship cache install failed; output: $(cat "$TMP_DIR/starship.log")"
assert_file "$TMP_DIR/home/.local/bin/starship"
[[ ! -e "$TMP_DIR/curl-called" ]] || fail "online installer was called despite a valid cache"

# Repository rendering must map Alibaba Cloud Linux 4 to an explicit compatible
# CentOS repository version and retain $releasever for normal CentOS.
cat > "$TMP_DIR/docker-ce.repo" <<'EOF'
[docker-ce-stable]
baseurl=https://download.docker.com/linux/centos/$releasever/$basearch/stable
EOF
cat > "$TMP_DIR/alinux-release" <<'EOF'
ID=alinux
VERSION_ID=4
EOF
cat > "$TMP_DIR/centos-release" <<'EOF'
ID=centos
VERSION_ID=9
EOF

SETUP_CENTOS_NO_MAIN=1 OS_RELEASE_FILE="$TMP_DIR/alinux-release" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" bash -c '
  source "$1"
  render_docker_repo "$2" "$3"
' _ "$ROOT/os/linux/setup_centos.sh" "$TMP_DIR/docker-ce.repo" "$TMP_DIR/alinux.repo" ||
  fail "Alibaba Cloud Linux repo rendering failed"
assert_contains "$TMP_DIR/alinux.repo" "http"
assert_contains "$TMP_DIR/alinux.repo" "/centos/9/"
assert_not_contains "$TMP_DIR/alinux.repo" '$releasever'
assert_not_contains "$TMP_DIR/alinux.repo" "/centos/4"

SETUP_CENTOS_NO_MAIN=1 OS_RELEASE_FILE="$TMP_DIR/centos-release" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" bash -c '
  source "$1"
  render_docker_repo "$2" "$3"
' _ "$ROOT/os/linux/setup_centos.sh" "$TMP_DIR/docker-ce.repo" "$TMP_DIR/centos.repo" ||
  fail "CentOS repo rendering failed"
assert_contains "$TMP_DIR/centos.repo" '$releasever'

# A previous interrupted fzf install may leave ~/.fzf behind even though fzf
# is not yet on PATH. Re-running setup must reuse a complete checkout instead
# of calling git clone into the non-empty directory.
mkdir -p "$TMP_DIR/fzf-home/.local/share/blesh" "$TMP_DIR/fzf-home/.fzf" "$TMP_DIR/fzf-bin"
touch "$TMP_DIR/fzf-home/.local/share/blesh/ble.sh"
printf '#!/usr/bin/env bash\ntouch "$FZF_INSTALL_MARKER"\n' > "$TMP_DIR/fzf-home/.fzf/install"
printf '#!/usr/bin/env bash\nif [[ "$1" == "clone" ]]; then touch "$FZF_CLONE_MARKER"; exit 99; fi\nexit 0\n' > "$TMP_DIR/fzf-bin/git"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_DIR/fzf-bin/zoxide"
chmod +x "$TMP_DIR/fzf-home/.fzf/install" "$TMP_DIR/fzf-bin/git" "$TMP_DIR/fzf-bin/zoxide"

FZF_INSTALL_MARKER="$TMP_DIR/fzf-install-called" FZF_CLONE_MARKER="$TMP_DIR/fzf-clone-called" PATH="$TMP_DIR/fzf-bin:/usr/bin:/bin" HOME="$TMP_DIR/fzf-home" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" bash "$ROOT/shell/bash/setup.sh" > "$TMP_DIR/fzf.log" 2>&1 ||
  fail "fzf retry failed; output: $(cat "$TMP_DIR/fzf.log")"
assert_file "$TMP_DIR/fzf-install-called"
[[ ! -e "$TMP_DIR/fzf-clone-called" ]] || fail "git clone was called for an existing fzf checkout"

# An incomplete checkout must be preserved and replaced with a fresh clone.
mkdir -p "$TMP_DIR/fzf-incomplete-home/.local/share/blesh" "$TMP_DIR/fzf-incomplete-home/.fzf" "$TMP_DIR/fzf-incomplete-bin"
touch "$TMP_DIR/fzf-incomplete-home/.local/share/blesh/ble.sh" "$TMP_DIR/fzf-incomplete-home/.fzf/partial-file"
printf '#!/usr/bin/env bash\nif [[ "$1" == "clone" ]]; then dest="${@: -1}"; if [[ -e "$dest" ]]; then touch "$FZF_CLONE_MARKER"; exit 99; fi; mkdir -p "$dest"; printf "#!/usr/bin/env bash\\ntouch \\\"$FZF_INSTALL_MARKER\\\"\\n" > "$dest/install"; chmod +x "$dest/install"; fi\nexit 0\n' > "$TMP_DIR/fzf-incomplete-bin/git"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_DIR/fzf-incomplete-bin/zoxide"
chmod +x "$TMP_DIR/fzf-incomplete-bin/git" "$TMP_DIR/fzf-incomplete-bin/zoxide"

FZF_INSTALL_MARKER="$TMP_DIR/fzf-incomplete-install-called" FZF_CLONE_MARKER="$TMP_DIR/fzf-incomplete-clone-failed" PATH="$TMP_DIR/fzf-incomplete-bin:/usr/bin:/bin" HOME="$TMP_DIR/fzf-incomplete-home" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" bash "$ROOT/shell/bash/setup.sh" > "$TMP_DIR/fzf-incomplete.log" 2>&1 ||
  fail "incomplete fzf retry failed; output: $(cat "$TMP_DIR/fzf-incomplete.log")"
assert_file "$TMP_DIR/fzf-incomplete-install-called"
[[ ! -e "$TMP_DIR/fzf-incomplete-clone-failed" ]] || fail "incomplete fzf directory was not moved before cloning"
find "$TMP_DIR/fzf-incomplete-home" -maxdepth 1 -type d -name '.fzf.backup.*' | grep -q . || fail "incomplete fzf directory was not backed up"

# The cached NodeSource script must not reject Alibaba Cloud Linux solely
# because /etc/redhat-release is absent.
assert_not_contains "$ROOT/cache/scripts/nodesource-setup-20.x" '! [ -f /etc/redhat-release ] && ! grep -q "Amazon Linux" /etc/system-release'
assert_contains "$ROOT/cache/scripts/nodesource-setup-20.x" 'command -v rpm'

# packages.list parser and OS setup dry-run (no real install)
bash -n "$ROOT/os/lib/packages_list.sh" || fail "bash -n os/lib/packages_list.sh"
bash -n "$ROOT/os/linux/setup_ubuntu.sh" || fail "bash -n setup_ubuntu.sh"
bash -n "$ROOT/os/linux/setup_centos.sh" || fail "bash -n setup_centos.sh"
bash -n "$ROOT/os/macos/setup.sh" || fail "bash -n os/macos/setup.sh"
bash -n "$ROOT/cache/download.sh" || fail "bash -n cache/download.sh"

assert_file "$ROOT/os/macos/packages.list"
assert_file "$ROOT/os/linux/packages.ubuntu.list"
assert_file "$ROOT/os/linux/packages.centos.list"

# shellcheck disable=SC1091
source "$ROOT/os/lib/packages_list.sh"
yazi_ver="$(packages_list_get_version "$ROOT/os/linux/packages.centos.list" yazi)" ||
  fail "packages_list_get_version yazi"
[[ "$yazi_ver" == "0.3.3" ]] || fail "expected yazi 0.3.3, got $yazi_ver"
tmux_ver="$(packages_list_get_version "$ROOT/os/linux/packages.centos.list" tmux)" ||
  fail "packages_list_get_version tmux"
[[ "$tmux_ver" == "3.7b" ]] || fail "expected tmux 3.7b, got $tmux_ver"
packages_list_has "$ROOT/os/macos/packages.list" git || fail "macos packages.list missing git"
packages_list_has "$ROOT/os/linux/packages.ubuntu.list" docker || fail "ubuntu list missing docker"

centos_dry="$TMP_DIR/centos-dry.log"
bash "$ROOT/os/linux/setup_centos.sh" --dry-run --packages-only >"$centos_dry" 2>&1 ||
  fail "setup_centos --dry-run failed: $(cat "$centos_dry")"
assert_contains "$centos_dry" "[dry-run] docker"
assert_contains "$centos_dry" "[dry-run] yazi"
assert_contains "$centos_dry" "packages.centos.list"

ubuntu_dry="$TMP_DIR/ubuntu-dry.log"
bash "$ROOT/os/linux/setup_ubuntu.sh" --dry-run --packages-only >"$ubuntu_dry" 2>&1 ||
  fail "setup_ubuntu --dry-run failed: $(cat "$ubuntu_dry")"
assert_contains "$ubuntu_dry" "[dry-run] docker"
assert_contains "$ubuntu_dry" "[dry-run] lazygit"

packages_list_has "$ROOT/os/linux/packages.centos.list" jq || fail "centos list missing jq"
packages_list_has "$ROOT/os/linux/packages.centos.list" bat || fail "centos list missing bat"
packages_list_has "$ROOT/os/linux/packages.centos.list" rg || fail "centos list missing rg"
packages_list_has "$ROOT/os/linux/packages.ubuntu.list" bat || fail "ubuntu list missing bat"
packages_list_has "$ROOT/os/macos/packages.list" rg || fail "macos list missing rg"
[[ "$(packages_list_brew_formula rg)" == "ripgrep" ]] || fail "rg brew formula mapping"
[[ "$(packages_list_sys_pkg rg)" == "ripgrep" ]] || fail "rg sys pkg mapping"

centos_check="$TMP_DIR/centos-check.log"
bash "$ROOT/os/linux/setup_centos.sh" --check >"$centos_check" 2>&1 ||
  fail "setup_centos --check failed: $(cat "$centos_check")"
assert_contains "$centos_check" "NAME"
assert_contains "$centos_check" "KIND"
assert_contains "$centos_check" "TAGS"
assert_contains "$centos_check" "jq"
assert_contains "$centos_check" "bat"
assert_contains "$centos_check" "rg"
assert_contains "$centos_check" "summary:"

centos_kind="$TMP_DIR/centos-kind.log"
bash "$ROOT/os/linux/setup_centos.sh" --check --kind tui >"$centos_kind" 2>&1 ||
  fail "setup_centos --check --kind tui failed: $(cat "$centos_kind")"
assert_contains "$centos_kind" "tmux"
assert_contains "$centos_kind" "yazi"
assert_not_contains "$centos_kind" "docker"

centos_tag="$TMP_DIR/centos-tag.log"
bash "$ROOT/os/linux/setup_centos.sh" --check --tag diagnostic >"$centos_tag" 2>&1 ||
  fail "setup_centos --check --tag diagnostic failed: $(cat "$centos_tag")"
assert_contains "$centos_tag" "rg"
assert_contains "$centos_tag" "cloc"
assert_not_contains "$centos_tag" "lazygit"

centos_install_one="$TMP_DIR/centos-install-one.log"
bash "$ROOT/os/linux/setup_centos.sh" --install bat --dry-run >"$centos_install_one" 2>&1 ||
  fail "setup_centos --install bat --dry-run failed: $(cat "$centos_install_one")"
assert_contains "$centos_install_one" "[dry-run] bat"
assert_not_contains "$centos_install_one" "[dry-run] docker"

ubuntu_check="$TMP_DIR/ubuntu-check.log"
bash "$ROOT/os/linux/setup_ubuntu.sh" --check >"$ubuntu_check" 2>&1 ||
  fail "setup_ubuntu --check failed: $(cat "$ubuntu_check")"
assert_contains "$ubuntu_check" "summary:"
grep -Eq 'installed|missing' "$ubuntu_check" || fail "ubuntu --check missing status column"

ubuntu_filter_dry="$TMP_DIR/ubuntu-filter-dry.log"
bash "$ROOT/os/linux/setup_ubuntu.sh" --dry-run --packages-only --kind tui >"$ubuntu_filter_dry" 2>&1 ||
  fail "setup_ubuntu --kind tui dry-run failed: $(cat "$ubuntu_filter_dry")"
assert_contains "$ubuntu_filter_dry" "[dry-run] tmux"
assert_not_contains "$ubuntu_filter_dry" "[dry-run] docker"

# --- shell/bash setup.sh plugin CLI ---
bash -n "$ROOT/shell/bash/setup.sh" || fail "bash -n shell/bash/setup.sh"

cli_help="$TMP_DIR/bash-cli-help.log"
bash "$ROOT/shell/bash/setup.sh" --help >"$cli_help" 2>&1 || fail "setup.sh --help failed"
assert_contains "$cli_help" "install"
assert_contains "$cli_help" "list"
assert_contains "$cli_help" "-n"
assert_not_contains "$cli_help" "-d, --dry-run"

cli_list_home="$TMP_DIR/bash-list-home"
mkdir -p "$cli_list_home/.local/share/blesh" "$cli_list_home/.local/bin"
touch "$cli_list_home/.local/share/blesh/ble.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$cli_list_home/.local/bin/zoxide"
chmod +x "$cli_list_home/.local/bin/zoxide"
# fzf and starship intentionally missing
cli_list="$TMP_DIR/bash-cli-list.log"
PATH="$cli_list_home/.local/bin:/usr/bin:/bin" HOME="$cli_list_home" \
  bash "$ROOT/shell/bash/setup.sh" list >"$cli_list" 2>&1 ||
  fail "setup.sh list failed: $(cat "$cli_list")"
assert_contains "$cli_list" "blesh"
assert_contains "$cli_list" "zoxide"
assert_contains "$cli_list" "fzf"
assert_contains "$cli_list" "starship"
assert_contains "$cli_list" "[installed]"
assert_contains "$cli_list" "[missing]"
grep -E 'blesh[[:space:]].*\[installed\]' "$cli_list" >/dev/null ||
  fail "blesh should be installed in list output"
grep -E 'zoxide[[:space:]].*\[installed\]' "$cli_list" >/dev/null ||
  fail "zoxide should be installed in list output"
grep -E 'fzf[[:space:]].*\[missing\]' "$cli_list" >/dev/null ||
  fail "fzf should be missing in list output"
grep -E 'starship[[:space:]].*\[missing\]' "$cli_list" >/dev/null ||
  fail "starship should be missing in list output"

cli_unknown_rc=0
bash "$ROOT/shell/bash/setup.sh" install nope >"$TMP_DIR/bash-cli-unknown.log" 2>&1 || cli_unknown_rc=$?
[[ "$cli_unknown_rc" -ne 0 ]] || fail "unknown plugin should fail"
assert_contains "$TMP_DIR/bash-cli-unknown.log" "list"

cli_dry="$TMP_DIR/bash-cli-dry.log"
HOME="$TMP_DIR/bash-dry-home" mkdir -p "$TMP_DIR/bash-dry-home"
HOME="$TMP_DIR/bash-dry-home" PATH="/usr/bin:/bin" \
  bash "$ROOT/shell/bash/setup.sh" install -n >"$cli_dry" 2>&1 ||
  fail "setup.sh install -n failed: $(cat "$cli_dry")"
assert_contains "$cli_dry" "试运行"
[[ ! -f "$TMP_DIR/bash-dry-home/.bashrc" ]] ||
  fail "dry-run must not create .bashrc when it did not exist"

# install fzf only must not invoke zoxide online installer (curl) when zoxide missing
single_home="$TMP_DIR/bash-single-home"
single_bin="$TMP_DIR/bash-single-bin"
mkdir -p "$single_home/.local/share/blesh" "$single_home/.fzf" "$single_bin"
touch "$single_home/.local/share/blesh/ble.sh"
printf '#!/usr/bin/env bash\ntouch "$FZF_INSTALL_MARKER"\n' > "$single_home/.fzf/install"
chmod +x "$single_home/.fzf/install"
printf '#!/usr/bin/env bash\nif [[ "$1" == "clone" ]]; then touch "$FZF_CLONE_MARKER"; exit 99; fi\nexit 0\n' > "$single_bin/git"
cat > "$single_bin/curl" <<'EOF'
#!/usr/bin/env bash
touch "$CURL_CALLED_MARKER"
exit 97
EOF
chmod +x "$single_bin/git" "$single_bin/curl"

FZF_INSTALL_MARKER="$TMP_DIR/bash-single-fzf-install" \
FZF_CLONE_MARKER="$TMP_DIR/bash-single-fzf-clone" \
CURL_CALLED_MARKER="$TMP_DIR/bash-single-curl" \
PATH="$single_bin:/usr/bin:/bin" HOME="$single_home" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" \
  bash "$ROOT/shell/bash/setup.sh" install fzf >"$TMP_DIR/bash-single.log" 2>&1 ||
  fail "install fzf failed: $(cat "$TMP_DIR/bash-single.log")"
assert_file "$TMP_DIR/bash-single-fzf-install"
[[ ! -e "$TMP_DIR/bash-single-curl" ]] || fail "install fzf must not curl-install zoxide/starship"
assert_contains "$single_home/.bashrc" "Lightweight Bash Plugins"
# starship.toml must NOT be written for fzf-only install
[[ ! -f "$single_home/.config/starship.toml" ]] ||
  fail "fzf-only install must not write starship.toml"

# alias ble.sh
alias_rc=0
PATH="$single_bin:/usr/bin:/bin" HOME="$single_home" DEVTOOLS_CACHE_DIR="$TMP_DIR/cache" \
  bash "$ROOT/shell/bash/setup.sh" install ble.sh -n >"$TMP_DIR/bash-alias.log" 2>&1 || alias_rc=$?
[[ "$alias_rc" -eq 0 ]] || fail "ble.sh alias dry-run failed: $(cat "$TMP_DIR/bash-alias.log")"

echo "PASS: Linux setup cache and ECS repository regression tests"
