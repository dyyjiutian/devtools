-- ============================================================
-- Git Integration
-- ============================================================

return {
  "tpope/vim-fugitive",
  config = function()
    vim.keymap.set("n", "<leader>gs", vim.cmd.Git, { desc = "[G]it [S]tatus" })
    vim.keymap.set("n", "<leader>gd", ":Gdiffsplit<CR>", { desc = "[G]it [D]iff" })
    vim.keymap.set("n", "<leader>gb", ":Git blame<CR>", { desc = "[G]it [B]lame" })
    vim.keymap.set("n", "<leader>gl", ":Git log --oneline<CR>", { desc = "[G]it [L]og" })
    vim.keymap.set("n", "<leader>gp", ":Git push<CR>", { desc = "[G]it [P]ush" })
    vim.keymap.set("n", "<leader>gP", ":Git pull<CR>", { desc = "[G]it [P]ull" })
  end,
}
