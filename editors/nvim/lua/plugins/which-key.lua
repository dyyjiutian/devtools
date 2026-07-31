-- ============================================================
-- Which-key: Keybinding helper
-- ============================================================

return {
  "folke/which-key.nvim",
  event = "VimEnter",
  config = function()
    require("which-key").setup()

    require("which-key").add({
      { "<leader>c", group = "[C]ode" },
      { "<leader>c_", hidden = true },
      { "<leader>d", group = "[D]ebug / [D]ocument" },
      { "<leader>d_", hidden = true },
      { "<leader>r", group = "[R]ename" },
      { "<leader>r_", hidden = true },
      { "<leader>s", group = "[S]earch" },
      { "<leader>s_", hidden = true },
      { "<leader>w", group = "[W]orkspace" },
      { "<leader>w_", hidden = true },
      { "<leader>t", group = "[T]est / [T]erminal" },
      { "<leader>t_", hidden = true },
      { "<leader>h", group = "Git [H]unk" },
      { "<leader>h_", hidden = true },
      { "<leader>g", group = "[G]it" },
      { "<leader>g_", hidden = true },
      { "<leader>f", group = "[F]ind" },
      { "<leader>f_", hidden = true },
      { "<leader>b", group = "[B]uffer" },
      { "<leader>b_", hidden = true },
    })
  end,
}
