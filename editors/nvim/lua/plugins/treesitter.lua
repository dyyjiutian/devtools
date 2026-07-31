-- ============================================================
-- Treesitter: Syntax Highlighting
-- ============================================================

-- Pinned to master: the default branch is now the rewrite, which needs Neovim
-- 0.12+, drops parsers.ft_to_lang() that telescope 0.1.x previewers call, and
-- ignores the ensure_installed/highlight/indent options below.
return {
  "nvim-treesitter/nvim-treesitter",
  branch = "master",
  build = ":TSUpdate",
  opts = {
    ensure_installed = {
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
    },
    -- ensure_installed + Lazy build=:TSUpdate already install parsers; auto_install
    -- can race the same lang and surface "Error during tarball extraction".
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
  },
  config = function(_, opts)
    -- curl+tar archive downloads often fail behind flaky GitHub access; git clone
    -- is more reliable for ensure_installed / :TSUpdate during setup.sh --update.
    require("nvim-treesitter.install").prefer_git = true
    require("nvim-treesitter.configs").setup(opts)
  end,
}
