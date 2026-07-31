-- ============================================================
-- treesitter-context: Sticky scope header (VSCode sticky scroll)
-- ============================================================

return {
  "nvim-treesitter/nvim-treesitter-context",
  event = { "BufReadPost", "BufNewFile" },
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  -- No keymap: [c / ]c already belong to gitsigns hunk navigation.
  opts = {
    max_lines = 3,
    multiline_threshold = 1,
    trim_scope = "outer",
    mode = "cursor",
  },
}
