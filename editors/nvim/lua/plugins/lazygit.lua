-- ============================================================
-- LazyGit: Git TUI integration
-- ============================================================

-- Upstream moved to `vim.fn.jobstart(cmd, { term = true })`, an option that only
-- exists on Neovim 0.11+, so older hosts are pinned to the last termopen commit.
-- `cond and nil or value` always yields value in Lua, so branch explicitly.
local legacy_commit = nil
if vim.fn.has("nvim-0.11") == 0 then
  legacy_commit = "4839ab642962cc76bb1bf278427dc4c59be15072"
end

return {
  "kdheepak/lazygit.nvim",
  commit = legacy_commit,
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
