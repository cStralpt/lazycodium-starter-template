-- A persistent, tmux-backed floating terminal workspace.
--
-- <C-/> toggles ONE near-fullscreen floating window that's really just a
-- client attached to a tmux session named after this Neovim instance's pid.
-- Because the session lives in tmux (not in a Neovim buffer/job), it survives
-- hiding/showing the float completely unaffected -- and splitting into panes
-- or opening a new "tab" (a tmux window) is just `tmux split-window` /
-- `tmux new-window` run against that session: real tmux underneath, with
-- convenient <leader>t Neovim keymaps on top instead of learning tmux's
-- prefix key.
--
-- Deliberately one session per Neovim instance (keyed by pid), not one
-- global session shared across every Neovim you have open -- so two
-- concurrent Neovim instances never fight over the same tmux windows/panes.
local M = {}

local session = ("nvim-float-%d"):format(vim.fn.getpid())

local function session_alive()
  vim.fn.system({ "tmux", "has-session", "-t", session })
  return vim.v.shell_error == 0
end

---Full path to fish, falling back to Neovim's own default shell if fish
---isn't installed -- resolved once and reused, since it can't change
---mid-session.
local fish = vim.fn.exepath("fish")
if fish == "" then
  fish = vim.o.shell
end

---Create the session (fish, rooted at the project dir) the first time
---<C-/> is pressed. `default-shell`/`default-command` make every pane
---split-window or new-window creates afterwards run fish too, without
---having to pass it explicitly on every tmux call.
local function ensure_session()
  if session_alive() then
    return
  end
  vim.fn.system({ "tmux", "new-session", "-d", "-s", session, "-c", LazyVim.root(), fish })
  vim.fn.system({ "tmux", "set-option", "-t", session, "default-shell", fish })
  vim.fn.system({ "tmux", "set-option", "-t", session, "default-command", fish })
end

---Run a tmux subcommand targeted at this instance's float session.
---No-ops with a notice if the session hasn't been started yet (<C-/> first).
---@param args string[] e.g. { "split-window", "-h" }
local function tmux(args)
  if not session_alive() then
    vim.notify("No floating terminal yet (<C-/> to start one)", vim.log.levels.WARN)
    return
  end
  local full = { "tmux", args[1], "-t", session }
  for i = 2, #args do
    full[#full + 1] = args[i]
  end
  vim.fn.system(full)
end

local pane_bound = {}

---Move between TMUX PANES with the same <C-hjkl> you use for Neovim windows
---everywhere else. Buffer-local and set only on the float's own buffer, so
---it overrides (not adds to) the global <C-hjkl> = ":wincmd" mappings --
---without this, those global mappings fire instead: since the float is a
---single Neovim window wrapping the whole tmux client, ":wincmd h" doesn't
---reach tmux's panes, it jumps focus to whatever real Neovim window sits
---behind the float (e.g. your editor), leaving the float visible but
---unfocused -- exactly the "cursor jumped to the editor" bug this fixes.
local function bind_pane_nav(buf)
  if pane_bound[buf] then
    return
  end
  pane_bound[buf] = true
  local dirs = { h = "-L", j = "-D", k = "-U", l = "-R" }
  for key, flag in pairs(dirs) do
    vim.keymap.set({ "n", "t" }, "<C-" .. key .. ">", function()
      vim.fn.system({ "tmux", "select-pane", "-t", session, flag })
    end, { buffer = buf, desc = "Tmux pane: move " .. key })
  end
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      pane_bound[buf] = nil
    end,
  })
end

---Toggle the floating terminal window, creating the tmux session (fish,
---rooted at the project dir) the first time this is called.
function M.toggle()
  ensure_session()
  -- Table form, not a string: shared_terminal.lua monkey-patches
  -- vim.fn.termopen to wrap every STRING command through ITS OWN tmux
  -- mirroring layer whenever a collab root session is active (<leader>iss).
  -- That would nest our "tmux attach" inside a second, outer tmux session
  -- whose job is to run that attach from a fresh detached pane -- which
  -- exits almost immediately, closing the float right after it opens.
  -- Table-form commands are documented (shared_terminal.lua) to pass
  -- through that patch untouched, so this sidesteps it entirely.
  local cmd = { "tmux", "attach", "-t", session }
  local terminal = Snacks.terminal.focus(cmd, {
    win = {
      position = "float",
      width = 0.97,
      height = 0.95,
      border = "rounded",
      -- init.lua sets a global vim.o.winblend = 20 for floats; force this
      -- one opaque so terminal text stays readable (same fix claude-code.lua
      -- applies to its own floating layout).
      wo = { winblend = 0 },
    },
  })
  if terminal and terminal.buf then
    bind_pane_nav(terminal.buf)
  end
end

---New pane, stacked top/bottom (mirrors Neovim's :split).
function M.split_horizontal()
  tmux({ "split-window", "-v" })
end

---New pane, side by side (mirrors Neovim's :vsplit).
function M.split_vertical()
  tmux({ "split-window", "-h" })
end

---New tab (tmux window) -- a fresh terminal group, back at the project root.
function M.new_tab()
  tmux({ "new-window", "-c", LazyVim.root() })
end

function M.next_tab()
  tmux({ "next-window" })
end

function M.prev_tab()
  tmux({ "previous-window" })
end

---Close the current pane. Closing the last pane in the last tab ends the
---tmux session too, same as it would in a real terminal.
function M.close_pane()
  tmux({ "kill-pane" })
end

-- Don't leave orphaned tmux sessions behind once this Neovim instance exits.
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    if session_alive() then
      vim.fn.system({ "tmux", "kill-session", "-t", session })
    end
  end,
})

return M
