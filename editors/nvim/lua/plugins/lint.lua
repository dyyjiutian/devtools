-- ============================================================
-- nvim-lint: Linters that are not language servers
-- ============================================================

return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPost", "BufNewFile", "BufWritePost" },
  config = function()
    local lint = require("lint")

    -- Go and Lua diagnostics already come from gopls / lua_ls.
    lint.linters_by_ft = {
      python = { "ruff" },
      sh = { "shellcheck" },
      bash = { "shellcheck" },
    }

    -- try_lint() raises "Error running <linter>: ENOENT" on every save when the
    -- binary is absent, e.g. before Mason has installed it. Run only what exists.
    local function installed_linters(ft)
      local names = {}
      for _, name in ipairs(lint.linters_by_ft[ft] or {}) do
        local linter = lint.linters[name]
        local cmd = type(linter) == "table" and linter.cmd or nil
        if type(cmd) == "function" then
          cmd = cmd()
        end
        if type(cmd) == "string" and vim.fn.executable(cmd) == 1 then
          table.insert(names, name)
        end
      end
      return names
    end

    local group = vim.api.nvim_create_augroup("nvim-lint-on-write", { clear = true })
    vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
      group = group,
      callback = function()
        -- Lint modifiable file buffers only; skip help, quickfix and terminals.
        if not vim.bo.modifiable or vim.bo.buftype ~= "" then
          return
        end
        local names = installed_linters(vim.bo.filetype)
        if #names > 0 then
          lint.try_lint(names)
        end
      end,
    })
  end,
}
