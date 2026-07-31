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

test_lsp_registers_servers_when_mason_fails() {
  local lsp
  lsp="$(cat "$MODULE_ROOT/lua/plugins/lsp.lua")"
  assert_contains "$lsp" 'local ok, err = pcall(function()' "wraps mason-lspconfig setup in pcall"
  assert_contains "$lsp" 'handlers = { setup_server }' "handler reuses setup_server"
  assert_contains "$lsp" 'if not ok then' "falls back when mason-lspconfig errors"
  assert_contains "$lsp" 'pcall(setup_server, server_name)' "registers servers directly on fallback"
  assert_contains "$lsp" 'server_installed(server_name)' "fallback only registers installed servers"
  pass "nvim lsp survives mason-lspconfig failure ($DEVTOOLS_TEST_PROFILE)"
}

test_lsp_covers_go_and_c() {
  local lsp
  lsp="$(cat "$MODULE_ROOT/lua/plugins/lsp.lua")"
  assert_contains "$lsp" "gopls = {}" "declares gopls server config"
  assert_contains "$lsp" '"gopls",' "auto-installs gopls"
  assert_contains "$lsp" '"clangd",' "auto-installs clangd"
  pass "nvim lsp covers Go and C/C++ ($DEVTOOLS_TEST_PROFILE)"
}

test_treesitter_pinned_to_master() {
  local treesitter setup
  treesitter="$(cat "$MODULE_ROOT/lua/plugins/treesitter.lua")"
  setup="$(cat "$SETUP_SH")"
  # Upstream's default branch is the rewrite, which drops parsers.ft_to_lang()
  # that telescope 0.1.x previewers call.
  assert_contains "$treesitter" 'branch = "master"' "pins nvim-treesitter to master"
  assert_contains "$treesitter" 'require("nvim-treesitter.configs").setup(opts)' "uses master setup entry point"
  assert_not_contains "$treesitter" 'require("nvim-treesitter").setup(opts)' "no rewrite-style setup call"
  assert_contains "$setup" "nvim-treesitter" "setup resets nvim-treesitter checkout"
  pass "nvim treesitter pinned to master ($DEVTOOLS_TEST_PROFILE)"
}

test_telescope_ignore_patterns_are_escaped() {
  local telescope
  # Comments mention the buggy patterns, so assert against code lines only.
  telescope="$(grep -v '^[[:space:]]*--' "$MODULE_ROOT/lua/plugins/telescope.lua")"
  assert_contains "$telescope" '"/%.git/"' "escapes the dot in .git"
  assert_contains "$telescope" '"%.pyc$"' "uses a Lua pattern for .pyc"
  # Bare ".git" matches any char before "git", e.g. ~/workspace/github/.
  assert_not_contains "$telescope" '".git"' "no unescaped .git pattern"
  assert_not_contains "$telescope" '"*.pyc"' "no glob-style *.pyc pattern"
  assert_not_contains "$telescope" '".DS_Store"' "no unescaped .DS_Store pattern"
  pass "nvim telescope ignore patterns escaped ($DEVTOOLS_TEST_PROFILE)"
}

test_lazygit_pinned_for_nvim_010() {
  local lazygit setup
  lazygit="$(cat "$MODULE_ROOT/lua/plugins/lazygit.lua")"
  setup="$(cat "$SETUP_SH")"
  # jobstart's `term` option only exists on 0.11+, so older hosts need termopen.
  assert_contains "$lazygit" 'vim.fn.has("nvim-0.11") == 0' "pins only below Neovim 0.11"
  assert_contains "$lazygit" '4839ab642962cc76bb1bf278427dc4c59be15072' "pins last termopen commit"
  assert_contains "$lazygit" 'commit = legacy_commit' "applies the conditional pin"
  assert_contains "$setup" "lazy_root}/lazygit.nvim" "setup resets lazygit checkout"
  pass "nvim lazygit pinned below 0.11 ($DEVTOOLS_TEST_PROFILE)"
}

test_leader_keys_are_unique() {
  local tree keymaps key hits
  tree="$(cat "$MODULE_ROOT/lua/plugins/nvim-tree.lua")"
  keymaps="$(cat "$MODULE_ROOT/lua/config/keymaps.lua")"
  assert_contains "$tree" '"<leader>n", "<cmd>NvimTreeToggle<CR>"' "file tree toggles on <leader>n"
  assert_contains "$keymaps" '"<leader>e", vim.diagnostic.open_float' "<leader>e stays on diagnostics"
  assert_not_contains "$keymaps" "vim.diagnostic.setloclist" "loclist mapping dropped for trouble.nvim"
  # A bare <leader>d would shadow the whole debug group behind timeoutlen.
  assert_not_contains "$keymaps" '"<leader>d", [[' "no bare <leader>d delete mapping"

  # Mapping one key twice means load order silently decides the winner.
  # -R follows symlinks: bazel runfiles expose lua/ as links.
  for key in "<leader>e" "<leader>q" "<leader>o" "<leader>tt" "<leader>cf" "<leader>sr"; do
    hits="$( { grep -Rho "\"$key\"" "$MODULE_ROOT/lua" || true; } | wc -l | tr -d ' ')"
    [[ "$hits" == "1" ]] || {
      echo "FAIL: $key mapped $hits times, expected 1" >&2
      return 1
    }
  done
  assert_contains "$(bash "$SETUP_SH" --help 2>&1)" "<Space>n" "help documents the new tree key"
  pass "nvim leader keys unique ($DEVTOOLS_TEST_PROFILE)"
}

test_ide_plugins_present() {
  local plugins
  # Comments name the rejected alternatives, so assert against code lines only.
  plugins="$(cat "$MODULE_ROOT"/lua/plugins/*.lua | grep -v '^[[:space:]]*--')"
  assert_contains "$plugins" '"stevearc/conform.nvim"' "format on save via conform"
  assert_contains "$plugins" '"mfussenegger/nvim-lint"' "linters via nvim-lint"
  assert_contains "$plugins" '"mfussenegger/nvim-dap"' "debugger via nvim-dap"
  assert_contains "$plugins" '"rcarriga/nvim-dap-ui"' "debugger UI"
  assert_contains "$plugins" '"nvim-neotest/neotest"' "test runner"
  assert_contains "$plugins" '"stevearc/aerial.nvim"' "code outline"
  assert_contains "$plugins" '"MagicDuck/grug-far.nvim"' "project search and replace"
  assert_contains "$plugins" '"akinsho/toggleterm.nvim"' "integrated terminal"
  assert_contains "$plugins" '"nvim-treesitter/nvim-treesitter-context"' "sticky context"
  assert_contains "$plugins" '"hrsh7th/cmp-buffer"' "buffer completion source"
  assert_contains "$plugins" '"hrsh7th/cmp-cmdline"' "cmdline completion source"

  # neotest-go is unmaintained; mason-nvim-dap couples to pinned Mason v1 internals.
  assert_not_contains "$plugins" "neotest-go\"" "does not use unmaintained neotest-go"
  assert_not_contains "$plugins" "mason-nvim-dap" "does not depend on mason-nvim-dap"
  pass "nvim IDE plugins declared ($DEVTOOLS_TEST_PROFILE)"
}

test_ide_plugins_pinned_for_nvim_010() {
  local aerial grugfar setup
  aerial="$(cat "$MODULE_ROOT/lua/plugins/aerial.lua")"
  grugfar="$(cat "$MODULE_ROOT/lua/plugins/grug-far.lua")"
  setup="$(cat "$SETUP_SH")"

  # aerial master errors below 0.12; grug-far refuses to load below 0.11.
  assert_contains "$aerial" 'vim.fn.has("nvim-0.12")' "aerial checks for 0.12"
  assert_contains "$aerial" '"nvim-0.9"' "aerial falls back to the 0.9 branch"
  assert_contains "$aerial" "branch = branch_for_host()" "aerial applies the conditional branch"
  assert_contains "$grugfar" 'vim.fn.has("nvim-0.11")' "grug-far checks for 0.11"
  assert_contains "$grugfar" '"1.6.6"' "grug-far pins the last 0.10-compatible tag"

  # `cond and nil or value` always yields value; conditional pins must branch.
  assert_not_contains "$aerial" "== 1 and nil or" "aerial avoids the and/or nil pitfall"
  assert_not_contains "$grugfar" "== 1 and nil or" "grug-far avoids the and/or nil pitfall"

  assert_contains "$setup" "lazy_root}/aerial.nvim" "setup resets aerial checkout"
  assert_contains "$setup" "lazy_root}/grug-far.nvim" "setup resets grug-far checkout"
  pass "nvim IDE plugins pinned for 0.10 ($DEVTOOLS_TEST_PROFILE)"
}

test_format_and_tools_wired() {
  local format lint autocmds lsp
  format="$(cat "$MODULE_ROOT/lua/plugins/format.lua")"
  lint="$(cat "$MODULE_ROOT/lua/plugins/lint.lua")"
  autocmds="$(cat "$MODULE_ROOT/lua/config/autocmds.lua")"
  lsp="$(cat "$MODULE_ROOT/lua/plugins/lsp.lua")"

  assert_contains "$format" "format_on_save" "conform formats on save"
  assert_contains "$format" "FormatToggle" "autoformat can be switched off"

  # try_lint() errors with ENOENT on every save when a linter is not installed.
  assert_contains "$lint" "vim.fn.executable(cmd) == 1" "lint skips missing binaries"
  assert_contains "$lint" "lint.try_lint(names)" "lint runs only installed linters"

  # A blanket trim on BufWritePre fights conform and eats markdown hard breaks.
  assert_not_contains "$autocmds" 's/\\s\\+$//e' "no blanket trailing-whitespace autocmd"

  for tool in ruff shellcheck debugpy delve; do
    assert_contains "$lsp" "\"$tool\"," "mason installs $tool"
  done
  pass "nvim format and mason tools wired ($DEVTOOLS_TEST_PROFILE)"
}

test_update_syncs_config_then_plugins() {
  local alt_bin="$HOME/nvim-update-bin"
  local cfg="$HOME/.config/nvim"
  local cmd_log="$HOME/nvim-update-cmd.log"
  local out backups

  mkdir -p "$alt_bin"
  rm -rf "$cfg" "$HOME/.config/nvim.bak."* "$HOME/.local/share/nvim/lazy"
  rm -f "$cmd_log"

  _devtools_write_exec "$alt_bin/nvim" '
printf "%s\n" "$*" >>"$HOME/nvim-update-cmd.log"
if [[ "${1:-}" == "--version" ]]; then echo "NVIM v0.10.4"; fi
exit 0
'

  # Pre-existing hand-written config must be preserved as a backup exactly once.
  mkdir -p "$cfg/lua"
  echo "handwritten" >"$cfg/init.lua"

  _run_update() {
    PATH="$alt_bin:$PATH" HOME="$HOME" SETUP_NO_MAIN=1 /bin/bash -c '
      setup="$1"
      set --
      # shellcheck disable=SC1090
      source "$setup"
      update_all
    ' _ "$SETUP_SH" 2>&1
  }

  out="$(_run_update)" || {
    echo "FAIL: update_all failed: $out" >&2
    return 1
  }

  assert_file_exists "$cfg/lua/plugins/nvim-tree.lua" "update copies lua/ config"
  assert_file_exists "$cfg/.devtools-nvim" "update writes managed marker"
  assert_not_contains "$(cat "$cfg/init.lua")" "handwritten" "update overwrites init.lua"
  assert_contains "$(cat "$cmd_log")" "Lazy! sync" "update syncs plugins"
  assert_contains "$(cat "$cmd_log")" "MasonToolsUpdateSync" "update refreshes LSP servers"

  backups="$(find "$HOME/.config" -maxdepth 1 -name 'nvim.bak.*' | wc -l | tr -d ' ')"
  [[ "$backups" == "1" ]] || {
    echo "FAIL: expected 1 backup of the unmanaged config, found $backups" >&2
    return 1
  }

  # Rerun: managed config is overwritten in place, stale modules disappear.
  echo "stale" >"$cfg/lua/obsolete.lua"
  out="$(_run_update)" || {
    echo "FAIL: second update_all failed: $out" >&2
    return 1
  }

  [[ ! -e "$cfg/lua/obsolete.lua" ]] || {
    echo "FAIL: stale lua module survived update" >&2
    return 1
  }
  backups="$(find "$HOME/.config" -maxdepth 1 -name 'nvim.bak.*' | wc -l | tr -d ' ')"
  [[ "$backups" == "1" ]] || {
    echo "FAIL: rerun created extra backups (found $backups)" >&2
    return 1
  }
  pass "nvim update syncs config and plugins ($DEVTOOLS_TEST_PROFILE)"
}

test_restore_flag_removed() {
  local setup out
  setup="$(cat "$SETUP_SH")"
  assert_not_contains "$setup" "restore_config" "restore_config is gone"
  assert_not_contains "$setup" "--restore" "no --restore flag"
  out="$(bash "$SETUP_SH" --restore 2>&1)" && {
    echo "FAIL: --restore still accepted" >&2
    return 1
  }
  assert_contains "$out" "Unknown option" "--restore is rejected"
  pass "nvim --restore removed ($DEVTOOLS_TEST_PROFILE)"
}

test_setup_quotes_lazy_sync() {
  local setup
  setup="$(cat "$SETUP_SH")"
  assert_contains "$setup" '_nvim_headless() {' "defines quoted headless helper"
  assert_contains "$setup" 'nvim --headless -c "$cmd" -c "qa!"' "passes Ex cmd as one -c argument"
  assert_contains "$setup" '_nvim_headless "Lazy! sync"' "Lazy sync is a single quoted argument"
  assert_contains "$setup" '_nvim_headless "MasonToolsInstallSync"' "Mason install is quoted"
  assert_contains "$setup" '_nvim_headless "MasonToolsUpdateSync"' "Mason update is quoted"
  # All plugin sync entry points go through helpers (no raw unquoted +Lazy!).
  assert_contains "$setup" '_sync_lazy_plugins' "uses _sync_lazy_plugins helper"
  local raw_hits
  raw_hits="$(printf '%s\n' "$setup" | grep -E 'nvim --headless' | grep -v '_nvim_headless\|#' || true)"
  # Only the helper body may call nvim --headless directly.
  assert_contains "$raw_hits" 'nvim --headless -c "$cmd" -c "qa!"' "only helper invokes nvim --headless"
  if printf '%s\n' "$setup" | grep -Eq -- 'nvim --headless \+Lazy! sync'; then
    echo "FAIL: found unquoted '+Lazy! sync' which shell splits" >&2
    return 1
  fi
  pass "nvim setup quotes Lazy sync ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_linux_prefers_nvim_cache
test_linux_download_uses_pinned_url
test_linux_skips_when_nvim_present
test_lsp_pins_for_nvim_010
test_lsp_registers_servers_when_mason_fails
test_lsp_covers_go_and_c
test_treesitter_pinned_to_master
test_lazygit_pinned_for_nvim_010
test_leader_keys_are_unique
test_ide_plugins_present
test_ide_plugins_pinned_for_nvim_010
test_format_and_tools_wired
test_telescope_ignore_patterns_are_escaped
test_update_syncs_config_then_plugins
test_restore_flag_removed
test_setup_quotes_lazy_sync

echo "PASS: nvim suite complete ($DEVTOOLS_TEST_PROFILE)"
