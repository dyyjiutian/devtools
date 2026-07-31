-- ============================================================
-- grug-far.nvim: Project-wide search and replace (VSCode Ctrl+Shift+H)
-- ============================================================

-- plugin/grug-far.lua refuses to load below 0.11 on the default branch; 1.6.6
-- is the last tag before that gate and still supports 0.10.
local function version_for_host()
  if vim.fn.has("nvim-0.11") == 1 then
    return nil
  end
  return "1.6.6"
end

return {
  "MagicDuck/grug-far.nvim",
  version = version_for_host(),
  cmd = { "GrugFar" },
  keys = {
    {
      "<leader>sr",
      function()
        require("grug-far").open({ transient = true })
      end,
      desc = "[S]earch and [R]eplace in project",
    },
    {
      "<leader>sw",
      function()
        require("grug-far").open({ transient = true, prefills = { search = vim.fn.expand("<cword>") } })
      end,
      desc = "[S]earch and replace [W]ord under cursor",
    },
  },
  opts = {},
}
