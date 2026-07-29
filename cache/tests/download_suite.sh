#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${TEST_SRCDIR:-}" ]]; then
  REPO_ROOT="${TEST_SRCDIR}/${TEST_WORKSPACE:-_main}"
else
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi
DOWNLOAD_SH="$REPO_ROOT/cache/download.sh"
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
  actual="$(sha256sum "$archive" | awk '{print $1}')"
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

  FINAL_DEST="$dest" \
    DELTA_FIXTURE="$DELTA_FIXTURE" PATH="$fake_bin:$ORIGINAL_PATH" \
    download_linux >/dev/null
  assert_valid_delta "$dest"
  echo "PASS: Linux cache download includes git-delta"
}

test_valid_cache_skips_download
test_corrupt_cache_is_replaced_atomically
test_failed_redownload_leaves_no_corrupt_target
test_linux_download_includes_delta

echo "PASS: cache download suite"
