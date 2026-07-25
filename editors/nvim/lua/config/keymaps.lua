-- ============================================================
-- Key Mappings
-- Leader key: <Space>
-- ============================================================

local map = vim.keymap.set

-- Clear highlights on search
map("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- Diagnostic navigation
map("n", "[d", vim.diagnostic.goto_prev, { desc = "Go to previous [D]iagnostic message" })
map("n", "]d", vim.diagnostic.goto_next, { desc = "Go to next [D]iagnostic message" })
map("n", "<leader>e", vim.diagnostic.open_float, { desc = "Show diagnostic [E]rror messages" })
map("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostic [Q]uickfix list" })

-- Window navigation
map("n", "<C-h>", "<C-w><C-h>", { desc = "Move focus to the left window" })
map("n", "<C-l>", "<C-w><C-l>", { desc = "Move focus to the right window" })
map("n", "<C-j>", "<C-w><C-j>", { desc = "Move focus to the lower window" })
map("n", "<C-k>", "<C-w><C-k>", { desc = "Move focus to the upper window" })

-- Buffer navigation
map("n", "<leader>bn", "<cmd>bnext<CR>", { desc = "[B]uffer [N]ext" })
map("n", "<leader>bp", "<cmd>bprevious<CR>", { desc = "[B]uffer [P]revious" })
map("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "[B]uffer [D]elete" })

-- Quick save/quit
map("n", "<leader>w", "<cmd>w<CR>", { desc = "[W]rite (save) file" })
map("n", "<leader>q", "<cmd>q<CR>", { desc = "[Q]uit" })
map("n", "<leader>wq", "<cmd>wq<CR>", { desc = "[W]rite and [Q]uit" })

-- Better indenting
map("v", "<", "<gv")
map("v", ">", ">gv")

-- Move lines
map("v", "J", ":m '>+1<CR>gv=gv")
map("v", "K", ":m '<-2<CR>gv=gv")

-- Stay in indent mode
map("v", "<", "<gv")
map("v", ">", ">gv")

-- Disable arrow keys in normal mode
map("n", "<left>", '<cmd>echo "Use h to move!!"<CR>')
map("n", "<right>", '<cmd>echo "Use l to move!!"<CR>')
map("n", "<up>", '<cmd>echo "Use k to move!!"<CR>')
map("n", "<down>", '<cmd>echo "Use j to move!!"<CR>')

-- Center cursor on search
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

-- Paste without overwriting register
map("x", "<leader>p", [['_dP]], { desc = "Paste without overwriting register" })

-- Delete without yanking
map({ "n", "v" }, "<leader>d", [['_d]], { desc = "Delete without yanking" })

-- Quick file explorer
map("n", "<leader>pv", vim.cmd.Ex, { desc = "Open file explorer" })

-- Terminal mode escape
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
