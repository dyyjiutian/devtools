-- ============================================================
-- aerial.nvim: Code outline (IDEA's Structure panel)
-- ============================================================

-- Upstream keeps one branch per supported Neovim range and master's setup()
-- bails out with an error below the current baseline.
local function branch_for_host()
  if vim.fn.has("nvim-0.12") == 1 then
    return nil
  end
  if vim.fn.has("nvim-0.11") == 1 then
    return "nvim-0.11"
  end
  return "nvim-0.9"
end

return {
  "stevearc/aerial.nvim",
  branch = branch_for_host(),
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons",
  },
  cmd = { "AerialToggle", "AerialOpen", "AerialNavToggle" },
  keys = {
    { "<leader>o", "<cmd>AerialToggle!<cr>", desc = "Toggle code [O]utline" },
    { "<leader>O", "<cmd>AerialNavToggle<cr>", desc = "[O]utline navigation popup" },
  },
  opts = {
    backends = { "lsp", "treesitter", "markdown", "man" },
    layout = { min_width = 28 },
    attach_mode = "global",
    show_guides = true,
    filter_kind = false,
  },
}
