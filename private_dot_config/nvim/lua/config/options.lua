-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.g.root_spec = { "cwd" } -- don't auto-change cwd based on open file
vim.opt.timeoutlen = 150
vim.opt.clipboard = "unnamedplus" -- yank/paste uses system clipboard
