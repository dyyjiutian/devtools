#!/usr/bin/env bash
# OS profile helpers: inject fake uname / package managers into PATH.
# shellcheck shell=bash

_devtools_write_exec() {
  local path="$1"
  shift
  cat >"$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
$*
EOF
  chmod +x "$path"
}

_devtools_resolve_host_tool() {
  local tool="$1" real dir
  real="$(command -v "$tool" 2>/dev/null || true)"
  if [[ -n "$real" && -x "$real" ]]; then
    printf '%s\n' "$real"
    return 0
  fi
  for dir in /usr/bin /bin /usr/local/bin /opt/homebrew/bin; do
    if [[ -x "$dir/$tool" ]]; then
      printf '%s\n' "$dir/$tool"
      return 0
    fi
  done
  return 1
}

# Link a minimal set of host tools into fake_bin so PATH can exclude /usr/bin/gh etc.
_devtools_link_host_tools() {
  local fake_bin="$1"
  local tool real shasum_bin
  local tools=(
    git head grep awk sed tr find mkdir cp ln rm cat tee bash mktemp
    basename dirname readlink wc date env true false chmod touch printf
    ls mv echo sort uniq sleep diff cut install getconf nproc gzip sha256sum tar node
    df hostname whoami python3
  )
  for tool in "${tools[@]}"; do
    real="$(_devtools_resolve_host_tool "$tool" || true)"
    if [[ -n "$real" && -x "$real" ]]; then
      # Portable: macOS BSD ln has no GNU -d; -sf is enough for force symlink.
      ln -sf "$real" "$fake_bin/$tool"
    fi
  done
  if [[ ! -x "$fake_bin/sha256sum" ]]; then
    shasum_bin="$(_devtools_resolve_host_tool shasum || true)"
    if [[ -n "$shasum_bin" ]]; then
      _devtools_write_exec "$fake_bin/sha256sum" "exec $(printf '%q' "$shasum_bin") -a 256 \"\$@\""
    fi
  fi
}

# setup_os_profile <profile> <fake_bin_dir>
# Creates fake commands for the given profile and sets PATH to fake_bin only.
setup_os_profile() {
  local profile="$1"
  local fake_bin="$2"

  mkdir -p "$fake_bin"
  _devtools_link_host_tools "$fake_bin"

  # Replace any linked names we override with profile fakes.
  rm -f "$fake_bin"/{uname,brew,apt-get,apt,dnf,yum,pacman,zypper,sudo,curl,rpm,dpkg-query,gh,delta}

  case "$profile" in
    linux_ubuntu)
      _devtools_write_exec "$fake_bin/uname" 'if [[ "${1:-}" == "-m" ]]; then printf "x86_64\n"; else printf "Linux\n"; fi'
      _devtools_write_exec "$fake_bin/apt-get" 'printf "apt-get %s\n" "$*" >&2; exit 0'
      _devtools_write_exec "$fake_bin/apt" 'printf "apt %s\n" "$*" >&2; exit 0'
      printf 'ID=ubuntu\nVERSION_ID=24.04\nVERSION_CODENAME=noble\nPRETTY_NAME="Ubuntu 24.04 LTS"\n' >"$HOME/os-release"
      ;;
    linux_centos)
      _devtools_write_exec "$fake_bin/uname" 'if [[ "${1:-}" == "-m" ]]; then printf "x86_64\n"; else printf "Linux\n"; fi'
      # dnf4-style --version (not dnf5) so install_gh takes the config-manager --add-repo path
      _devtools_write_exec "$fake_bin/dnf" 'if [[ "${1:-}" == "--version" ]]; then printf "4.14.0\n"; exit 0; fi; printf "dnf %s\n" "$*" >&2; exit 0'
      _devtools_write_exec "$fake_bin/yum" 'printf "yum %s\n" "$*" >&2; exit 0'
      _devtools_write_exec "$fake_bin/rpm" 'exit 1'
      printf 'ID=centos\nVERSION_ID=9\nPRETTY_NAME="CentOS Stream 9"\n' >"$HOME/os-release"
      ;;
    linux_alinux3)
      _devtools_write_exec "$fake_bin/uname" 'if [[ "${1:-}" == "-m" ]]; then printf "x86_64\n"; else printf "Linux\n"; fi'
      _devtools_write_exec "$fake_bin/dnf" 'if [[ "${1:-}" == "--version" ]]; then printf "4.7.0\n"; exit 0; fi; printf "dnf %s\n" "$*" >&2; exit 0'
      _devtools_write_exec "$fake_bin/yum" 'printf "yum %s\n" "$*" >&2; exit 0'
      _devtools_write_exec "$fake_bin/rpm" 'exit 1'
      printf 'ID=alinux\nVERSION_ID=3\nPRETTY_NAME="Alibaba Cloud Linux 3"\n' >"$HOME/os-release"
      ;;
    linux_alinux4)
      _devtools_write_exec "$fake_bin/uname" 'if [[ "${1:-}" == "-m" ]]; then printf "x86_64\n"; else printf "Linux\n"; fi'
      _devtools_write_exec "$fake_bin/dnf" 'if [[ "${1:-}" == "--version" ]]; then printf "4.16.2\n"; exit 0; fi; printf "dnf %s\n" "$*" >&2; exit 0'
      _devtools_write_exec "$fake_bin/yum" 'printf "yum %s\n" "$*" >&2; exit 0'
      _devtools_write_exec "$fake_bin/rpm" 'exit 1'
      printf 'ID=alinux\nVERSION_ID=4\nPRETTY_NAME="Alibaba Cloud Linux 4"\n' >"$HOME/os-release"
      ;;
    macos)
      _devtools_write_exec "$fake_bin/uname" 'if [[ "${1:-}" == "-m" ]]; then printf "x86_64\n"; else printf "Darwin\n"; fi'
      _devtools_write_exec "$fake_bin/brew" '
if [[ "${1:-}" == "list" ]]; then exit 1; fi
printf "brew %s\n" "$*" >&2
exit 0
'
      : >"$HOME/os-release"
      ;;
    *)
      echo "Unknown DEVTOOLS_TEST_PROFILE: $profile" >&2
      return 1
      ;;
  esac

  _devtools_write_exec "$fake_bin/sudo" 'exec "$@"'
  _devtools_write_exec "$fake_bin/curl" '
echo "curl invoked unexpectedly: $*" >&2
exit 1
'

  # Hermetic PATH: only fakes + linked host tools (no host gh/delta/brew/apt/dnf).
  export PATH="$fake_bin"
  export DEVTOOLS_TEST_PROFILE="$profile"
  export DEVTOOLS_TEST_ARCH="x86_64"
  export DEVTOOLS_ARCH="x86_64"
  export OS_RELEASE_FILE="$HOME/os-release"
}

profile_uname_expected() {
  case "${1:-}" in
    macos) echo "Darwin" ;;
    linux_ubuntu|linux_centos|linux_alinux3|linux_alinux4) echo "Linux" ;;
    *) echo "unknown" ;;
  esac
}
