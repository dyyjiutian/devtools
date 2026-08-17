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

# Bazel runfiles expose lua/ as symlinks. macOS grep -R does not follow them.
_lua_grep_count() {
  local pattern="$1"
  { find -L "$MODULE_ROOT/lua" -name '*.lua' -exec grep -h -o "$pattern" {} + || true; } \
    | wc -l | tr -d ' '
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

test_treesitter_branches_by_nvim_version() {
  local treesitter setup
  treesitter="$(cat "$MODULE_ROOT/lua/plugins/treesitter.lua")"
  setup="$(cat "$SETUP_SH")"
  # Upstream: main is the rewrite (Neovim 0.12+); master is the locked legacy
  # branch (<= 0.11), kept for the Linux 0.10.4 / glibc 2.32 baseline.
  assert_contains "$treesitter" 'branch = IS_012 and "main" or "master"' "branches on host nvim version"
  assert_contains "$treesitter" 'lazy = false' "plugin does not support lazy-loading"
  assert_contains "$treesitter" 'require("nvim-treesitter").setup {' "rewrite setup entry point"
  assert_contains "$treesitter" 'require("nvim-treesitter.configs").setup {' "legacy setup entry point"
  assert_contains "$treesitter" "vim.treesitter.start" "rewrite enables highlighting explicitly"
  assert_contains "$treesitter" 'require("nvim-treesitter").install(PARSERS)' "rewrite seeds parsers explicitly"
  assert_contains "$treesitter" "prefer_git = true" "legacy prefers git over curl tarball downloads"
  assert_contains "$treesitter" "auto_install = false" "legacy disables auto_install to avoid TSUpdate races"
  assert_contains "$setup" "nvim-treesitter" "setup resets nvim-treesitter checkout"
  # `tree-sitter` formula ships only libtree-sitter; the rewrite needs the CLI.
  assert_contains "$setup" "tree-sitter-cli" "macOS installs tree-sitter-cli for the rewrite"
  pass "nvim treesitter branches by nvim version ($DEVTOOLS_TEST_PROFILE)"
}

test_copilot_plugin_wired() {
  local copilot completion setup readme hits
  copilot="$(cat "$MODULE_ROOT/lua/plugins/copilot.lua")"
  completion="$(cat "$MODULE_ROOT/lua/plugins/completion.lua")"
  setup="$(cat "$SETUP_SH")"
  readme="$(cat "$MODULE_ROOT/README.md")"

  assert_contains "$copilot" '"github/copilot.vim"' "installs copilot.vim"
  # Lazy-loaded after VimEnter; without cmd, :Copilot is missing until load.
  assert_contains "$copilot" 'cmd = "Copilot"' "registers :Copilot lazy stub"
  assert_contains "$copilot" 'event = "VeryLazy"' "loads on VeryLazy, not only InsertEnter"
  assert_contains "$copilot" 'copilot#Init' "calls Init after lazy load"
  assert_contains "$copilot" "vim.g.copilot_no_tab_map = true" "disables copilot's own Tab map"
  assert_contains "$copilot" '"i", "<C-j>"' "accepts suggestions on <C-j>"
  assert_contains "$copilot" "copilot#Accept" "wires the accept function"
  assert_contains "$copilot" '"i", "<C-S-g>"' "requests suggestions on <C-S-g>"
  assert_contains "$copilot" "copilot#Suggest" "wires the suggest function"
  assert_contains "$copilot" "cmp.close" "<C-S-g> closes cmp before suggesting"
  assert_not_contains "$copilot" '"i", "<C-g>"' "does not use bare <C-g> for suggest"
  assert_not_contains "$copilot" 'event = "InsertEnter"' "does not wait for InsertEnter to start"

  # Copilot's own Tab map stays off; our cmp <Tab> handler owns the key.
  assert_not_contains "$copilot" '"<Tab>"' "copilot.lua does not bind <Tab> itself"
  assert_contains "$completion" '["<Tab>"]' "cmp maps <Tab>"
  assert_not_contains "$completion" '["<S-Tab>"]' "cmp does not bind <S-Tab>"
  # <Tab> priority: cmp confirm → Copilot accept → indent. Never navigate.
  local tab_block
  tab_block="$(awk '/\["<Tab>"\]/,/\["<CR>"\]/' <<<"$completion")"
  assert_contains "$tab_block" "cmp.confirm" "cmp <Tab> confirms when the menu is open"
  assert_contains "$tab_block" "copilot#GetDisplayedSuggestion" \
    "cmp <Tab> checks for a displayed Copilot suggestion"
  assert_contains "$tab_block" "copilot#Accept" "cmp <Tab> can accept Copilot"
  # cmp.confirm must be checked before Copilot in the Tab handler body.
  local confirm_line accept_line
  confirm_line="$(printf '%s\n' "$tab_block" | grep -n 'cmp.confirm' | head -1 | cut -d: -f1)"
  accept_line="$(printf '%s\n' "$tab_block" | grep -n 'copilot#Accept' | head -1 | cut -d: -f1)"
  [[ -n "$confirm_line" && -n "$accept_line" && "$confirm_line" -lt "$accept_line" ]] || {
    echo "FAIL: cmp.confirm (line ${confirm_line:-?}) must precede copilot#Accept (line ${accept_line:-?}) in <Tab>" >&2
    return 1
  }
  assert_not_contains "$tab_block" "select_next_item" "cmp <Tab> does not navigate"
  assert_not_contains "$tab_block" "select_prev_item" "cmp <Tab> does not navigate prev"

  # <C-j> / <C-S-g> must be unique in insert mode across plugin specs.
  hits="$(_lua_grep_count '"i", *"<C-j>"')"
  [[ "$hits" == "1" ]] || {
    echo "FAIL: insert-mode <C-j> mapped $hits times, expected 1" >&2
    return 1
  }
  hits="$(_lua_grep_count '"i", *"<C-S-g>"')"
  [[ "$hits" == "1" ]] || {
    echo "FAIL: insert-mode <C-S-g> mapped $hits times, expected 1" >&2
    return 1
  }
  assert_not_contains "$completion" "<C-j>" "cmp does not also claim <C-j>"
  assert_not_contains "$completion" '["<C-S-g>"]' "cmp has no <C-S-g> mapping"
  assert_not_contains "$completion" '["<C-Space>"]' "does not bind tmux prefix <C-Space>"
  assert_not_contains "$completion" "cmp.mapping.complete" "no manual cmp complete shortcut"

  # <CR> mirrors <Tab>: cmp confirm → Copilot accept → newline.
  local cr_block
  cr_block="$(awk '/\["<CR>"\]/,/\["<C-l>"\]/' <<<"$completion")"
  assert_contains "$cr_block" "cmp.confirm" "<CR> confirms cmp when the menu is open"
  assert_contains "$cr_block" "copilot#GetDisplayedSuggestion" \
    "<CR> checks for a displayed Copilot suggestion before falling back"
  assert_contains "$cr_block" "copilot#Accept" "<CR> can accept the Copilot suggestion"
  confirm_line="$(printf '%s\n' "$cr_block" | grep -n 'cmp.confirm' | head -1 | cut -d: -f1)"
  accept_line="$(printf '%s\n' "$cr_block" | grep -n 'copilot#Accept' | head -1 | cut -d: -f1)"
  [[ -n "$confirm_line" && -n "$accept_line" && "$confirm_line" -lt "$accept_line" ]] || {
    echo "FAIL: cmp.confirm (line ${confirm_line:-?}) must precede copilot#Accept (line ${accept_line:-?}) in <CR>" >&2
    return 1
  }
  hits="$( { grep -o '\["<CR>"\]' <<<"$completion" || true; } | wc -l | tr -d ' ')"
  [[ "$hits" == "1" ]] || {
    echo "FAIL: cmp mapping table defines <CR> $hits times, expected 1" >&2
    return 1
  }

  assert_contains "$readme" ":Copilot auth" "README documents the manual sign-in step"
  assert_contains "$setup" ":Copilot auth" "setup output points to the manual sign-in step"
  pass "nvim copilot wired without clobbering cmp ($DEVTOOLS_TEST_PROFILE)"
}

test_lazy_cmd_stubs_for_user_commands() {
  local dap neotest
  dap="$(cat "$MODULE_ROOT/lua/plugins/dap.lua")"
  neotest="$(cat "$MODULE_ROOT/lua/plugins/neotest.lua")"

  # keys-only lazy load leaves :Dap* / :Neotest unavailable until a keymap fires.
  assert_contains "$dap" 'cmd = {' "dap declares lazy cmd stubs"
  assert_contains "$dap" '"DapContinue"' "dap stubs :DapContinue"
  assert_contains "$dap" '"DapToggleBreakpoint"' "dap stubs :DapToggleBreakpoint"
  assert_contains "$dap" '"DapTerminate"' "dap stubs :DapTerminate"
  assert_contains "$neotest" 'cmd = "Neotest"' "neotest stubs :Neotest"
  pass "nvim lazy cmd stubs for user commands ($DEVTOOLS_TEST_PROFILE)"
}

test_telescope_ignore_patterns_are_escaped() {
  local telescope
  # Comments mention the buggy patterns, so assert against code lines only.
  telescope="$(grep -v '^[[:space:]]*--' "$MODULE_ROOT/lua/plugins/telescope.lua")"
  # master (>= v0.11.7) for nvim 0.12+; 0.1.x calls nvim-treesitter legacy APIs
  # the main rewrite drops, and is kept for the nvim 0.10 baseline.
  assert_contains "$telescope" 'branch = IS_012 and "master" or "0.1.x"' "telescope branches on host nvim version"
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
  for key in "<leader>e" "<leader>q" "<leader>o" "<leader>tt" "<leader>cf" "<leader>sr"; do
    hits="$(_lua_grep_count "\"$key\"")"
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

test_lsp_mason_tools_preinstall_common_servers() {
  # MasonToolsInstallSync only waits on mason-tool-installer. Servers that live
  # solely in mason-lspconfig ensure_installed are started async and get killed
  # by headless qa!, so gd/gr on .sh files stay unmapped in the image.
  local tools
  tools="$(awk '/require\("mason-tool-installer"\)/,/debounce_hours/' \
    "$MODULE_ROOT/lua/plugins/lsp.lua")"
  for name in bashls lua_ls pyright jsonls yamlls ts_ls; do
    assert_contains "$tools" "\"$name\"" "mason-tool-installer waits for $name"
  done
  pass "nvim mason-tool-installer preinstalls common LSPs ($DEVTOOLS_TEST_PROFILE)"
}

test_setup_asserts_mason_bashls_when_strict() {
  local setup
  setup="$(cat "$SETUP_SH")"
  assert_contains "$setup" "_assert_mason_lsps_installed" \
    "setup verifies mason LSPs after install"
  assert_contains "$setup" "bash-language-server" \
    "strict setup requires bash-language-server"
  pass "nvim setup asserts mason bashls when strict ($DEVTOOLS_TEST_PROFILE)"
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
  assert_contains "$(cat "$cmd_log")" "TSUpdateSync" "update refreshes treesitter parsers"
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
  assert_contains "$setup" "_LAZY_SYNC_CMD='Lazy! sync'" "Lazy sync waits via bang command"
  assert_contains "$setup" '_nvim_headless "${_LAZY_SYNC_CMD}"' "Lazy sync is a single quoted argument"
  assert_contains "$setup" '_nvim_headless "TSUpdateSync"' "treesitter install is quoted"
  assert_contains "$setup" '_nvim_headless "MasonToolsInstallSync"' "Mason install is quoted"
  assert_contains "$setup" '_nvim_headless "MasonToolsUpdateSync"' "Mason update is quoted"
  # All plugin sync entry points go through helpers (no raw unquoted +Lazy!).
  assert_contains "$setup" '_sync_lazy_plugins' "uses _sync_lazy_plugins helper"
  assert_contains "$setup" '_assert_lazy_plugins_installed' "verifies plugins after sync"
  assert_contains "$setup" "NVIM_SETUP_STRICT" "image builds can fail on missing plugins"
  assert_contains "$setup" "NVIM_SETUP_QUIET" "image builds can suppress headless progress logs"
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

test_setup_strict_fails_when_mason_lsps_missing() {
  local alt_bin="$HOME/nvim-mason-strict-bin"
  local out

  mkdir -p "$alt_bin"
  rm -rf "$HOME/.local/share/nvim/mason"
  _devtools_write_exec "$alt_bin/nvim" '
if [[ "${1:-}" == "--version" ]]; then echo "NVIM v0.10.4"; fi
exit 0
'

  out="$(
    PATH="$alt_bin:$PATH" HOME="$HOME" NVIM_SETUP_STRICT=1 SETUP_NO_MAIN=1 /bin/bash -c '
      setup="$1"
      set --
      # shellcheck disable=SC1090
      source "$setup"
      _install_mason_tools
    ' _ "$SETUP_SH" 2>&1
  )" && {
    echo "FAIL: strict mason install succeeded without packages: $out" >&2
    return 1
  }
  assert_contains "$out" "mason package missing after install" \
    "strict mode reports missing mason LSPs"
  pass "nvim strict setup fails when mason LSPs are missing ($DEVTOOLS_TEST_PROFILE)"
}

test_setup_strict_fails_when_plugins_missing() {
  local alt_bin="$HOME/nvim-strict-bin"
  local out

  mkdir -p "$alt_bin"
  rm -rf "$HOME/.local/share/nvim/lazy"
  _devtools_write_exec "$alt_bin/nvim" '
if [[ "${1:-}" == "--version" ]]; then echo "NVIM v0.10.4"; fi
exit 0
'

  out="$(
    PATH="$alt_bin:$PATH" HOME="$HOME" NVIM_SETUP_STRICT=1 SETUP_NO_MAIN=1 /bin/bash -c '
      setup="$1"
      set --
      # shellcheck disable=SC1090
      source "$setup"
      _sync_lazy_plugins
    ' _ "$SETUP_SH" 2>&1
  )" && {
    echo "FAIL: strict sync succeeded without plugins: $out" >&2
    return 1
  }
  assert_contains "$out" "plugin missing after sync" "strict mode reports missing plugins"
  pass "nvim strict setup fails when plugins are missing ($DEVTOOLS_TEST_PROFILE)"
}

test_help
test_linux_prefers_nvim_cache
test_linux_download_uses_pinned_url
test_linux_skips_when_nvim_present
test_lsp_pins_for_nvim_010
test_lsp_registers_servers_when_mason_fails
test_lsp_covers_go_and_c
test_treesitter_branches_by_nvim_version
test_lazygit_pinned_for_nvim_010
test_leader_keys_are_unique
test_ide_plugins_present
test_ide_plugins_pinned_for_nvim_010
test_format_and_tools_wired
test_lsp_mason_tools_preinstall_common_servers
test_setup_asserts_mason_bashls_when_strict
test_copilot_plugin_wired
test_lazy_cmd_stubs_for_user_commands
test_telescope_ignore_patterns_are_escaped
test_update_syncs_config_then_plugins
test_restore_flag_removed
test_setup_quotes_lazy_sync
test_setup_strict_fails_when_mason_lsps_missing
test_setup_strict_fails_when_plugins_missing

echo "PASS: nvim suite complete ($DEVTOOLS_TEST_PROFILE)"
