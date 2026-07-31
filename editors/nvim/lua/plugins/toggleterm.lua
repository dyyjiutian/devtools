-- ============================================================
-- toggleterm.nvim: Integrated terminal
-- ============================================================

return {
  "akinsho/toggleterm.nvim",
  cmd = { "ToggleTerm", "TermExec" },
  keys = {
    { [[<C-\>]], desc = "Toggle terminal" },
    { "<leader>tv", "<cmd>ToggleTerm direction=vertical size=60<cr>", desc = "[T]erminal [V]ertical" },
    { "<leader>tF", "<cmd>ToggleTerm direction=float<cr>", desc = "[T]erminal [F]loating" },
  },
  opts = {
    open_mapping = [[<C-\>]],
    direction = "horizontal",
    size = 15,
    shade_terminals = true,
    start_in_insert = true,
    persist_size = true,
  },
}
