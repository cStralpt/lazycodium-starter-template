-- bootstrap lazy.nvim, LazyVim and your plugins
if vim.g.vscode then
  -- VSCode extension
  require("config.lazy")
else
  require("config.lazy")
  require("oil").setup()
  vim.api.nvim_command("highlight LineNr guifg=#bae67e ctermfg=149")
  vim.api.nvim_command("highlight CursorLineNr guifg=#ef6b73 ctermfg=203")
  vim.api.nvim_command("highlight CursorLine guibg=#1C1C3E")
  vim.o.winblend = 20
  vim.o.pumblend = 20

  if vim.g.neovide then
    -- vim.g.neovide_background_color = '#0f1117'
    vim.g.neovide_transparency = 0.9
    vim.keymap.set("i", "<C-S-v>", "<C-r>+")
    vim.keymap.set("t", "<C-S-v>", [[<C-\><C-n>"+pi]], { noremap = true, silent = true })
    vim.g.neovide_refresh_rate = 100
    vim.g.neovide_refresh_rate_idle = 5
    vim.g.neovide_cursor_animate_in_insert_mode = true
    vim.g.neovide_cursor_animate_command_line = true
    vim.g.neovide_cursor_vfx_mode = "sonicboom"
    vim.g.neovide_window_blurred = true
    vim.g.neovide_floating_blur_amount_x = 2.0
    vim.g.neovide_floating_blur_amount_y = 2.0
    vim.opt.guifont = "FantasqueSansM Nerd Font:h14"
  end

  -- make nvim transparent (only in bare neovim)
  if not vim.g.vscode and not vim.g.neovide then
    local transparencyOptions = {
      init = {
        Normal = { bg = "NONE", ctermbg = "NONE" },
        NormalNC = { bg = "NONE", ctermbg = "NONE" },
        NeoTreeNormal = { bg = "NONE", ctermbg = "NONE" },
        NeoTreeNormalNC = { bg = "NONE", ctermbg = "NONE" },
      },
    }

    if transparencyOptions then
      for group, hl in pairs(transparencyOptions.init) do
        vim.cmd(
          "highlight "
            .. group
            .. " guifg="
            .. (hl.gui and hl.gui.fg or "NONE")
            .. " guibg="
            .. (hl.gui and hl.gui.bg or "NONE")
            .. " ctermfg="
            .. (hl.cterm and hl.cterm.fg or "NONE")
            .. " ctermbg="
            .. (hl.cterm and hl.cterm.bg or "NONE")
        )
      end
    end
  end
end
