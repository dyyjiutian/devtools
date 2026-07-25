-- ============================================================
-- Treesitter: Syntax Highlighting
-- ============================================================

return {
  "nvim-treesitter/nvim-treesitter",
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
    auto_install = true,
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
    require("nvim-treesitter").setup(opts)
  end,
}
