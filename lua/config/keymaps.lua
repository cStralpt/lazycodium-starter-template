-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local function map(mode, lhs, rhs, opts)
	local keys = require("lazy.core.handler").handlers.keys
	---@cast keys LazyKeysHandler
	-- do not create the keymap if a lazy keys handler exists
	if not keys.active[keys.parse({ lhs, mode = mode }).id] then
		opts = opts or {}
		opts.silent = opts.silent ~= false
		if opts.remap and not vim.g.vscode then
			opts.remap = nil
		end
		vim.keymap.set(mode, lhs, rhs, opts)
	end
end

local function copyToClipBoard()
	vim.cmd("set clipboard+=unnamedplus")
	vim.cmd("norm! y")
	vim.cmd("set clipboard-=unnamedplus")
	print("copied!")
end

map("i", "<C-a>", function()
	vim.cmd("norm! ggVG")
	print("Selected all lines")
end, { remap = false, desc = "select all lines in buffer" })
map({ "v", "i" }, "<C-c>", function()
	copyToClipBoard()
end, { remap = false, desc = "copy selected text" })
map("i", "<BS>", "<cmd>norm! de<CR>", { noremap = true, desc = "delete next word to right" })
map("i", "<C-l>", "<Del>", { remap = true, desc = "delete one character backward" })

if vim.g.vscode then
	print("⚡connected to neovim!💯‼️🤗😎")
	-- this shortcut somehow will jump/focus into terminal
	-- map(
	--   "i",
	--   "<C-j>",
	--   "<Cmd>call VSCodeCall('workbench.action.terminal.focus')<CR>",
	--   { noremap = true, silent = true, desc = "vs code keybinding test" }
	-- )

	map(
		"n",
		"<C-/>",
		"<Cmd>call VSCodeCall('workbench.action.terminal.focus')<CR>",
		{ noremap = true, silent = true, desc = "vs code keybinding test" }
	)

	map("n", "<S-l>", function()
		local cyclesNextEditor = "call VSCodeNotify('workbench.action.nextEditor')"
		vim.cmd(cyclesNextEditor)
	end, { noremap = true, desc = "switch between editor to next" })

	map("n", "<S-h>", function()
		local cyclesToNextEditor = "call VSCodeNotify('workbench.action.previousEditor')"
		vim.cmd(cyclesToNextEditor)
	end, { noremap = true, desc = "switch between editor to previous" })

	map("n", "gr", function()
		local go2Referces = "call VSCodeNotify('editor.action.referenceSearch.trigger')"
		vim.cmd(go2Referces)
	end, { noremap = true, desc = "peek references inside vs code" })

	map("n", "<leader>sd", function()
		local openProblemsInfos = "call VSCodeNotify('workbench.action.problems.focus')"
		vim.cmd(openProblemsInfos)
	end, { noremap = true, desc = "open problems and errors infos" })

	map("n", "<leader>e", function()
		local openFileExplorer = "call VSCodeNotify('workbench.files.action.focusFilesExplorer')"
		vim.cmd(openFileExplorer)
	end, { noremap = true, desc = "focus to file explorer" })

	map("n", "<leader>fe", function()
		local openFileExplorer = "call VSCodeNotify('workbench.files.action.focusFilesExplorer')"
		vim.cmd(openFileExplorer)
	end, { noremap = true, desc = "focus to file explorer" })

	map("n", "<leader>ff", function()
		local quickOpenFiles = "call VSCodeNotify('workbench.action.quickOpen')"
		vim.cmd(quickOpenFiles)
	end, { noremap = true, desc = "open files" })

	map("n", "<leader>gg", function()
		local openGitSourceControl = "call VSCodeNotify('workbench.view.scm')"
		vim.cmd(openGitSourceControl)
	end, { noremap = true, desc = "open git source controll" })

	map("n", "<leader>jml", function()
		local bookmarksList4CurrentFile = "call VSCodeNotify('bookmarks.list')"
		vim.cmd(bookmarksList4CurrentFile)
	end, { noremap = true, desc = "open bookmarks list for current files" })

	map("n", "<leader>jmL", function()
		local bookmarksList4AllFiles = "call VSCodeNotify('bookmarks.listFromAllFiles')"
		vim.cmd(bookmarksList4AllFiles)
	end, { noremap = true, desc = "open bookmarks list for all files" })

	map("n", "<leader>jmm", function()
		local bookmarksMarkToggle = "call VSCodeNotify('bookmarks.toggle')"
		vim.cmd(bookmarksMarkToggle)
	end, { noremap = true, desc = "toggle bookmarks" })

	map("n", "<leader>ca", function()
		local codeAction4QuickFix = "call VSCodeNotify('editor.action.quickFix')"
		vim.cmd(codeAction4QuickFix)
	end, { noremap = true, desc = "open quick fix in vs code" })

	map("n", "<leader>cs", function()
		local openSourceAction = "call VSCodeNotify('editor.action.sourceAction')"
		vim.cmd(openSourceAction)
	end, { noremap = true, desc = "open source Action in vs code" })

	map({ "v" }, "<C-c>", function()
		local copyText = "call VSCodeNotify('editor.action.clipboardCopyAction')"
		vim.cmd(copyText)
		print("📎added to clipboard!")
	end, { noremap = true, desc = "copy text/add text to clipboard" })
else
	map(
		{ "i", "t" },
		"<C-j>",
		"<cmd>ToggleTerm direction=float<CR><Esc>i",
		{ desc = "open floating terminal", noremap = false }
	)

	map("i", "<C-d>", function()
		local new_text = vim.fn.input("Replace with?: ")
		local cmd = "normal! *Ncgn" .. new_text
		vim.cmd(cmd)
	end, { desc = "ctrl+d vs code alternative" })

	map("i", "<C-f>", "<Esc>/", { noremap = false })

	function ToggleWordWrap()
		if vim.wo.wrap then
			vim.wo.wrap = false
			print("Word wrap disabled")
		else
			vim.wo.wrap = true
			print("Word wrap enabled")
		end
	end

	-- Map a keybinding to toggle word wrap
	map("n", "<leader>ct", ":lua ToggleWordWrap()<CR>", { noremap = true, silent = true, desc = "toggle word wrap" })
	map("n", "<leader>bc", "<cmd>BufferLinePick<CR>", { noremap = false, silent = true, desc = "pick buffer" })
	map("n", "-", require("oil").open, { desc = "Open parent directory" })
	-- force/replace already used keymaps
	vim.api.nvim_set_keymap(
		"n",
		"<leader>cs",
		"<cmd>AerialNavOpen<CR>",
		{ noremap = true, silent = true, desc = "Symbols Outline(Aerial)" }
	)
end
