-- ============================================================
-- Treesitter: Syntax Highlighting
-- ============================================================

-- Upstream split nvim-treesitter in two: `main` is a full incompatible rewrite
-- that requires Neovim 0.12+ and enables nothing by default; `master` is the
-- locked legacy branch for Neovim <= 0.11 (kept here because the Linux baseline
-- pins Neovim 0.10.4 for Alinux 3 / glibc 2.32). Branch on the host version so
-- this one file covers both platforms.
local IS_012 = vim.fn.has("nvim-0.12") == 1

local PARSERS = {
  "bash",
  "c",
  "cpp",
  "css",
  "dockerfile",
  "go",
  "html",
  "java",
  "javascript",
  "json",
  "lua",
  "luadoc",
  "markdown",
  "markdown_inline",
  "python",
  "query",
  "regex",
  "rust",
  "typescript",
  "vim",
  "vimdoc",
  "yaml",
}

-- main (rewrite): parsers land in stdpath("data")/site, highlighting and indent
-- are opt-in (the rewrite ignores ensure_installed/highlight/indent options),
-- and incremental_selection does not exist.
local function setup_rewrite()
  require("nvim-treesitter").setup {
    install_dir = vim.fn.stdpath("data") .. "/site",
  }
  -- The rewrite ignores ensure_installed; seed parsers explicitly. This is a
  -- no-op once installed. pcall so a missing tree-sitter-cli cannot brick
  -- startup; setup.sh installs tree-sitter on macOS before the first Lazy sync.
  pcall(function()
    require("nvim-treesitter").install(PARSERS):wait(120000)
  end)

  local grp = vim.api.nvim_create_augroup("devtools-treesitter", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = grp,
    callback = function()
      -- Highlighting is not auto-enabled on the rewrite; opt in per filetype.
      -- pcall: buffers without a parser start is a harmless no-op.
      pcall(vim.treesitter.start)
      -- Experimental treesitter indentation (mirrors legacy config's broad scope).
      if vim.bo.filetype ~= "ruby" then
        vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end
    end,
    desc = "Enable treesitter highlighting and indentation",
  })
end

-- master (legacy): configs.setup drives highlight/indent/incremental_selection.
local function setup_legacy()
  -- curl+tar archive downloads often fail behind flaky GitHub access; git clone
  -- is more reliable for ensure_installed / :TSUpdate during setup.sh --update.
  require("nvim-treesitter.install").prefer_git = true
  -- ensure_installed + Lazy build=:TSUpdate already install parsers; auto_install
  -- can race the same lang and surface "Error during tarball extraction".
  require("nvim-treesitter.configs").setup {
    ensure_installed = PARSERS,
    auto_install = false,
    highlight = {
      enable = true,
      additional_vim_regex_highlighting = { "ruby" },
    },
    indent = { enable = true, disable = { "ruby" } },
    incremental_selection = {
      enable = true,
      keymaps = {
        init_selection = "<C-space>",
        node_incremental = "<C-space>",
        scope_incremental = false,
        node_decremental = "<bs>",
      },
    },
  }
end

return {
  "nvim-treesitter/nvim-treesitter",
  branch = IS_012 and "main" or "master",
  lazy = false, -- upstream: the plugin does not support lazy-loading
  build = ":TSUpdate",
  config = IS_012 and setup_rewrite or setup_legacy,
}
