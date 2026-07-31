-- ============================================================
-- GitHub Copilot: AI ghost-text suggestions
-- Requires an active Copilot subscription and Node.js (already installed by
-- setup.sh). Run :Copilot auth once after install — it opens a device-flow
-- login in the browser and cannot be scripted.
-- ============================================================

return {
  "github/copilot.vim",
  event = "InsertEnter",
  init = function()
    -- <Tab> already selects the next nvim-cmp item; accept suggestions on
    -- <C-j> instead of fighting nvim-cmp over Tab. Must be set before the
    -- plugin's own plugin/copilot.vim runs, hence init() not config().
    vim.g.copilot_no_tab_map = true
  end,
  config = function()
    vim.keymap.set("i", "<C-j>", 'copilot#Accept("\\<CR>")', {
      expr = true,
      replace_keycodes = false,
      desc = "Accept Copilot suggestion",
    })
  end,
}
