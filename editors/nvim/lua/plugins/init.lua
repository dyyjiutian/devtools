-- ============================================================
-- Plugin Specifications
-- ============================================================

return {
  -- Colorscheme
  {
    "folke/tokyonight.nvim",
    priority = 1000,
    init = function()
      vim.cmd.colorscheme("tokyonight-night")
    end,
  },

  -- File explorer
  require("plugins.nvim-tree"),

  -- Fuzzy finder
  require("plugins.telescope"),

  -- LSP Configuration
  require("plugins.lsp"),

  -- Auto-completion
  require("plugins.completion"),

  -- Syntax highlighting
  require("plugins.treesitter"),

  -- Git integration
  require("plugins.git"),

  -- Status line
  require("plugins.lualine"),

  -- Buffer line
  require("plugins.bufferline"),

  -- Auto pairs
  require("plugins.autopairs"),

  -- Comment
  require("plugins.comment"),

  -- Indent blankline
  require("plugins.indent-blankline"),

  -- Which-key (keybinding helper)
  require("plugins.which-key"),

  -- Gitsigns
  require("plugins.gitsigns"),

  -- Surround
  require("plugins.surround"),

  -- Trouble (diagnostics)
  require("plugins.trouble"),

  -- Flash (enhanced search)
  require("plugins.flash"),

  -- Todo comments
  require("plugins.todo-comments"),

  -- LazyGit
  require("plugins.lazygit"),
}
