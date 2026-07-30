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

# Build a minimal nvim-linux-x86_64 tarball matching upstream layout.
make_fake_nvim_tarball() {
  local dest="$1"
  local payload
  payload="$(mktemp -d "${TMPDIR:-/tmp}/nvim-fake.XXXXXX")"
  mkdir -p "$payload/nvim-linux-x86_64/bin"
  cat >"$payload/nvim-linux-x86_64/bin/nvim" <<'EOF'
#!/usr/bin/env bash
echo "NVIM v0.10.4 (fake tarball)"
EOF
  chmod +x "$payload/nvim-linux-x86_64/bin/nvim"
  mkdir -p "$(dirname "$dest")"
  tar -czf "$dest" -C "$payload" nvim-linux-x86_64
  rm -rf "$payload"
}

test_help() {
  local out
  out="$(bash "$SETUP_SH" --help 2>&1)"
  assert_contains "$out" "Neovim" "help mentions Neovim"
  assert_contains "$out" "0.10.4" "help mentions pinned version"
  assert_contains "$out" "tarball" "help mentions tarball install"
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
  local cache_name="nvim-linux-x86_64-v0.10.4.tar.gz"
  local cached="$DEVTOOLS_CACHE_DIR/binaries/$cache_name"
  local out

  mkdir -p "$DEVTOOLS_CACHE_DIR/binaries" "$alt_bin" "$HOME/.local/bin"
  rm -f "$HOME/curl-was-called" "$HOME/.local/bin/nvim"
  rm -rf "$HOME/.local/nvim"

  make_fake_nvim_tarball "$cached"
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
  assert_file_exists "$HOME/.local/nvim/bin/nvim" "nvim tree installed under ~/.local/nvim"
  assert_symlink "$HOME/.local/bin/nvim" "nvim symlink in ~/.local/bin"
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
  local fixture="$HOME/fake-nvim.tar.gz"

  mkdir -p "$alt_bin" "$HOME/.local/bin" "$DEVTOOLS_CACHE_DIR/binaries"
  rm -f "$DEVTOOLS_CACHE_DIR/binaries"/nvim-*.tar.gz "$DEVTOOLS_CACHE_DIR/binaries"/nvim-*.appimage \
    "$url_log" "$HOME/.local/bin/nvim"
  rm -rf "$HOME/.local/nvim"
  make_fake_nvim_tarball "$fixture"

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
cp "$HOME/fake-nvim.tar.gz" "$out"
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
  assert_contains "$(cat "$url_log")" "v0.10.4/nvim-linux-x86_64.tar.gz" "downloads pinned v0.10.4 tarball"
  assert_not_contains "$(cat "$url_log")" "appimage" "does not download AppImage"
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

test_lsp_pins_for_nvim_010() {
  local lsp
  lsp="$(cat "$MODULE_ROOT/lua/plugins/lsp.lua")"
  assert_contains "$lsp" 'version = "v1.8.0"' "pins nvim-lspconfig for 0.10"
  assert_contains "$lsp" 'version = "v1.11.0"' "pins mason.nvim v1"
  assert_contains "$lsp" 'version = "v1.32.0"' "pins mason-lspconfig v1"
  assert_contains "$lsp" "debounce_hours = 24" "debounces tool installer"
  assert_not_contains "$lsp" "vim.tbl_keys(servers" "does not auto-install every LSP via tool-installer"
  pass "nvim lsp pins for 0.10 ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_linux_prefers_nvim_cache
test_linux_download_uses_pinned_url
test_linux_skips_when_nvim_present
test_lsp_pins_for_nvim_010

echo "PASS: nvim suite complete ($DEVTOOLS_TEST_PROFILE)"
