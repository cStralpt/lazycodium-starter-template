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
    -- -g (global, not -t canonical): a session-scoped option set on the
    -- canonical session does NOT propagate to a grouped session (verified
    -- directly -- new-window run against a grouped "mine" session fell back
    -- to bash), so <leader>tn from a collaborator's own grouped session
    -- would silently miss it. Global only affects panes/windows created
    -- WITHOUT an explicit command, so it can't clobber shared_terminal.lua's
    -- own sessions (those always pass an explicit cmd).
    vim.fn.system({ "tmux", "set-option", "-g", "default-shell", fish })
    vim.fn.system({ "tmux", "set-option", "-g", "default-command", fish })
    -- Without an explicit "default" background, tmux paints every unstyled
    -- cell (window, status bar, pane borders) a hardcoded black rather than
    -- leaving it untouched -- so instead of showing through Neovim's own
    -- terminal background (which tracks the colorscheme, since nothing in
    -- this config overrides g:terminal_color_*), you get a flat black box
    -- wherever tmux itself painted anything. `bg=default` tells tmux to
    -- emit plain SGR 49 ("default background", no explicit color) instead
    -- -- these apply live at render time, not at pane-creation time, so
    -- ordering relative to `new-session` above doesn't matter.
    vim.fn.system({ "tmux", "set-option", "-g", "window-style", "bg=default" })
    vim.fn.system({ "tmux", "set-option", "-g", "window-active-style", "bg=default" })
    vim.fn.system({ "tmux", "set-option", "-g", "status-style", "bg=default" })
    vim.fn.system({ "tmux", "set-option", "-g", "pane-border-style", "bg=default" })
    vim.fn.system({ "tmux", "set-option", "-g", "pane-active-border-style", "bg=default" })
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

---Force a genuine pty resize round-trip, so the underlying `tmux attach`
---process gets a REAL SIGWINCH and does its own full reflow+redraw -- the
---same thing that already happens correctly whenever you resize your actual
---terminal window (which is why THAT case never shows this bug). Needed
---because reopening a hidden float at identical rows/cols never generates
---an actual size change, so nothing ever prompts tmux to repaint; its last
---frame from before hide() just sits stale in whatever cells the fresh
---content didn't happen to overwrite. This almost certainly predates the
---indicator entirely -- it was just invisible before, since both the stale
---leftover content and the freshly (correctly) drawn content were rendered
---on the same solid black tmux background; switching tmux to `bg=default`
---(to follow the colorscheme, per an earlier request) didn't cause this, it
---just stopped hiding it -- the stale cells kept their old black fill while
---everything genuinely redrawn now shows through in theme color instead.
---@param win integer @param buf integer
local function nudge_resize(win, buf)
  local job = vim.b[buf] and vim.b[buf].terminal_job_id
  if not job then
    return
  end
  local ok_w, width = pcall(vim.api.nvim_win_get_width, win)
  local ok_h, height = pcall(vim.api.nvim_win_get_height, win)
  if not (ok_w and ok_h) then
    return
  end
  -- Resize down then immediately back to the real size: two genuinely
  -- different dimensions, guaranteeing an actual SIGWINCH fires at least
  -- once, unlike calling jobresize with the unchanged size (a likely no-op).
  vim.fn.jobresize(job, math.max(width - 1, 1), height)
  vim.fn.jobresize(job, width, height)
end

---Window currently showing the float, so tab-count changes (new/next/prev/
---close) can refresh its indicator even though each M.toggle() call gets a
---fresh `terminal` object from Snacks rather than a value we already hold.
local current_win = nil

---Forward-declared: `_G.FloatingTermTabClick` below calls this, but as a
---GLOBAL function its body only sees locals already in scope at the point
---it's defined -- `refresh_indicator` didn't exist yet there (it's assigned
---further down), so without this forward declaration the call resolved to
---a nonexistent _G.refresh_indicator instead of this local, erroring
---"attempt to call global 'refresh_indicator' (a nil value)" on every click.
local refresh_indicator

---Click handler for a winbar tab box (registered globally below, invoked via
---`%{minwid}@v:lua.FloatingTermTabClick@...%X` -- Neovim's 'statusline'/
---'winbar' click syntax only accepts a callable *name*, not a closure, so
---this can't be local to tab_indicator() and has to read `my_session()`
---itself rather than capturing `target`).
---@param minwid integer the tmux window index, passed through as the click item's minwid
function _G.FloatingTermTabClick(minwid)
  local target = my_session()
  if session_alive(target) then
    vim.fn.system({ "tmux", "select-window", "-t", target .. ":" .. minwid })
  end
  refresh_indicator()
end

local rainbow = require("util.rainbow_tabs")

---Rounded-pill winbar for the float's tmux windows ("tabs"), mirroring the
---rainbow bufferline tabpage indicator in the corner of the editor tabline:
---one uniquely-colored pill per tmux window, and -- like clicking an editor
---tab to switch to it -- clickable to jump straight to that tmux window
---instead of only via [ / ].
local function tab_indicator()
  local target = my_session()
  if not session_alive(target) then
    return ""
  end
  local out = vim.fn.system({
    "tmux",
    "list-windows",
    "-t",
    target,
    "-F",
    "#{window_index}:#{window_active}",
  })
  if vim.v.shell_error ~= 0 then
    return ""
  end
  local parts = {}
  for index, active in out:gmatch("(%d+):(%d)") do
    local idx = tonumber(index)
    table.insert(parts, rainbow.pill(idx, active == "1", index, "v:lua.FloatingTermTabClick"))
  end
  return table.concat(parts) .. "%#TabLineFill#"
end

---Recompute and apply the winbar on the float's window, if it's currently
---open. Safe to call after any tmux() action even when the float is hidden.
function refresh_indicator()
  if current_win and vim.api.nvim_win_is_valid(current_win) then
    vim.wo[current_win].winbar = tab_indicator()
  end
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
  -- Self-heal the winbar on every re-entry into this buffer's window,
  -- rather than trusting the single set right after M.toggle() returns.
  -- Snacks.win re-applies its OWN `opts.wo` (which defaults winbar = "" for
  -- float terminals -- we never override it) on some show()/update() paths,
  -- which can silently clobber whatever we set a moment earlier depending on
  -- exact timing -- this was the "pills vanish after the 2nd <C-/>" bug.
  -- Scheduled so it runs after any of Snacks' own same-tick option resets.
  vim.api.nvim_create_autocmd("WinEnter", {
    buffer = buf,
    callback = function()
      current_win = vim.api.nvim_get_current_win()
      vim.schedule(refresh_indicator)
    end,
  })
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
  local opts = {
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
  }
  -- This one call does 100% of the actual window management (show / hide /
  -- resize / focus). Its return value is ignored: snacks.win's `:focus()`
  -- has no `return` statement, so on every REOPEN of an already-existing
  -- terminal `Snacks.terminal.focus()`'s own `assert(terminal):show():focus()`
  -- evaluates to nil even though the window opened fine -- so trusting the
  -- return value here (a version of this file once did) silently skipped
  -- the winbar update on every reopen. Instead: let Snacks fully own
  -- toggling, and separately (net-new, side-effect-free) read the SAME
  -- cached terminal object straight out of its own cache afterward, purely
  -- to drive the winbar and the reopen-redraw nudge below.
  Snacks.terminal.focus(cmd, opts)
  local terminal = Snacks.terminal.get(cmd, { create = false })
  if terminal and terminal.buf then
    bind_pane_nav(terminal.buf, target)
  end
  if terminal and terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
    current_win = terminal.win
    nudge_resize(terminal.win, terminal.buf)
  end
  refresh_indicator()
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
  refresh_indicator()
end

function M.next_tab()
  tmux({ "next-window" })
  refresh_indicator()
end

function M.prev_tab()
  tmux({ "previous-window" })
  refresh_indicator()
end

---Close the current pane. Closing the last pane in the last tab ends the
---underlying window (and, once every collaborator's view session has done
---the same, the canonical session too), same as it would in a real
---terminal.
function M.close_pane()
  tmux({ "kill-pane" })
  refresh_indicator()
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
