-- bootstrap lazy.nvim, LazyVim and your plugins
if vim.g.vscode then
	-- VSCode extension
	require("config.lazy")
	vim.api.nvim_exec(
		[[
    " THEME CHANGER
    function! SetCursorLineNrColorInsert(mode)
        " Insert mode: blue
        if a:mode == "i"
            call VSCodeNotify('nvim-theme.insert')

        " Replace mode: red
        elseif a:mode == "r"
            call VSCodeNotify('nvim-theme.replace')
        endif
    endfunction

    augroup CursorLineNrColorSwap
        autocmd!
        autocmd ModeChanged *:[vV\x16]* call VSCodeNotify('nvim-theme.visual')
        autocmd ModeChanged *:[R]* call VSCodeNotify('nvim-theme.replace')
        autocmd InsertEnter * call SetCursorLineNrColorInsert(v:insertmode)
        autocmd InsertLeave * call VSCodeNotify('nvim-theme.normal')
        autocmd CursorHold * call VSCodeNotify('nvim-theme.normal')
    augroup END
]],
		false
	)
else
	require("config.lazy")
	require("nvim-ts-autotag").setup({})
	require("toggleterm").setup({})
	require("oil").setup()
	require("notify").setup({
		background_colour = "#101e2c",
	})
	vim.api.nvim_command("highlight LineNr guifg=#bae67e ctermfg=149")
	vim.api.nvim_command("highlight CursorLineNr guifg=#ef6b73 ctermfg=203")
	vim.api.nvim_command("highlight CursorLine guibg=#1C1C3E")

	-- make nvim transparent
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
