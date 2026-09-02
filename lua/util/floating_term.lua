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
-- Collaboration:
--   - Not collaborating: one session per Neovim instance (keyed by pid),
--     shared across all of THIS instance's tabs.
--   - Collaborating (vim.g.instant_root_port set): one CANONICAL session
--     per root session (keyed by port alone), so every collaborator window
--     shares the exact same windows/panes -- same running processes, same
--     output, real shared state. But each window attaches via its OWN tmux
--     session, grouped (`tmux new-session -t canonical`) with the canonical
--     one rather than literally being it: session groups share
--     windows/panes (state) but track "current window" per session
--     independently, so switching groups/panes in one collaborator's view
--     never yanks another collaborator's view along with it.
--
-- Deliberately NOT keyed by Neovim tab number, unlike shared_terminal.lua
-- and claude-code.lua (whose whole point is one Claude conversation per
-- tab). This float already has its own first-class grouping INSIDE it --
-- tmux windows, the clickable pills on the winbar -- so a second, invisible
-- split along Neovim tabs on top of that bought nothing and actively
-- confused things: tab numbers do not line up between collaborating
-- windows (a joining mirror lands on whatever tab its bootstrap left it on,
-- not the host's), so the same float resolved to a DIFFERENT session per
-- window and every collaborator but the host opened an empty terminal while
-- the real one kept running, invisible, under a name nobody was looking at.
-- One float workspace per session, groups for separation within it.
local M = {}

---The session name used before collaboration is involved: one workspace per
---Neovim instance, shared across all of this instance's tabs.
local function local_session()
  return ("nvim-float-%d"):format(vim.fn.getpid())
end

---The session holding the actual state (windows, panes, running processes)
----- shared with every collaborator window in the same root session.
---
---NOTE this name is NOT stable for the lifetime of a workspace: it changes
---the moment vim.g.instant_root_port is set (<leader>iss), even though the
---tmux session it used to name is still alive and full of your terminals.
---See adopt_workspace() for how that hand-off is made non-destructive.
local function canonical_session()
  if vim.g.instant_root_port then
    return ("floatterm-root%s"):format(tostring(vim.g.instant_root_port))
  end
  return local_session()
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

---What canonical_session() resolved to the last time this instance actually
---opened the float -- i.e. where its real workspace lives right now,
---regardless of what the name would be recomputed as today.
---@type string?
local workspace_session = nil

---Whether some OTHER session shares `name`'s windows (a tmux session
---group). A collaborative canonical session always is -- every
---collaborator's view session is grouped with it -- while the pre-collab,
---pid-keyed one never is. A failed query counts as grouped: never rename
---something we couldn't check.
local function session_grouped(name)
  local out = vim.fn.system({ "tmux", "display-message", "-p", "-t", name, "#{session_group}" })
  if vim.v.shell_error ~= 0 then
    return true
  end
  return vim.trim(out) ~= ""
end

---Carry this instance's existing workspace over to a NEW canonical name instead
---of silently abandoning it.
---
---canonical_session() is keyed by root port while collaborating and by pid
---otherwise, so the instant <leader>iss sets
---vim.g.instant_root_port, the float's session name changes out from under a
---workspace that is still very much alive. Without this, <C-/> simply
---created that brand-new, EMPTY name and attached to it, while every
---window, pane and running process you already had kept running orphaned
---under the old name -- still listed by `tmux ls`, still attached to by the
---now-abandoned float buffer. That is exactly the reported bug: "after
---<leader>iss all my previous terminals and their groups are gone, but I
---can still see them in the background".
---
---A rename moves the entire session -- windows, panes, processes,
---scrollback, and the client already attached to it -- under the new name,
---so nothing is lost and no state is duplicated.
---
---Only ever renames an UNGROUPED session, i.e. one no collaborator is
---sharing. The pre-collab session always qualifies; a collaborative
---canonical one never does, so this can't yank a shared workspace out from
---under another window. (The consequence is that the reverse hand-off --
---leaving a session with <leader>isS -- still starts a fresh float rather
---than reclaiming the shared one, deliberately: those windows may still be
---in use by collaborators, and renaming a session does not remove it from
---its group anyway, so "reclaiming" it would keep mirroring after you left.)
---@return boolean adopted
local function adopt_workspace(canonical)
  -- Falling back to the pid-keyed name covers the case where this instance
  -- had a float open but never recorded it (nothing to record before this
  -- existed) -- it is the only other name this instance's workspace can
  -- ever have lived under.
  local previous = workspace_session or local_session()
  if previous == canonical or not session_alive(previous) then
    return false
  end
  if session_grouped(previous) then
    return false
  end
  vim.fn.system({ "tmux", "rename-session", "-t", previous, canonical })
  if vim.v.shell_error ~= 0 then
    return false
  end
  -- Ownership follows the session, not the name -- but only under the same
  -- rule the creation path uses: a collaborative canonical session is never
  -- ours to kill at exit, since a mirror window may still be attached to it.
  owned_sessions[previous] = nil
  if not vim.g.instant_root_port then
    owned_sessions[canonical] = true
  end
  workspace_session = canonical
  return true
end

---Hand this instance's existing float workspace to the session it has just
---joined, RIGHT NOW rather than whenever <C-/> next happens to run.
---
---Timing is the whole point. Adoption can only fire while the canonical
---name is still unclaimed, and the mirror window spawned by <leader>iss
---claims it the first time anyone opens a float in it. So with lazy
---adoption the outcome depended purely on who pressed <C-/> first: host
---first and the workspace was carried over correctly, mirror first and the
---mirror created an empty canonical session, after which the host found
---that name already alive, skipped adoption entirely, and its real
---workspace stayed orphaned under the old name -- "press <leader>iss, hit
---<C-/> in the other window, and my whole terminal state is gone", while
---doing it in the other order worked fine. Claiming eagerly, before the
---mirror even exists, removes the ordering from the picture.
---
---No-op when there is nothing to hand over (no float open yet): the
---canonical session is still created on demand by whoever opens one first.
function M.claim_workspace()
  local canonical = canonical_session()
  if session_alive(canonical) then
    return
  end
  adopt_workspace(canonical)
end

---Ensure both the canonical session (state) and, when collaborating, this
---instance's own grouped session (view) exist. Returns the session this
---instance should attach to.
local function ensure_session()
  local canonical = canonical_session()
  if not session_alive(canonical) then
    adopt_workspace(canonical)
  end
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

  -- Scrollback. `tmux attach` runs on the ALTERNATE screen, so Neovim's own
  -- terminal scrollback for this buffer is permanently empty -- scrolling up
  -- in the Neovim window can never reach anything tmux drew, no matter how
  -- large 'scrollback' is. The history lives in tmux, one independent buffer
  -- PER PANE, and the only way in is tmux's copy-mode. With `mouse off`
  -- (tmux's default, and nothing here used to change it) the wheel isn't
  -- bound to anything either, so nothing scrolls at all -- output above the
  -- viewport just looks truncated.
  --
  -- `mouse on` binds the wheel to "enter copy-mode in the pane UNDER THE
  -- CURSOR", which is exactly per-pane scrolling for splits: each pane
  -- scrolls its own history, independently, and panes that aren't hovered
  -- stay put. Neovim forwards the wheel to the job whenever the program
  -- asked for mouse reporting (mouse=a here), so this works through the
  -- float without any Neovim-side mapping.
  --
  -- Set on EVERY call, not just at session creation: an already-running
  -- session (e.g. one started before this block existed, or by another
  -- collaborator) picks the options up too. history-limit only applies to
  -- panes created after it, so existing panes keep their old 2000 lines.
  vim.fn.system({ "tmux", "set-option", "-g", "mouse", "on" })
  vim.fn.system({ "tmux", "set-option", "-g", "history-limit", "50000" })
  vim.fn.system({ "tmux", "set-window-option", "-g", "mode-keys", "vi" })

  workspace_session = canonical

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

---The float's 'winbar' is set to this EXPRESSION, never to a rendered
---string, and it is handed to Snacks as part of the window config rather
---than assigned afterwards. Both halves of that matter:
---
---  - Snacks re-applies its own `opts.wo` on several paths (:update, which
---    VimResized reaches via on_resize, plus set_buf and show), and for a
---    float terminal it hard-sets `wo.winbar = ""` (snacks/terminal.lua).
---    Anything we paint on afterwards is wiped the next time any of those
---    runs, with no WinEnter to notice -- which is exactly why the pills
---    vanished when the window was resized and only came back when creating
---    a group happened to repaint them. Passing OUR value in `wo` means
---    every one of those re-applies now restores the indicator instead of
---    erasing it.
---  - An expression stays correct across those re-applies where a rendered
---    string would not: the same constant always re-evaluates to the CURRENT
---    groups, so a stale repaint is impossible.
---
---`%{% %}` (not plain `%{ }`) because the result is itself statusline
---markup -- highlight groups and click regions -- that has to be
---interpreted, not printed literally.
local WINBAR = "%{%v:lua.FloatingTermWinbar()%}"

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
  -- No separate has-session probe: list-windows already fails on a session
  -- that isn't there, and this runs on a timer now, so halving the number of
  -- tmux subprocesses per refresh is worth having.
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

---Last rendered pill row, and when it was built. The winbar expression is
---evaluated on every redraw -- constantly, while a terminal is producing
---output -- and building the row shells out to tmux, so what the expression
---returns is this cached string; the refresh happens off to the side, at
---most every INDICATOR_TTL ms.
local indicator = { text = "", at = 0, pending = false }
local INDICATOR_TTL = 500

---Rebuild the pill row and, if it actually changed, redraw so the new one
---is shown. Called from the TTL path below and directly by every action
---that changes the group list, so those feel immediate rather than waiting
---out the interval.
function refresh_indicator()
  indicator.at = vim.uv.now()
  local text = tab_indicator()
  if text ~= indicator.text then
    indicator.text = text
    pcall(vim.cmd, "redrawstatus!")
  end
end

---What the winbar expression evaluates to. Returns the cached row and, when
---it has gone stale, schedules the rebuild rather than doing it inline:
---this runs inside a redraw, which is no place for a blocking subprocess
---call. `pending` keeps a burst of redraws from queueing a rebuild each.
---
---The side effect of refreshing on a timer rather than only on our own
---actions: groups a COLLABORATOR adds to the shared session now appear here
---on their own, which they previously never did until you touched the
---float yourself.
function _G.FloatingTermWinbar()
  if not indicator.pending and (vim.uv.now() - indicator.at) > INDICATOR_TTL then
    indicator.pending = true
    vim.schedule(function()
      indicator.pending = false
      refresh_indicator()
    end)
  end
  return indicator.text
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
  -- Entering the float is the one moment worth paying for an out-of-band
  -- refresh: the row you are about to look at should be current, not up to
  -- INDICATOR_TTL old. (Keeping the value itself correct is no longer this
  -- autocmd's job -- see WINBAR.)
  vim.api.nvim_create_autocmd("WinEnter", {
    buffer = buf,
    callback = function()
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

---The float buffer currently on screen, and the exact session it runs
---`tmux attach -t` against.
---@type {buf: integer, target: string}?
local attached = nil

---Drop a float buffer whose session name is no longer the one we should be
---attaching to.
---
---Snacks caches terminals by their COMMAND, and the session name is baked
---into ours -- so a name change (going collaborative, or the rename done by
---adopt_workspace) makes M.toggle() open a SECOND float instead of reusing
---the existing one. Both would then be live `tmux attach` clients: the
---stale one keeps the old buffer sitting in the background, and when both
---point at the same workspace tmux shrinks every pane to the smaller
---client's size. Deleting the buffer only ends that one attach -- the tmux
---session and everything running inside it are untouched.
local function close_stale_float(target)
  if not attached or attached.target == target then
    return
  end
  local buf = attached.buf
  attached = nil
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

---Toggle the floating terminal window, creating the tmux session (fish,
---rooted at the project dir) the first time this is called.
function M.toggle()
  local target = ensure_session()
  close_stale_float(target)
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
      -- applies to its own floating layout). winbar goes through here rather
      -- than being assigned to the window afterwards -- see WINBAR.
      wo = { winblend = 0, winbar = WINBAR },
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
    attached = { buf = terminal.buf, target = target }
    bind_pane_nav(terminal.buf, target)
  end
  if terminal and terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
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
