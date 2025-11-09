-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
local opt = vim.opt
opt.undofile = false
-- opt.shell = "powershell.exe"
if vim.fn.executable("powershell") == 1 then
  -- Use PowerShell as the default shell in Windows
  vim.opt.shell = "powershell"
  vim.opt.shellcmdflag = "-command"
  vim.opt.shellquote = '"'
  vim.opt.shellxquote = ""
else
  -- Fallback to bash if PowerShell is not available
  vim.opt.shell = "bash"
end

opt.clipboard = ""
vim.g.lazyvim_rust_diagnostics = "rust-analyzer"