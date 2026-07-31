-- ============================================================
-- GitHub Copilot: AI ghost-text suggestions
-- Requires an active Copilot subscription and Node.js (already installed by
-- setup.sh). Run :Copilot auth once after install — it opens a device-flow
-- login in the browser and cannot be scripted.
-- ============================================================

return {
  "github/copilot.vim",
  -- cmd stub so :Copilot works before the plugin body loads.
  cmd = "Copilot",
  -- VeryLazy (not InsertEnter): plugin's own autocmd only calls copilot#Init on
  -- VimEnter; loading after that left the agent dead until :Copilot restart.
  event = "VeryLazy",
  init = function()
    -- Disable copilot.vim's own <Tab> map; completion.lua owns <Tab>/<CR>
    -- (cmp confirm → Copilot accept → indent/newline). Keep <C-j> / <C-S-g>.
    -- Must be set before plugin/copilot.vim runs, hence init() not config().
    vim.g.copilot_no_tab_map = true
  end,
  config = function()
    -- Kick the language server if VimEnter already fired before we loaded.
    vim.schedule(function()
      pcall(vim.fn["copilot#Init"])
    end)

    vim.keymap.set("i", "<C-j>", 'copilot#Accept("\\<CR>")', {
      expr = true,
      replace_keycodes = false,
      desc = "Accept Copilot suggestion",
    })
    -- Manual suggest (Ctrl-Shift-G). Close cmp first so ghost text is visible.
    -- Needs terminal/tmux extended-keys (csi-u) in some hosts.
    vim.keymap.set("i", "<C-S-g>", function()
      local ok_cmp, cmp = pcall(require, "cmp")
      if ok_cmp and cmp.visible() then
        cmp.close()
      end
      pcall(vim.fn["copilot#Suggest"])
    end, { desc = "Request Copilot suggestion" })
  end,
}
