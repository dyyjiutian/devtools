-- ============================================================
-- Auto-completion
-- ============================================================

return {
  "hrsh7th/nvim-cmp",
  event = "InsertEnter",
  dependencies = {
    {
      "L3MON4D3/LuaSnip",
      build = (function()
        if vim.fn.has("win32") == 1 or vim.fn.executable("make") == 0 then
          return
        end
        return "make install_jsregexp"
      end)(),
      dependencies = {
        {
          "rafamadriz/friendly-snippets",
          config = function()
            require("luasnip.loaders.from_vscode").lazy_load()
          end,
        },
      },
    },
    "saadparwaiz1/cmp_luasnip",
    "hrsh7th/cmp-nvim-lsp",
    "hrsh7th/cmp-path",
    "hrsh7th/cmp-buffer",
    "hrsh7th/cmp-cmdline",
  },
  config = function()
    local cmp = require("cmp")
    local luasnip = require("luasnip")
    luasnip.config.setup({})

    cmp.setup({
      snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      },
      completion = { completeopt = "menu,menuone,noinsert" },
      mapping = cmp.mapping.preset.insert({
        ["<C-n>"] = cmp.mapping.select_next_item(),
        ["<C-p>"] = cmp.mapping.select_prev_item(),
        ["<C-b>"] = cmp.mapping.scroll_docs(-4),
        ["<C-f>"] = cmp.mapping.scroll_docs(4),
        ["<C-y>"] = cmp.mapping.confirm({ select = true }),
        -- Tab / Enter: Copilot ghost text → cmp confirm → fallback
        -- (indent for Tab, newline for Enter). Ctrl-J accepts Copilot only.
        -- Up/Down (and <C-n>/<C-p>) navigate. No <S-Tab> — leave it free.
        ["<Tab>"] = cmp.mapping(function(fallback)
          local ok, suggestion = pcall(vim.fn["copilot#GetDisplayedSuggestion"])
          if ok and suggestion.text and suggestion.text ~= "" then
            local ok_accept, keys = pcall(vim.fn["copilot#Accept"], "")
            if ok_accept and keys ~= "" then
              vim.api.nvim_feedkeys(keys, "n", true)
              return
            end
          end
          if cmp.visible() then
            cmp.confirm({ select = true })
            return
          end
          fallback()
        end),
        ["<CR>"] = cmp.mapping(function(fallback)
          local ok, suggestion = pcall(vim.fn["copilot#GetDisplayedSuggestion"])
          if ok and suggestion.text and suggestion.text ~= "" then
            local ok_accept, keys = pcall(vim.fn["copilot#Accept"], "")
            if ok_accept and keys ~= "" then
              vim.api.nvim_feedkeys(keys, "n", true)
              return
            end
          end
          if cmp.visible() then
            cmp.confirm({ select = true })
            return
          end
          fallback()
        end),
        ["<C-Space>"] = cmp.mapping.complete({}),
        ["<C-l>"] = cmp.mapping(function()
          if luasnip.expand_or_locally_jumpable() then
            luasnip.expand_or_jump()
          end
        end, { "i", "s" }),
        ["<C-h>"] = cmp.mapping(function()
          if luasnip.locally_jumpable(-1) then
            luasnip.jump(-1)
          end
        end, { "i", "s" }),
      }),
      sources = {
        { name = "nvim_lsp" },
        { name = "luasnip" },
        { name = "path" },
        { name = "buffer", keyword_length = 3 },
      },
    })

    cmp.setup.cmdline("/", {
      mapping = cmp.mapping.preset.cmdline(),
      sources = { { name = "buffer" } },
    })

    cmp.setup.cmdline(":", {
      mapping = cmp.mapping.preset.cmdline(),
      sources = cmp.config.sources({ { name = "path" } }, { { name = "cmdline" } }),
    })
  end,
}
