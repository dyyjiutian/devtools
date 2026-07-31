-- ============================================================
-- nvim-dap: Debugger (VSCode-style F5 / F9 / F10 / F11 loop)
-- Adapters come from Mason (debugpy, delve) via mason-tool-installer;
-- mason-nvim-dap is deliberately not used because it reaches into
-- mason-core internals that are tied to the pinned Mason v1.
-- ============================================================

-- debugpy runs from Mason's own venv. Without it there is no Python adapter to
-- register, so skip setup rather than pointing dap at an interpreter that
-- cannot import debugpy.
local function debugpy_python()
  local venv = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"
  return vim.fn.executable(venv) == 1 and venv or nil
end

return {
  "mfussenegger/nvim-dap",
  dependencies = {
    { "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
    { "theHamsta/nvim-dap-virtual-text", opts = {} },
    "mfussenegger/nvim-dap-python",
    { "leoluz/nvim-dap-go", opts = {} },
  },
  -- keys alone leave :Dap* unavailable until a keymap fires.
  cmd = {
    "DapContinue",
    "DapToggleBreakpoint",
    "DapClearBreakpoints",
    "DapToggleRepl",
    "DapStepOver",
    "DapStepInto",
    "DapStepOut",
    "DapPause",
    "DapTerminate",
    "DapDisconnect",
    "DapRestartFrame",
    "DapNew",
    "DapEval",
    "DapSetLogLevel",
    "DapShowLog",
  },
  keys = {
    { "<F5>", function() require("dap").continue() end, desc = "Debug: start / continue" },
    { "<F9>", function() require("dap").toggle_breakpoint() end, desc = "Debug: toggle breakpoint" },
    { "<F10>", function() require("dap").step_over() end, desc = "Debug: step over" },
    { "<F11>", function() require("dap").step_into() end, desc = "Debug: step into" },
    { "<S-F11>", function() require("dap").step_out() end, desc = "Debug: step out" },
    { "<leader>dc", function() require("dap").continue() end, desc = "[D]ebug: [C]ontinue" },
    { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "[D]ebug: toggle [B]reakpoint" },
    {
      "<leader>dB",
      function()
        require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
      end,
      desc = "[D]ebug: conditional [B]reakpoint",
    },
    { "<leader>dr", function() require("dap").repl.toggle() end, desc = "[D]ebug: toggle [R]EPL" },
    { "<leader>dl", function() require("dap").run_last() end, desc = "[D]ebug: run [L]ast" },
    { "<leader>dt", function() require("dap").terminate() end, desc = "[D]ebug: [T]erminate" },
    { "<leader>du", function() require("dapui").toggle() end, desc = "[D]ebug: toggle [U]I" },
    {
      "<leader>de",
      function()
        require("dapui").eval(nil, { enter = true })
      end,
      mode = { "n", "v" },
      desc = "[D]ebug: [E]valuate expression",
    },
  },
  config = function()
    local dap = require("dap")
    local dapui = require("dapui")

    dapui.setup()

    dap.listeners.after.event_initialized["dapui_config"] = dapui.open
    dap.listeners.before.event_terminated["dapui_config"] = dapui.close
    dap.listeners.before.event_exited["dapui_config"] = dapui.close

    vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticSignError" })
    vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticSignWarn" })
    vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticSignInfo" })

    local python = debugpy_python()
    if python then
      pcall(require("dap-python").setup, python)
    end
  end,
}
