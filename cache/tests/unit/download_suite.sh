#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${TEST_SRCDIR:-}" ]]; then
  REPO_ROOT="${TEST_SRCDIR}/${TEST_WORKSPACE:-_main}"
else
  REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi
DOWNLOAD_SH="$REPO_ROOT/cache/download.sh"
NODESOURCE_SCRIPT="$REPO_ROOT/cache/scripts/nodesource-setup-20.x"
DELTA_FIXTURE="$REPO_ROOT/cache/binaries/delta-0.19.2-x86_64-unknown-linux-musl.tar.gz"
DELTA_SHA256="f1ea01ca7728ce3462debc359f39dfc7cbbc1a63224b71fefabf92042864aa1b"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cache-download-test.XXXXXX")"
ORIGINAL_PATH="$PATH"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_valid_delta() {
  local archive="$1" actual
  [[ -f "$archive" ]] || fail "missing archive: $archive"
  actual="$(file_sha256 "$archive")"
  [[ "$actual" == "$DELTA_SHA256" ]] || fail "unexpected checksum for $archive: $actual"
}

export CACHE_DOWNLOAD_NO_MAIN=1
# shellcheck disable=SC1090
source "$DOWNLOAD_SH"

test_valid_cache_skips_download() {
  local dir="$TMP_ROOT/valid" dest fake_bin
  mkdir -p "$dir"
  dest="$dir/delta.tar.gz"
  cp "$DELTA_FIXTURE" "$dest"
  fake_bin="$dir/bin"
  mkdir -p "$fake_bin"
  cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
touch "$CURL_MARKER"
exit 99
EOF
  chmod +x "$fake_bin/curl"

  CURL_MARKER="$dir/curl-called" PATH="$fake_bin:$ORIGINAL_PATH" \
    download_verified "https://example.invalid/delta.tar.gz" "$dest" "$DELTA_SHA256"
  [[ ! -e "$dir/curl-called" ]] || fail "valid cache unexpectedly downloaded"
  assert_valid_delta "$dest"
  echo "PASS: valid verified cache skips download"
}

write_fixture_curl() {
  local path="$1"
  cat >"$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
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
[[ "$out" != "$FINAL_DEST" ]]
[[ ! -e "$FINAL_DEST" ]]
cp "$DELTA_FIXTURE" "$out"
EOF
  chmod +x "$path"
}

test_corrupt_cache_is_replaced_atomically() {
  local dir="$TMP_ROOT/corrupt" dest fake_bin
  mkdir -p "$dir"
  dest="$dir/delta.tar.gz"
  printf 'corrupt\n' >"$dest"
  fake_bin="$dir/bin"
  mkdir -p "$fake_bin"
  write_fixture_curl "$fake_bin/curl"

  FINAL_DEST="$dest" DELTA_FIXTURE="$DELTA_FIXTURE" PATH="$fake_bin:$ORIGINAL_PATH" \
    download_verified "https://example.invalid/delta.tar.gz" "$dest" "$DELTA_SHA256"
  assert_valid_delta "$dest"
  if find "$dir" -maxdepth 1 -name 'delta.tar.gz.tmp.*' -print -quit | grep -q .; then
    fail "temporary download file was not cleaned up"
  fi
  echo "PASS: corrupt cache is replaced atomically"
}

test_failed_redownload_leaves_no_corrupt_target() {
  local dir="$TMP_ROOT/failure" dest fake_bin rc=0
  mkdir -p "$dir"
  dest="$dir/delta.tar.gz"
  printf 'corrupt\n' >"$dest"
  fake_bin="$dir/bin"
  mkdir -p "$fake_bin"
  cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 22
EOF
  chmod +x "$fake_bin/curl"

  PATH="$fake_bin:$ORIGINAL_PATH" \
    download_verified "https://example.invalid/delta.tar.gz" "$dest" "$DELTA_SHA256" || rc=$?
  [[ "$rc" -ne 0 ]] || fail "failed download unexpectedly succeeded"
  [[ ! -e "$dest" ]] || fail "corrupt target survived failed redownload"
  if find "$dir" -maxdepth 1 -name 'delta.tar.gz.tmp.*' -print -quit | grep -q .; then
    fail "failed download left a temporary file"
  fi
  echo "PASS: failed redownload removes corrupt target and temp file"
}

test_linux_download_includes_delta() {
  local dir="$TMP_ROOT/linux" fake_bin dest
  dir="$TMP_ROOT/linux"
  fake_bin="$dir/bin"
  dest="$dir/binaries/delta-0.19.2-x86_64-unknown-linux-musl.tar.gz"
  mkdir -p "$dir/binaries" "$dir/scripts" "$dir/fonts" "$fake_bin"
  write_fixture_curl "$fake_bin/curl"
  BINARIES_DIR="$dir/binaries"
  SCRIPTS_DIR="$dir/scripts"
  FONTS_DIR="$dir/fonts"
  download() { :; }
  download_alinux3_kernel_headers() { :; }

  FINAL_DEST="$dest" \
    DELTA_FIXTURE="$DELTA_FIXTURE" PATH="$fake_bin:$ORIGINAL_PATH" \
    download_linux >/dev/null
  assert_valid_delta "$dest"
  echo "PASS: Linux cache download includes git-delta"
}

bash -n "$DOWNLOAD_SH"
if grep -Fq '! [ -f /etc/redhat-release ] && ! grep -q "Amazon Linux" /etc/system-release' \
    "$NODESOURCE_SCRIPT"; then
  fail "cached NodeSource script rejects ALinux without /etc/redhat-release"
fi
grep -Fq 'command -v rpm' "$NODESOURCE_SCRIPT" ||
  fail "cached NodeSource script does not detect RPM systems"

test_linux_download_includes_glow() {
  local dir="$TMP_ROOT/linux-glow" fake_bin log
  mkdir -p "$dir/binaries" "$dir/scripts" "$dir/fonts"
  fake_bin="$dir/bin"
  log="$dir/download.log"
  mkdir -p "$fake_bin"
  : >"$log"

  BINARIES_DIR="$dir/binaries"
  SCRIPTS_DIR="$dir/scripts"
  FONTS_DIR="$dir/fonts"
  download() {
    printf '%s\t%s\n' "$1" "$2" >>"$log"
  }
  download_verified() {
    :
  }
  download_git_delta() {
    :
  }

  PATH="$fake_bin:$ORIGINAL_PATH" download_linux >/dev/null

  grep -Fq $'https://github.com/charmbracelet/glow/releases/download/v2.1.2/glow_2.1.2_Linux_x86_64.tar.gz\t'"$dir/binaries/glow_2.1.2_Linux_x86_64.tar.gz" "$log" ||
    fail "linux download missing glow x86_64 v2.1.2 tarball"
  grep -Fq $'https://github.com/charmbracelet/glow/releases/download/v2.1.2/glow_2.1.2_Linux_arm64.tar.gz\t'"$dir/binaries/glow_2.1.2_Linux_arm64.tar.gz" "$log" ||
    fail "linux download missing glow arm64 v2.1.2 tarball"
  echo "PASS: Linux cache download includes pinned glow tarballs"
}

test_linux_download_includes_nvim() {
  local dir="$TMP_ROOT/linux-nvim" fake_bin log
  mkdir -p "$dir/binaries" "$dir/scripts" "$dir/fonts"
  fake_bin="$dir/bin"
  log="$dir/download.log"
  mkdir -p "$fake_bin"
  : >"$log"

  BINARIES_DIR="$dir/binaries"
  SCRIPTS_DIR="$dir/scripts"
  FONTS_DIR="$dir/fonts"
  download() {
    printf '%s\t%s\n' "$1" "$2" >>"$log"
  }
  download_verified() {
    :
  }
  download_git_delta() {
    :
  }

  PATH="$fake_bin:$ORIGINAL_PATH" download_linux >/dev/null

  grep -Fq $'https://github.com/neovim/neovim/releases/download/v0.10.4/nvim-linux-x86_64.tar.gz\t'"$dir/binaries/nvim-linux-x86_64-v0.10.4.tar.gz" "$log" ||
    fail "linux download missing nvim x86_64 v0.10.4 tarball"
  grep -Fq $'https://github.com/neovim/neovim/releases/download/v0.10.4/nvim-linux-arm64.tar.gz\t'"$dir/binaries/nvim-linux-arm64-v0.10.4.tar.gz" "$log" ||
    fail "linux download missing nvim arm64 v0.10.4 tarball"
  if grep -Ei 'appimage|/stable/nvim' "$log"; then
    fail "linux download still references neovim AppImage or stable"
  fi
  echo "PASS: Linux cache download includes pinned Neovim tarballs"
}

test_valid_cache_skips_download
test_corrupt_cache_is_replaced_atomically
test_failed_redownload_leaves_no_corrupt_target
test_linux_download_includes_kernel_headers() {
  local dir="$TMP_ROOT/linux-kh" fake_bin log
  # Earlier cases replace download helpers in this shell. Reload the script so
  # this case calls the real kernel-headers downloader.
  # shellcheck disable=SC1090
  source "$DOWNLOAD_SH"
  mkdir -p "$dir/binaries" "$dir/scripts" "$dir/fonts"
  fake_bin="$dir/bin"
  log="$dir/download.log"
  mkdir -p "$fake_bin"
  : >"$log"

  BINARIES_DIR="$dir/binaries"
  SCRIPTS_DIR="$dir/scripts"
  FONTS_DIR="$dir/fonts"
  download() { :; }
  download_verified() {
    printf '%s\t%s\n' "$1" "$2" >>"$log"
  }

  PATH="$fake_bin:$ORIGINAL_PATH" download_linux >/dev/null

  grep -Fq $'https://mirrors.aliyun.com/alinux/3/plus/x86_64/kernels/kernel-headers-5.10.134-20.2.al8.x86_64.rpm\t'"$dir/binaries/kernel-headers-5.10.134-20.2.al8.x86_64.rpm" "$log" ||
    fail "linux download missing pinned alinux3 kernel-headers RPM"
  echo "PASS: Linux cache download includes pinned alinux3 kernel-headers"
}

test_linux_download_includes_delta
test_linux_download_includes_glow
test_linux_download_includes_nvim
test_linux_download_includes_kernel_headers

# Integrity pins for the protobuf geo data: a history-rewrite once replaced
# a domain substring inside geosite.dat and broke its wire format. Checksums
# catch any future byte-level corruption of these binary assets.
GEOSITE_SHA256="8c3a825b1a7d09f627de10263b21008b8a48dee10794f42caf1927928fec74da"
GEOIP_SHA256="6ba63d75f307d16a81ae09406ddcf2779fa75cb642d4aae59613370d62d33509"
actual="$(file_sha256 "$REPO_ROOT/cache/binaries/geosite.dat")"
[[ "$actual" == "$GEOSITE_SHA256" ]] || fail "geosite.dat checksum mismatch (corrupted?): $actual"
actual="$(file_sha256 "$REPO_ROOT/cache/binaries/geoip.dat")"
[[ "$actual" == "$GEOIP_SHA256" ]] || fail "geoip.dat checksum mismatch (corrupted?): $actual"
KH_SHA256="18bea523d468e822a24a74e2427e62355b278895f76516941db1c1a3d890893a"
actual="$(file_sha256 "$REPO_ROOT/cache/binaries/kernel-headers-5.10.134-20.2.al8.x86_64.rpm")"
[[ "$actual" == "$KH_SHA256" ]] || fail "kernel-headers RPM checksum mismatch (corrupted?): $actual"

echo "PASS: cache download unit suite"
