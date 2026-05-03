-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.opt.ttimeoutlen = 0  -- no delay on escape sequences
vim.diagnostic.config({ virtual_text = false, signs = false, underline = false }) -- disable all diagnostics
vim.g.root_spec = { "cwd" } -- don't auto-change cwd based on open file
vim.opt.timeoutlen = 150
vim.opt.clipboard = "unnamedplus" -- yank/paste uses system clipboard
vim.opt.guicursor:append("a:blinkwait700-blinkon400-blinkoff250") -- blink cursor in all modes
