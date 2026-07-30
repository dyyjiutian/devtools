-- ============================================================
-- LSP Configuration
-- Pinned for Neovim 0.10.x (Alinux 3). mason-lspconfig v2+ needs
-- vim.lsp.enable() which only exists in Neovim 0.11+.
-- ============================================================

return {
  "neovim/nvim-lspconfig",
  version = "v1.8.0",
  dependencies = {
    { "williamboman/mason.nvim", version = "v1.11.0", config = true },
    { "williamboman/mason-lspconfig.nvim", version = "v1.32.0" },
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    { "j-hui/fidget.nvim", opts = {} },
    { "folke/neodev.nvim", opts = {} },
  },
  config = function()
    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("kickstart-lsp-attach", { clear = true }),
      callback = function(event)
        local map = function(keys, func, desc)
          vim.keymap.set("n", keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
        end

        map("gd", require("telescope.builtin").lsp_definitions, "[G]oto [D]efinition")
        map("gr", require("telescope.builtin").lsp_references, "[G]oto [R]eferences")
        map("gI", require("telescope.builtin").lsp_implementations, "[G]oto [I]mplementation")
        map("<leader>D", require("telescope.builtin").lsp_type_definitions, "Type [D]efinition")
        map("<leader>ds", require("telescope.builtin").lsp_document_symbols, "[D]ocument [S]ymbols")
        map("<leader>ws", require("telescope.builtin").lsp_dynamic_workspace_symbols, "[W]orkspace [S]ymbols")
        map("<leader>rn", vim.lsp.buf.rename, "[R]e[n]ame")
        map("<leader>ca", vim.lsp.buf.code_action, "[C]ode [A]ction")
        map("K", vim.lsp.buf.hover, "Hover Documentation")
        map("gD", vim.lsp.buf.declaration, "[G]oto [D]eclaration")

        local client = vim.lsp.get_client_by_id(event.data.client_id)
        if client and client.server_capabilities.documentHighlightProvider then
          vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
            buffer = event.buf,
            callback = vim.lsp.buf.document_highlight,
          })
          vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
            buffer = event.buf,
            callback = vim.lsp.buf.clear_references,
          })
        end
      end,
    })

    local capabilities = vim.lsp.protocol.make_client_capabilities()
    capabilities = vim.tbl_deep_extend("force", capabilities, require("cmp_nvim_lsp").default_capabilities())

    -- Server configs (handlers still apply when installed via :Mason).
    local servers = {
      lua_ls = {
        settings = {
          Lua = {
            completion = {
              callSnippet = "Replace",
            },
          },
        },
      },
      pyright = {},
      gopls = {},
      jdtls = {},
      bashls = {},
      jsonls = {},
      yamlls = {},
      dockerls = {},
      html = {},
      cssls = {},
      ts_ls = {},
      rust_analyzer = {},
      clangd = {},
    }

    -- Auto-install a small common set once; heavy/optional servers via :Mason.
    local ensure_lsp = {
      "lua_ls",
      "pyright",
      "gopls",
      "clangd",
      "bashls",
      "jsonls",
      "yamlls",
      "ts_ls",
    }

    local function setup_server(server_name)
      local server = vim.deepcopy(servers[server_name] or {})
      server.capabilities = vim.tbl_deep_extend("force", {}, capabilities, server.capabilities or {})
      require("lspconfig")[server_name].setup(server)
    end

    -- Only register servers whose binary is on PATH (mason bin included).
    local function server_installed(server_name)
      local ok, config = pcall(function()
        return require("lspconfig")[server_name]
      end)
      if not ok or not config then
        return false
      end
      local default_config = (config.document_config or {}).default_config or {}
      local cmd = default_config.cmd
      if type(cmd) ~= "table" or not cmd[1] then
        return false
      end
      return vim.fn.executable(cmd[1]) == 1
    end

    require("mason").setup()

    -- Formatters only (not every LSP). Debounce avoids "X: installing" spam each start.
    require("mason-tool-installer").setup({
      ensure_installed = {
        "stylua",
        "prettier",
        "shfmt",
      },
      auto_update = false,
      run_on_start = true,
      debounce_hours = 24,
    })

    -- A mason-lspconfig error must not abort this config: without a fallback the
    -- handlers never run, no server attaches, and gr/gd silently do nothing.
    local ok, err = pcall(function()
      require("mason-lspconfig").setup({
        ensure_installed = ensure_lsp,
        automatic_installation = false,
        handlers = { setup_server },
      })
    end)

    if not ok then
      vim.notify(
        "mason-lspconfig setup failed, registering installed servers directly: " .. tostring(err),
        vim.log.levels.WARN
      )
      for server_name in pairs(servers) do
        if server_installed(server_name) then
          pcall(setup_server, server_name)
        end
      end
    end
  end,
}
