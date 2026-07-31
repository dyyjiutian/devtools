-- ============================================================
-- neotest: Run and inspect tests from the editor
-- neotest-golang is used instead of neotest-go, which is unmaintained.
-- ============================================================

return {
  "nvim-neotest/neotest",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-neotest/nvim-nio",
    "antoinemadec/FixCursorHold.nvim",
    "nvim-treesitter/nvim-treesitter",
    "nvim-neotest/neotest-python",
    "fredrikaverpil/neotest-golang",
  },
  -- keys alone leave :Neotest unavailable until a keymap fires.
  cmd = "Neotest",
  keys = {
    {
      "<leader>tt",
      function()
        require("neotest").run.run()
      end,
      desc = "[T]est: run nearest",
    },
    {
      "<leader>tf",
      function()
        require("neotest").run.run(vim.fn.expand("%"))
      end,
      desc = "[T]est: run [F]ile",
    },
    {
      "<leader>tl",
      function()
        require("neotest").run.run_last()
      end,
      desc = "[T]est: run [L]ast",
    },
    {
      "<leader>ts",
      function()
        require("neotest").summary.toggle()
      end,
      desc = "[T]est: toggle [S]ummary",
    },
    {
      "<leader>to",
      function()
        require("neotest").output.open({ enter = true, auto_close = true })
      end,
      desc = "[T]est: show [O]utput",
    },
    {
      "<leader>tp",
      function()
        require("neotest").output_panel.toggle()
      end,
      desc = "[T]est: toggle output [P]anel",
    },
    {
      "<leader>tx",
      function()
        require("neotest").run.stop()
      end,
      desc = "[T]est: stop run",
    },
    {
      "<leader>td",
      function()
        require("neotest").run.run({ strategy = "dap" })
      end,
      desc = "[T]est: [D]ebug nearest",
    },
  },
  config = function()
    require("neotest").setup({
      adapters = {
        require("neotest-python")({ dap = { justMyCode = false } }),
        require("neotest-golang")({}),
      },
    })
  end,
}
