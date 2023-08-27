-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
local opt = vim.opt
opt.undofile = false
-- opt.shell = "pwsh.exe"
if vim.fn.executable("pwsh") == 1 then
  vim.cmd([[
    set shell=pwsh
    set shellcmdflag=-command
    set shellquote=\"
    set shellxquote=
  ]])
else
  vim.cmd([[
    set shell=bash
  ]])
end
opt.clipboard = ""