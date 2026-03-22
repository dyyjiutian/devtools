-- ============================================================
-- LazyGit: Git TUI integration
-- ============================================================

return {
  "kdheepak/lazygit.nvim",
  cmd = {
    "LazyGit",
    "LazyGitConfig",
    "LazyGitCurrentFile",
    "LazyGitFilter",
    "LazyGitFilterCurrentFile",
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  keys = {
    { "<leader>gg", "<cmd>LazyGit<cr>", desc = "Open Lazy[G]it" },
    { "<leader>gf", "<cmd>LazyGitCurrentFile<cr>", desc = "Lazy[G]it current [F]ile" },
    { "<leader>gc", "<cmd>LazyGitConfig<cr>", desc = "Lazy[G]it [C]onfig" },
  },
}
