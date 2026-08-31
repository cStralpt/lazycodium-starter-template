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

local function ToggleWordWrap()
  if vim.wo.wrap then
    vim.wo.wrap = false
    print("Word wrap disabled")
  else
    vim.wo.wrap = true
    print("Word wrap enabled")
  end
end

local function copyToClipBoard()
  vim.cmd("set clipboard+=unnamedplus")
  vim.cmd("norm! y")
  vim.cmd("set clipboard-=unnamedplus")
  print("copied!")
end

local function callVSCodeFunction(vsCodeCommand)
  vim.cmd(vsCodeCommand)
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
-- Terminal-mode window navigation, so you can jump between the Claude Code
-- chat and your code buffers without leaving terminal-insert mode first.
-- Normal-mode <C-hjkl> window nav already ships with LazyVim; this mirrors it
-- for "t" mode so the same keys work while typing into Claude.
-- Deliberately NOT mapping <esc><esc> here: a leading-<Esc> mapping makes
-- Neovim delay every single <Esc> by 'timeoutlen' waiting for a second one,
-- which breaks Claude Code's press-Esc-to-interrupt. Use <C-\><C-n> (Neovim's
-- real default) if you ever need to drop to terminal-normal mode in place.
map("t", "<C-h>", "<cmd>wincmd h<cr>", { desc = "Go to Left Window" })
map("t", "<C-j>", "<cmd>wincmd j<cr>", { desc = "Go to Lower Window" })
map("t", "<C-k>", "<cmd>wincmd k<cr>", { desc = "Go to Upper Window" })
map("t", "<C-l>", "<cmd>wincmd l<cr>", { desc = "Go to Right Window" })

-- <C-\><C-n> (Neovim's real default to drop to terminal-normal mode) doesn't
-- reach Neovim reliably from every keyboard layout/terminal emulator (some
-- need AltGr for backslash, some swallow the chord). <C-g> is far more
-- portable and unused by Claude Code, so bind it to the same action.
map("t", "<C-g>", "<C-\\><C-n>", { desc = "Exit terminal mode (terminal-normal)" })

-- LazyVim's default <C-/> opens an EMBEDDED terminal buffer (Snacks.terminal,
-- toggleable/hideable like any Neovim window) but runs $SHELL, which is bash
-- here -- hence the "bare" look, even though you interactively use fish
-- (styled prompt, theme, etc.) everywhere else. Run fish in it instead so
-- the embedded terminal actually looks like your terminal.
local function open_terminal()
  local shell = vim.fn.executable("fish") == 1 and "fish" or nil
  -- snacks.nvim defaults to a FLOATING window whenever `cmd` is non-nil
  -- (assumes a one-off command), and only defaults to "bottom" when cmd is
  -- nil (a plain shell). Since we always pass an explicit shell now, pin
  -- position explicitly or it silently floats instead of splitting.
  Snacks.terminal.focus(shell, { cwd = LazyVim.root(), win = { position = "bottom" } })
end
map({ "n", "t" }, "<C-/>", open_terminal, { desc = "Terminal (fish, embedded)" })
map({ "n", "t" }, "<C-_>", open_terminal, { desc = "which_key_ignore" })

local function neovimMappings()
  -- map(
  --   { "i", "t" },
  --   "<C-j>",
  --   "<cmd>ToggleTerm direction=float<CR><Esc>i",
  --   { desc = "open floating terminal", noremap = false }
  -- )

  map("i", "<C-d>", function()
    local new_text = vim.fn.input("Replace with?: ")
    local cmd = "normal! *Ncgn" .. new_text
    vim.cmd(cmd)
  end, { desc = "ctrl+d vs code alternative" })

  map("i", "<C-f>", "<Esc>/", { noremap = false })

  map("v", "<C-c>", function()
    copyToClipBoard()
  end, { remap = false, desc = "copy selected text" })

  -- Map a keybinding to toggle word wrap
  map("n", "<leader>ct", function()
    ToggleWordWrap()
  end, { noremap = true, silent = true, desc = "toggle word wrap" })
  map("n", "<leader>bc", "<cmd>BufferLinePick<CR>", { noremap = false, silent = true, desc = "pick buffer" })
  map("n", "-", require("oil").open, { desc = "Open parent directory" })
end

local function vscodeMappings()
  map("n", "<C-/>", function()
    callVSCodeFunction("call VSCodeCall('workbench.action.terminal.focus')")
  end, { noremap = true, silent = true, desc = "toggle terminal" })

  map("t", "<C-l>", function()
    print("next term")
    callVSCodeFunction("call VSCodeCall('workbench.action.terminal.focusNextPane')")
  end, { noremap = true, silent = true, desc = "cycle terminal focus" })

  map("t", "<C-h>", function()
    print("prev term")
    callVSCodeFunction("call VSCodeCall('workbench.action.terminal.focusPreviousPane')")
  end, { noremap = true, silent = true, desc = "cycle terminal focus" })

  map("n", "<leader>cs", function()
    print("go to symbols in editor")
    callVSCodeFunction("call VSCodeCall('workbench.action.gotoSymbol')")
  end, { noremap = true, silent = true, desc = "go to symbols in editor" })

  map("n", "<S-l>", function()
    callVSCodeFunction("call VSCodeNotify('workbench.action.nextEditor')")
  end, { noremap = true, desc = "switch between editor to next" })

  map("n", "<S-h>", function()
    callVSCodeFunction("call VSCodeNotify('workbench.action.previousEditor')")
  end, { noremap = true, desc = "switch between editor to previous" })

  map("n", "gr", function()
    callVSCodeFunction("call VSCodeNotify('editor.action.referenceSearch.trigger')")
  end, { noremap = true, desc = "peek references inside vs code" })

  map("n", "<leader>sd", function()
    callVSCodeFunction("call VSCodeNotify('workbench.action.problems.focus')")
  end, { noremap = true, desc = "open problems and errors infos" })

  map("n", "<leader>e", function()
    callVSCodeFunction("call VSCodeNotify('workbench.files.action.focusFilesExplorer')")
  end, { noremap = true, desc = "focus to file explorer" })

  map("n", "<leader>fe", function()
    callVSCodeFunction("call VSCodeNotify('workbench.files.action.focusFilesExplorer')")
  end, { noremap = true, desc = "focus to file explorer" })

  map("n", "<leader>ff", function()
    callVSCodeFunction("call VSCodeNotify('workbench.action.quickOpen')")
  end, { noremap = true, desc = "open files" })

  map("n", "<leader>gg", function()
    callVSCodeFunction("call VSCodeNotify('workbench.view.scm')")
  end, { noremap = true, desc = "open git source control" })

  map("n", "<leader>sml", function()
    callVSCodeFunction("call VSCodeNotify('bookmarks.list')")
  end, { noremap = true, desc = "open bookmarks list for current files" })

  map("n", "<leader>smL", function()
    callVSCodeFunction("call VSCodeNotify('bookmarks.listFromAllFiles')")
  end, { noremap = true, desc = "open bookmarks list for all files" })

  map("n", "<leader>smm", function()
    callVSCodeFunction("call VSCodeNotify('bookmarks.toggle')")
  end, { noremap = true, desc = "toggle bookmarks" })

  map("n", "<leader>smd", function()
    callVSCodeFunction("call VSCodeNotify('bookmarks.clear')")
  end, { noremap = true, desc = "clear bookmarks from current file" })

  map("n", "<leader>smr", function()
    callVSCodeFunction("call VSCodeNotify('bookmarks.clearFromAllFiles')")
  end, { noremap = true, desc = "clear bookmarks from all file" })

  map("n", "<leader>cr", function()
    callVSCodeFunction("call VSCodeNotify('editor.action.rename')")
  end, { noremap = true, desc = "rename symbol" })

  map("n", "<leader>ca", function()
    callVSCodeFunction("call VSCodeNotify('editor.action.quickFix')")
  end, { noremap = true, desc = "open quick fix in vs code" })

  map("n", "<leader>cA", function()
    callVSCodeFunction("call VSCodeNotify('editor.action.sourceAction')")
  end, { noremap = true, desc = "open source Action in vs code" })

  map("n", "<leader>cp", function()
    callVSCodeFunction("call VSCodeNotify('workbench.panel.markers.view.focus')")
  end, { noremap = true, desc = "open problems diagnostics" })

  map("n", "<leader>cd", function()
    callVSCodeFunction("call VSCodeNotify('editor.action.marker.next')")
  end, { noremap = true, desc = "open problems diagnostics" })

  map({ "v" }, "<C-c>", function()
    callVSCodeFunction("call VSCodeNotify('editor.action.clipboardCopyAction')")
    print("📎added to clipboard!")
  end, { noremap = true, desc = "copy text/add text to clipboard" })

  map({ "n" }, "u", function()
    callVSCodeFunction("call VSCodeNotify('undo')")
  end, { noremap = true, desc = "undo changes" })

  map({ "n" }, "<C-r>", function()
    callVSCodeFunction("call VSCodeNotify('redo')")
  end, { noremap = true, desc = "redo changes" })

  map("n", "<leader>cix", function()
    callVSCodeFunction("call VSCodeNotify('chatgpt.openSidebar')")
    print("🤖 Opening ChatGPT Codex...")
  end, { noremap = true, silent = true, desc = "open ChatGPT Codex sidebar" })

  map("n", "<leader>cic", function()
    callVSCodeFunction("call VSCodeNotify('workbench.action.focusAuxiliaryBar')")
    print("🔧 Opening Cursor...")
  end, { noremap = true, silent = true, desc = "open cursor auxiliary bar" })

  map("n", "<leader>cia", function()
    callVSCodeFunction("call VSCodeNotify('vscode-augment.startNewChat')")
    print("✨ Starting Augment Chat...")
  end, { noremap = true, silent = true, desc = "start new augment chat" })

  map("n", "<leader>cik", function()
    callVSCodeFunction("call VSCodeNotify('kiroAgent.newSession')")
    print("✨ Starting new session i kiro")
  end, { noremap = true, silent = true, desc = "start new kiro session" })
end

if vim.g.vscode then
  print("⚡connected to neovim!💯‼️🤗😎")
  vscodeMappings()
else
  neovimMappings()
end
