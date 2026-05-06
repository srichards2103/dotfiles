-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
vim.keymap.set("i", "jk", "<Esc>", { desc = "Exit insert mode" })
vim.keymap.set("n", "<leader>r", "<cmd>e!<cr>", { desc = "Reload file" })

-- agent: send text to a Claude Code or Codex CLI in a sibling tmux pane
require("agent").setup()
local map = vim.keymap.set
map("v", "<leader>ac", ":AgentSendPrompt claude<cr>",     { desc = "Send selection → Claude (prompt)" })
map("v", "<leader>ax", ":AgentSendPrompt codex<cr>",      { desc = "Send selection → Codex (prompt)" })
map("n", "<leader>ab", "<cmd>AgentSendBuffer claude<cr>", { desc = "Send buffer → Claude" })
map("n", "<leader>aB", "<cmd>AgentSendBuffer codex<cr>",  { desc = "Send buffer → Codex" })
map("n", "<leader>ap", "<cmd>AgentSendPath claude<cr>",   { desc = "Append @file → Claude" })
map("n", "<leader>aP", "<cmd>AgentSendPath codex<cr>",    { desc = "Append @file → Codex" })
