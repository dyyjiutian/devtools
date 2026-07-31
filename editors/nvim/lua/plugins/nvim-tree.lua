-- ============================================================
-- nvim-tree: File Explorer
-- ============================================================

return {
  "nvim-tree/nvim-tree.lua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    require("nvim-tree").setup({
      sort_by = "case_sensitive",
      view = {
        width = 30,
      },
      renderer = {
        group_empty = true,
        icons = {
          show = {
            file = true,
            folder = true,
            folder_arrow = true,
            git = true,
          },
        },
      },
      filters = {
        dotfiles = false,
        custom = { "^.git$", "__pycache__", "node_modules", ".DS_Store" },
      },
      git = {
        enable = true,
        ignore = false,
      },
      actions = {
        open_file = {
          quit_on_open = false,
        },
      },
    })

    -- Keymaps: <leader>e belongs to the diagnostic float in config/keymaps.lua
    vim.keymap.set("n", "<leader>n", "<cmd>NvimTreeToggle<CR>", { desc = "Toggle file tree ([N]vimTree)" })
    vim.keymap.set("n", "<leader>fe", "<cmd>NvimTreeFindFile<CR>", { desc = "[F]ind file in [E]xplorer" })
  end,
}
