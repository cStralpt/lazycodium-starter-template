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
--
-- Inside a tmux workspace float (<C-/>, <leader>ac) it does something better
-- than plain terminal-normal mode, because there plain terminal-normal mode is
-- close to useless: `tmux attach` runs on the alternate screen, so that buffer
-- is one screen tall and j/k have nothing to move through. W.scrollback()
-- instead drops the pane's real history into an ordinary buffer -- so scrolling
-- works, and so does every normal-mode mapping you already have, including
-- <C-c> to the clipboard. Everywhere else <C-g> is unchanged.
map("t", "<C-g>", function()
  for _, ws in ipairs({ require("util.floating_term"), require("util.claude_agents").workspace }) do
    if ws.in_float() then
      return ws.scrollback()
    end
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true), "n", false)
end, { desc = "Exit terminal mode (scrollback in a workspace float)" })

-- <C-/> toggles a near-fullscreen floating terminal that's actually a
-- persistent tmux session (lua/util/floating_term.lua) -- so, unlike a
-- single bare Snacks terminal buffer, it supports real splits (<leader>ts/tv)
-- and tabs/terminal groups (<leader>tn, <leader>t]/t[) via tmux itself,
-- while state (running processes, scrollback) survives hiding/reshowing
-- untouched.
local floating_term = require("util.floating_term")
map({ "n", "t" }, "<C-/>", floating_term.toggle, { desc = "Terminal (floating, tmux)" })
map({ "n", "t" }, "<C-_>", floating_term.toggle, { desc = "which_key_ignore" })

-- These are normal-mode only (not "t"): <leader> is space, which you type
-- constantly inside a shell, so mapping it in terminal-insert mode would
-- break normal typing. Drop into terminal-normal mode first (<C-g>, mapped
-- above) to reach them while the floating terminal is focused.
map("n", "<leader>ts", floating_term.split_horizontal, { desc = "Terminal: split pane (horizontal)" })
map("n", "<leader>tv", floating_term.split_vertical, { desc = "Terminal: split pane (vertical)" })
map("n", "<leader>tn", floating_term.new_tab, { desc = "Terminal: new tab (terminal group)" })
map("n", "<leader>tx", floating_term.close_pane, { desc = "Terminal: close pane" })
-- Not ]t/[t: LazyVim already claims those for todo-comments.nvim, and the
-- `map()` wrapper above silently skips ours whenever a lazy-loaded plugin
-- keymap already owns the lhs -- so ]t/[t would appear to do nothing.
map("n", "<leader>t]", floating_term.next_tab, { desc = "Terminal: next tab" })
map("n", "<leader>t[", floating_term.prev_tab, { desc = "Terminal: prev tab" })

-- The Claude workspace: N Claudes as tmux panes, in groups (util/claude_agents
-- .lua). Mapped EAGERLY here, not as lazy `keys` on coder/claudecode.nvim,
-- which is where they used to live.
--
-- That mattered for latency, not tidiness. None of these touch that plugin --
-- they drive tmux through util/claude_agents.lua -- but as entries in its
-- `keys` table they were lazy TRIGGERS for it, so pressing <leader>a ran
-- lazy.nvim's stub, loaded the plugin, registered 31 mappings and replayed the
-- pending keys before anything happened. Worse, the spec's
-- `{ "<leader>a", "", desc = "+ai" }` group entry mapped <leader>a to an empty
-- string, making it a COMPLETE mapping as well as a prefix -- so every press
-- also sat out the full 'timeoutlen' (300ms here) waiting to see whether a
-- longer mapping was coming. That is the "everything under <leader>a is slow"
-- report: the cost was in the prefix, identical whichever key followed it.
--
-- There is deliberately no <leader>a group mapping now. which-key still shows
-- the group (registered below on VeryLazy, when it exists), but <leader>a is a
-- pure prefix again, so there is nothing to disambiguate and no wait.
local agents = require("util.claude_agents")
local marks = require("util.send_marks")

map("n", "<leader>ac", agents.toggle, { desc = "Claude: toggle workspace" })
map("n", "<leader>an", agents.new_group, { desc = "Claude: new group (claude tab)" })
map("n", "<leader>ao", agents.split_below, { desc = "Claude: another agent below" })
map("n", "<leader>aV", agents.split_right, { desc = "Claude: another agent right" })
map("n", "<leader>a]", agents.next_group, { desc = "Claude: next group" })
map("n", "<leader>a[", agents.prev_group, { desc = "Claude: prev group" })
map("n", "<leader>ax", agents.close_agent, { desc = "Claude: close this agent" })
map("n", "<leader>az", agents.zoom, { desc = "Claude: show only this agent" })
-- Counted, this skips the picker AND the float entirely: `3<leader>af` just
-- retargets where the next send lands, read off the statusline pills. Bare, it
-- is still the picker, which does reveal -- browsing what each agent holds and
-- then landing in front of the one you chose is the whole point of that path.
map("n", "<leader>af", function()
  local count = vim.v.count
  if count > 0 then
    agents.focus_slot(count)
  else
    agents.pick()
  end
end, { desc = "Claude: pick an agent (count: focus slot, no float)" })

-- Cycle focus without opening anything -- the keyboard version of clicking a
-- pill, for when you don't want to aim at one.
map("n", "<leader>aj", function()
  agents.cycle(1)
end, { desc = "Claude: focus next agent (no float)" })
map("n", "<leader>ak", function()
  agents.cycle(-1)
end, { desc = "Claude: focus prev agent (no float)" })
map("n", "<leader>am", function()
  agents.move_to_group(vim.v.count)
end, { desc = "Claude: move agent to a group" })

-- Same picker <leader>aIm shows, but targets the active tmux agent's live
-- session instead of spawning a new terminal.
map("n", "<leader>ai", function()
  agents.select_model(vim.v.count)
end, { desc = "Claude: switch model (active agent)" })

-- Sends. Each takes an optional count -- `2<leader>as` delivers to agent 2
-- without moving focus -- and the number is printed on the statusline pill, so
-- it is read rather than memorised.
map("n", "<leader>al", function()
  local file = vim.fn.fnamemodify(vim.fn.expand("%:p"), ":.")
  agents.send(("@%s:%d "):format(file, vim.fn.line(".")), vim.v.count)
end, { desc = "Claude: mention current line" })

map("n", "<leader>aM", function()
  local buf = vim.api.nvim_get_current_buf()
  local count = vim.v.count
  local lines = marks.lines(buf)
  if #lines == 0 then
    vim.notify("No marked lines in this buffer (<leader>mm to mark)", vim.log.levels.WARN)
    return
  end
  agents.send(marks.blocks(buf, lines), count, function()
    marks.clear(buf)
  end)
end, { desc = "Claude: send all marked lines" })

map("v", "<leader>as", function()
  local count = vim.v.count
  vim.cmd("normal! \27") -- leave visual mode so '< '> marks are set
  local s, e = vim.fn.line("'<"), vim.fn.line("'>")
  local file = vim.fn.fnamemodify(vim.fn.expand("%:p"), ":.")
  local lines = vim.api.nvim_buf_get_lines(0, s - 1, e, false)
  agents.send(("%s:%d-%d\n```\n%s\n```\n"):format(file, s, e, table.concat(lines, "\n")), count)
end, { desc = "Claude: send selection" })

map("n", "<leader>mm", marks.toggle, { desc = "Toggle send-mark on this line" })
map("v", "<leader>mm", marks.toggle_visual, { desc = "Toggle send-mark on selected lines" })
map("n", "<leader>mc", function()
  marks.clear(vim.api.nvim_get_current_buf())
  vim.notify("Cleared all send marks in this buffer")
end, { desc = "Clear all send marks" })

-- Group labels only -- which-key's own registry, NOT real mappings, so the
-- prefixes stay prefixes and keep costing nothing to type through.
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  callback = function()
    local ok, wk = pcall(require, "which-key")
    if ok then
      wk.add({
        { "<leader>a", group = "ai" },
        { "<leader>aI", group = "ai-review (mcp)" },
        { "<leader>m", group = "send-marks" },
      })
    end
  end,
})

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
