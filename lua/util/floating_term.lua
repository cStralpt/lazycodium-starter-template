-- A persistent, tmux-backed floating terminal workspace.
--
-- <C-/> toggles ONE near-fullscreen floating window that's really a client
-- attached to a tmux session. Because the session lives in tmux (not in a
-- Neovim buffer/job), it survives hiding/showing the float completely
-- unaffected -- and splitting into panes or opening a new "tab" (a tmux
-- window) is just `tmux split-window` / `tmux new-window` run against that
-- session: real tmux underneath, with convenient <leader>t Neovim keymaps
-- on top instead of learning tmux's prefix key.
--
-- Collaboration (matches the tab-scoped convention shared_terminal.lua and
-- claude-code.lua already use elsewhere):
--   - Not collaborating: one session per Neovim instance (keyed by pid),
--     shared across all of THIS instance's tabs -- unchanged from before.
--   - Collaborating (vim.g.instant_root_port set): the CANONICAL session is
--     keyed by (root port, tab number), so every collaborator window on the
--     same tab shares the exact same windows/panes -- same running
--     processes, same output, real shared state. But each window attaches
--     via its OWN tmux session, grouped (`tmux new-session -t canonical`)
--     with the canonical one rather than literally being it: session groups
--     share windows/panes (state) but track "current window" per session
--     independently, so switching tabs/panes in one collaborator's view
--     never yanks another collaborator's view along with it.
local M = {}

local function tab_id()
  return vim.api.nvim_tabpage_get_number(0)
end

---The session holding the actual state (panes, windows, running
---processes) -- shared with any collaborator window on the same tab.
local function canonical_session()
  if vim.g.instant_root_port then
    return ("floatterm-root%s-tab%d"):format(tostring(vim.g.instant_root_port), tab_id())
  end
  return ("nvim-float-%d"):format(vim.fn.getpid())
end

---The session THIS Neovim instance actually attaches to. Equal to the
---canonical session outside collaboration (nothing to group); a distinct,
---pid-suffixed, grouped session while collaborating, so this window's
---current-tab/pane navigation stays independent of every other
---collaborator's.
local function my_session()
  local canonical = canonical_session()
  if vim.g.instant_root_port then
    return canonical .. ("-w%d"):format(vim.fn.getpid())
  end
  return canonical
end

local function session_alive(name)
  vim.fn.system({ "tmux", "has-session", "-t", name })
  return vim.v.shell_error == 0
end

---Full path to fish, falling back to Neovim's own default shell if fish
---isn't installed -- resolved once and reused, since it can't change
---mid-session.
local fish = vim.fn.exepath("fish")
if fish == "" then
  fish = vim.o.shell
end

-- Sessions this Neovim instance actually created (as opposed to a shared
-- canonical session another collaborator created) -- always safe to kill on
-- exit, since each name is unique to this pid by construction, whether it's
-- a plain non-collab session or a collab grouped one. A shared collab
-- canonical session created by SOMEONE ELSE is never in here, so we never
-- pull the terminal state out from under another collaborator.
local owned_sessions = {}

---Ensure both the canonical session (state) and, when collaborating, this
---instance's own grouped session (view) exist. Returns the session this
---instance should attach to.
local function ensure_session()
  local canonical = canonical_session()
  if not session_alive(canonical) then
    vim.fn.system({ "tmux", "new-session", "-d", "-s", canonical, "-c", LazyVim.root(), fish })
    vim.fn.system({ "tmux", "set-option", "-t", canonical, "default-shell", fish })
    vim.fn.system({ "tmux", "set-option", "-t", canonical, "default-command", fish })
    if not vim.g.instant_root_port then
      owned_sessions[canonical] = true
    end
  end

  local mine = my_session()
  if mine ~= canonical then
    if not session_alive(mine) then
      vim.fn.system({ "tmux", "new-session", "-d", "-s", mine, "-t", canonical })
    end
    owned_sessions[mine] = true
  end
  return mine
end

---Run a tmux subcommand targeted at THIS instance's current view session.
---No-ops with a notice if it hasn't been started yet (<C-/> first).
---@param args string[] e.g. { "split-window", "-h" }
local function tmux(args)
  local target = my_session()
  if not session_alive(target) then
    vim.notify("No floating terminal yet (<C-/> to start one)", vim.log.levels.WARN)
    return
  end
  local full = { "tmux", args[1], "-t", target }
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
---@param target string the exact session THIS buffer is attached to
local function bind_pane_nav(buf, target)
  if pane_bound[buf] then
    return
  end
  pane_bound[buf] = true
  local dirs = { h = "-L", j = "-D", k = "-U", l = "-R" }
  for key, flag in pairs(dirs) do
    vim.keymap.set({ "n", "t" }, "<C-" .. key .. ">", function()
      vim.fn.system({ "tmux", "select-pane", "-t", target, flag })
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
  local target = ensure_session()
  -- Table form, not a string: shared_terminal.lua monkey-patches
  -- vim.fn.termopen to wrap every STRING command through ITS OWN tmux
  -- mirroring layer whenever a collab root session is active. That would
  -- nest our "tmux attach" inside a second, outer tmux session whose job is
  -- to run that attach from a fresh detached pane -- which exits almost
  -- immediately, closing the float right after it opens. Table-form
  -- commands are documented (shared_terminal.lua) to pass through that
  -- patch untouched, so this sidesteps it entirely -- we already handle our
  -- own collab sharing above via tmux session groups.
  local cmd = { "tmux", "attach", "-t", target }
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
    bind_pane_nav(terminal.buf, target)
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
---underlying window (and, once every collaborator's view session has done
---the same, the canonical session too), same as it would in a real
---terminal.
function M.close_pane()
  tmux({ "kill-pane" })
end

-- Don't leave orphaned tmux sessions behind once this Neovim instance
-- exits. Only ever kills sessions THIS instance created (owned_sessions) --
-- never a collab canonical session another collaborator might still be
-- using.
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    for name in pairs(owned_sessions) do
      if session_alive(name) then
        vim.fn.system({ "tmux", "kill-session", "-t", name })
      end
    end
  end,
})

return M
