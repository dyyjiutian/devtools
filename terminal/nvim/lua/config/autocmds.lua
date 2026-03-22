-- ============================================================
-- Auto Commands
-- ============================================================

local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

-- Highlight when yanking text
autocmd("TextYankPost", {
  desc = "Highlight when yanking (copying) text",
  group = augroup("kickstart-highlight-yank", { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- Remove trailing whitespace on save
autocmd("BufWritePre", {
  desc = "Remove trailing whitespace on save",
  group = augroup("trim-whitespace", { clear = true }),
  command = [[%s/\s\+$//e]],
})

-- Auto resize splits when window is resized
autocmd("VimResized", {
  desc = "Auto resize splits when window is resized",
  group = augroup("resize-splits", { clear = true }),
  command = "tabdo wincmd =",
})

-- Set indentation for specific filetypes
autocmd("FileType", {
  desc = "Set 2-space indentation for specific filetypes",
  group = augroup("filetype-indent", { clear = true }),
  pattern = { "lua", "javascript", "typescript", "json", "yaml", "html", "css", "scss", "sh", "bash", "zsh", "vim" },
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.softtabstop = 2
  end,
})

-- Set noexpandtab for Go files
autocmd("FileType", {
  desc = "Use tabs for Go files",
  group = augroup("go-indent", { clear = true }),
  pattern = { "go" },
  callback = function()
    vim.opt_local.expandtab = false
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.softtabstop = 4
  end,
})

-- Close some filetypes with <q>
autocmd("FileType", {
  desc = "Close some filetypes with <q>",
  group = augroup("close-with-q", { clear = true }),
  pattern = {
    "PlenaryTestPopup",
    "help",
    "lspinfo",
    "man",
    "notify",
    "qf",
    "spectre_panel",
    "startuptime",
    "tsplayground",
    "neotest-output",
    "checkhealth",
    "neotest-summary",
    "neotest-output-panel",
  },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = event.buf, silent = true })
  end,
})

-- Check if we need to reload the file when it changed
autocmd({ "FocusGained", "TermClose", "TermLeave" }, {
  desc = "Check if file changed and reload",
  group = augroup("checktime", { clear = true }),
  command = "checktime",
})
