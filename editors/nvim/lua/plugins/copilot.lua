-- ============================================================
-- GitHub Copilot: AI ghost-text suggestions
-- Requires an active Copilot subscription and Node.js (already installed by
-- setup.sh). Run :Copilot auth once after install — it opens a device-flow
-- login in the browser and cannot be scripted.
-- ============================================================

return {
  "github/copilot.vim",
  -- cmd stub so :Copilot auth works before the first InsertEnter load.
  cmd = "Copilot",
  event = "InsertEnter",
  init = function()
    -- Disable copilot.vim's own <Tab> map; completion.lua owns <Tab>/<CR>
    -- (Copilot accept → cmp confirm → indent/newline). Keep <C-j> / <C-g>.
    -- Must be set before plugin/copilot.vim runs, hence init() not config().
    vim.g.copilot_no_tab_map = true
  end,
  config = function()
    vim.keymap.set("i", "<C-j>", 'copilot#Accept("\\<CR>")', {
      expr = true,
      replace_keycodes = false,
      desc = "Accept Copilot suggestion",
    })
    -- Close cmp first so ghost text is visible, then request a suggestion.
    vim.keymap.set("i", "<C-g>", function()
      local ok_cmp, cmp = pcall(require, "cmp")
      if ok_cmp and cmp.visible() then
        cmp.close()
      end
      pcall(vim.fn["copilot#Suggest"])
    end, { desc = "Request Copilot suggestion" })
  end,
}
