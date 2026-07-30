#!/usr/bin/env bash
# nvim module suite — expects run_module_test.sh environment.
set -euo pipefail

SETUP_SH="$MODULE_ROOT/setup.sh"

_devtools_write_exec() {
  local path="$1"
  local body="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$body" >"$path"
  chmod +x "$path"
}

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "Neovim" "help mentions Neovim"
  assert_contains "$out" "0.10.4" "help mentions pinned version"
  pass "nvim setup --help ($DEVTOOLS_TEST_PROFILE)"
}

test_linux_prefers_nvim_cache() {
  case "$DEVTOOLS_TEST_PROFILE" in
    linux_*) ;;
    *)
      pass "nvim cache prefer skipped on $DEVTOOLS_TEST_PROFILE"
      return 0
      ;;
  esac

  local alt_bin="$HOME/nvim-cache-bin"
  local cache_name="nvim-linux-x86_64-v0.10.4.appimage"
  local cached="$DEVTOOLS_CACHE_DIR/binaries/$cache_name"
  local out

  mkdir -p "$DEVTOOLS_CACHE_DIR/binaries" "$alt_bin" "$HOME/.local/bin"
  rm -f "$HOME/curl-was-called" "$HOME/.local/bin/nvim"

  # Minimal fake AppImage payload (executable stub).
  cat >"$cached" <<'EOF'
#!/usr/bin/env bash
echo "NVIM v0.10.4 (fake cache)"
EOF
  chmod +x "$cached"

  _devtools_write_exec "$alt_bin/curl" 'touch "$HOME/curl-was-called"; echo "curl should not run" >&2; exit 1'

  out="$(
    PATH="$alt_bin:$PATH" HOME="$HOME" DEVTOOLS_CACHE_DIR="$DEVTOOLS_CACHE_DIR" \
      SETUP_NO_MAIN=1 /bin/bash -c '
        setup="$1"
        set --
        # shellcheck disable=SC1090
        source "$setup"
        install_nvim_linux
      ' _ "$SETUP_SH" 2>&1
  )" || {
    echo "FAIL: install_nvim_linux with cache failed: $out" >&2
    return 1
  }

  assert_contains "$out" "local cache" "mentions local cache"
  assert_contains "$out" "$cache_name" "mentions cached filename"
  assert_file_exists "$HOME/.local/bin/nvim" "nvim installed to ~/.local/bin"
  [[ ! -e "$HOME/curl-was-called" ]] || {
    echo "FAIL: valid cache unexpectedly accessed network" >&2
    return 1
  }
  pass "nvim linux prefers cache ($DEVTOOLS_TEST_PROFILE)"
}

test_linux_download_uses_pinned_url() {
  case "$DEVTOOLS_TEST_PROFILE" in
    linux_*) ;;
    *)
      pass "nvim pinned download skipped on $DEVTOOLS_TEST_PROFILE"
      return 0
      ;;
  esac

  local alt_bin="$HOME/nvim-download-bin"
  local out
  local url_log="$HOME/curl-url.log"

  mkdir -p "$alt_bin" "$HOME/.local/bin" "$DEVTOOLS_CACHE_DIR/binaries"
  rm -f "$DEVTOOLS_CACHE_DIR/binaries"/nvim-*.appimage "$url_log" "$HOME/.local/bin/nvim"

  _devtools_write_exec "$alt_bin/curl" '
printf "%s\n" "$*" >>"$HOME/curl-url.log"
out=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" || "$1" == "-O" ]]; then
    out="$2"
    shift 2
  else
    shift
  fi
done
[[ -n "$out" ]]
cat >"$out" <<'"'"'APP'"'"'
#!/usr/bin/env bash
echo fake-nvim
APP
chmod +x "$out"
'

  out="$(
    PATH="$alt_bin:$PATH" HOME="$HOME" DEVTOOLS_CACHE_DIR="$DEVTOOLS_CACHE_DIR" \
      SETUP_NO_MAIN=1 /bin/bash -c '
        setup="$1"
        set --
        # shellcheck disable=SC1090
        source "$setup"
        install_nvim_linux
      ' _ "$SETUP_SH" 2>&1
  )" || {
    echo "FAIL: install_nvim_linux download path failed: $out" >&2
    return 1
  }

  assert_file_exists "$url_log" "curl was invoked"
  assert_contains "$(cat "$url_log")" "v0.10.4/nvim-linux-x86_64.appimage" "downloads pinned v0.10.4"
  assert_not_contains "$(cat "$url_log")" "/stable/" "does not use stable tag"
  assert_file_exists "$HOME/.local/bin/nvim" "nvim installed after download"
  pass "nvim linux downloads pinned URL ($DEVTOOLS_TEST_PROFILE)"
}

test_linux_skips_when_nvim_present() {
  case "$DEVTOOLS_TEST_PROFILE" in
    linux_*) ;;
    *)
      pass "nvim skip-when-present skipped on $DEVTOOLS_TEST_PROFILE"
      return 0
      ;;
  esac

  local alt_bin="$HOME/nvim-present-bin"
  local out

  mkdir -p "$alt_bin" "$HOME/.local/bin"
  rm -f "$HOME/curl-was-called" "$HOME/.local/bin/nvim"

  _devtools_write_exec "$alt_bin/nvim" 'if [[ "${1:-}" == "--version" ]]; then echo "NVIM v0.10.4"; exit 0; fi; exit 0'
  _devtools_write_exec "$alt_bin/curl" 'touch "$HOME/curl-was-called"; exit 1'

  out="$(
    PATH="$alt_bin:$PATH" HOME="$HOME" DEVTOOLS_CACHE_DIR="$DEVTOOLS_CACHE_DIR" \
      SETUP_NO_MAIN=1 /bin/bash -c '
        setup="$1"
        set --
        # shellcheck disable=SC1090
        source "$setup"
        install_nvim_linux
      ' _ "$SETUP_SH" 2>&1
  )" || {
    echo "FAIL: install_nvim_linux skip path failed: $out" >&2
    return 1
  }

  assert_contains "$out" "already installed" "skips when Neovim >= 0.9.0"
  [[ ! -e "$HOME/curl-was-called" ]] || {
    echo "FAIL: skip path unexpectedly accessed network" >&2
    return 1
  }
  pass "nvim linux skips when already present ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_linux_prefers_nvim_cache
test_linux_download_uses_pinned_url
test_linux_skips_when_nvim_present

echo "PASS: nvim suite complete ($DEVTOOLS_TEST_PROFILE)"
