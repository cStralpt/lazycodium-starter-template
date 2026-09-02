-- A persistent, tmux-backed workspace rendered in one Neovim float.
--
-- Generalized out of util/floating_term.lua, which is now one instance of it
-- (<C-/>, running fish); util/claude_agents.lua is the second (<leader>ac,
-- running claude). Everything below -- session grouping for collaboration,
-- the workspace hand-off on <leader>iss, the clickable rainbow pills, pane
-- navigation, the resize nudge -- was written and debugged for the terminal
-- float and is shared verbatim rather than reimplemented per workspace.
--
-- One float is really a client attached to a tmux session. Because the
-- session lives in tmux (not in a Neovim buffer/job), it survives hiding and
-- showing the float completely unaffected -- and splitting into panes or
-- opening a new "tab" (a tmux window) is just `tmux split-window` /
-- `tmux new-window` against that session: real tmux underneath, with
-- convenient Neovim keymaps on top instead of learning tmux's prefix key.
--
-- Collaboration:
--   - Not collaborating: one session per Neovim instance (keyed by pid),
--     shared across all of THIS instance's tabs.
--   - Collaborating (vim.g.instant_root_port set): one CANONICAL session per
--     root session (keyed by port alone), so every collaborator window shares
--     the exact same windows/panes -- same running processes, same output,
--     real shared state. But each window attaches via its OWN tmux session,
--     grouped (`tmux new-session -t canonical`) with the canonical one rather
--     than literally being it: session groups share windows/panes (state) but
--     track "current window" per session independently, so switching
--     groups/panes in one collaborator's view never yanks another
--     collaborator's view along with it.
--
-- Deliberately NOT keyed by Neovim tab number. A workspace already has
-- first-class grouping INSIDE it -- tmux windows, the clickable pills on the
-- winbar -- so a second, invisible split along Neovim tabs on top of that
-- bought nothing and actively confused things: tab numbers do not line up
-- between collaborating windows (a joining mirror lands on whatever tab its
-- bootstrap left it on, not the host's), so the same float resolved to a
-- DIFFERENT session per window and every collaborator but the host opened an
-- empty terminal while the real one kept running, invisible, under a name
-- nobody was looking at. One workspace per session, groups within it.

local rainbow = require("util.rainbow_tabs")

local M = {}

---@class TmuxWorkspaceConfig
---@field id string unique, used to name this instance's global winbar/click functions
---@field local_prefix string session name prefix used outside collaboration (suffixed with pid)
---@field root_prefix string session name prefix used while collaborating (suffixed with the root port)
---@field cmd string|fun():string command new sessions/windows/panes run
---@field set_global_shell boolean set tmux's GLOBAL default-shell/default-command to cmd. Only
---       true for the terminal workspace: it makes bare `new-window` inherit fish. The Claude
---       workspace must never do this -- it would make every tmux window on the box run claude.
---@field shared_local boolean when true the non-collaborative session name carries NO pid, so every
---       Neovim on this machine shares one workspace. The terminal float is per-instance (false);
---       the Claude workspace is shared (true), because agents must be reachable from any window.
---@field always_group boolean when true this instance always attaches through its own pid-suffixed
---       grouped session, not just while collaborating. Required alongside shared_local: without it
---       every window would BE the shared session and switching group in one would yank all of them.
---@field kill_when_last boolean tear the shared canonical session down once the last Neovim using
---       it exits. Only meaningful with shared_local: a per-instance workspace is already owned and
---       killed by its own instance.
---@field float { width: number, height: number }
---@field missing_msg string shown when an action runs before the workspace exists

---@param config TmuxWorkspaceConfig
function M.new(config)
  local W = {}

  local function cmd()
    return type(config.cmd) == "function" and config.cmd() or config.cmd
  end

  ---The session name used before collaboration is involved: one workspace per
  ---Neovim instance, shared across all of this instance's tabs.
  local function local_session()
    if config.shared_local then
      return config.local_prefix
    end
    return ("%s-%d"):format(config.local_prefix, vim.fn.getpid())
  end

  ---The session holding the actual state (windows, panes, running processes)
  ----- shared with every collaborator window in the same root session.
  ---
  ---NOTE this name is NOT stable for the lifetime of a workspace: it changes
  ---the moment vim.g.instant_root_port is set (<leader>iss), even though the
  ---tmux session it used to name is still alive and full of your work. See
  ---adopt_workspace() for how that hand-off is made non-destructive.
  local function canonical_session()
    -- A shared_local workspace has ONE name, forever, collaborating or not.
    --
    -- Renaming it per root session was actively harmful. The collaboration
    -- rename exists so a per-instance workspace can be handed to the session
    -- you just joined -- but a shared workspace is already machine-wide, so the
    -- root port adds nothing, and always_group makes its canonical session
    -- permanently GROUPED (every Neovim attaches via "<name>-w<pid>").
    -- adopt_workspace refuses to rename a grouped session, correctly, since
    -- that would yank the workspace out from under other windows -- so the
    -- hand-off could never succeed. <leader>iss therefore abandoned the live
    -- workspace and built a second one beside it: two sets of agents, both
    -- running, ~1.4GB of duplicated Claude processes, with only the new set
    -- reachable from the pickers.
    if config.shared_local then
      return local_session()
    end
    if vim.g.instant_root_port then
      return ("%s-root%s"):format(config.root_prefix, tostring(vim.g.instant_root_port))
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
    if vim.g.instant_root_port or config.always_group then
      return canonical .. ("-w%d"):format(vim.fn.getpid())
    end
    return canonical
  end
  W.session = my_session

  -- Sessions we have seen alive, and when. Only POSITIVE results are cached: a
  -- session that exists effectively never stops existing mid-burst, while a
  -- negative result must stay uncached or we would skip creating one.
  --
  -- This matters because every action used to re-probe several times, and each
  -- probe is a fork. Under a burst of keypresses those probes are both the
  -- latency and the danger: `has-session` DOES fail transiently while the tmux
  -- server is busy or still starting ("no server running on
  -- /tmp/tmux-1000/default", observed directly), and any code treating one
  -- failed probe as truth then silently does nothing.
  local alive_cache = {}
  local ALIVE_TTL = 1000

  local function session_alive(name)
    local seen_at = alive_cache[name]
    if seen_at and (vim.uv.now() - seen_at) < ALIVE_TTL then
      return true
    end
    vim.fn.system({ "tmux", "has-session", "-t", name })
    if vim.v.shell_error == 0 then
      alive_cache[name] = vim.uv.now()
      return true
    end
    alive_cache[name] = nil
    return false
  end

  -- Sessions this Neovim instance actually created (as opposed to a shared
  -- canonical session another collaborator created) -- always safe to kill on
  -- exit, since each name is unique to this pid by construction, whether it's
  -- a plain non-collab session or a collab grouped one. A shared collab
  -- canonical session created by SOMEONE ELSE is never in here, so we never
  -- pull the workspace out from under another collaborator.
  local owned_sessions = {}

  ---What canonical_session() resolved to the last time this instance actually
  ---opened the float -- i.e. where its real workspace lives right now,
  ---regardless of what the name would be recomputed as today.
  ---@type string?
  local workspace_session = nil

  ---Whether some OTHER session shares `name`'s windows (a tmux session group).
  ---A collaborative canonical session always is -- every collaborator's view
  ---session is grouped with it -- while the pre-collab, pid-keyed one never
  ---is. A failed query counts as grouped: never rename something we couldn't
  ---check.
  local function session_grouped(name)
    local out = vim.fn.system({ "tmux", "display-message", "-p", "-t", name, "#{session_group}" })
    if vim.v.shell_error ~= 0 then
      return true
    end
    return vim.trim(out) ~= ""
  end

  ---Carry this instance's existing workspace over to a NEW canonical name
  ---instead of silently abandoning it.
  ---
  ---canonical_session() is keyed by root port while collaborating and by pid
  ---otherwise, so the instant <leader>iss sets vim.g.instant_root_port, the
  ---session name changes out from under a workspace that is still very much
  ---alive. Without this, toggling simply created that brand-new, EMPTY name
  ---and attached to it, while every window, pane and running process you
  ---already had kept running orphaned under the old name -- still listed by
  ---`tmux ls`, still attached to by the now-abandoned float buffer. That is
  ---exactly the reported bug: "after <leader>iss all my previous terminals and
  ---their groups are gone, but I can still see them in the background".
  ---
  ---A rename moves the entire session -- windows, panes, processes,
  ---scrollback, and the client already attached to it -- under the new name,
  ---so nothing is lost and no state is duplicated.
  ---
  ---Only ever renames an UNGROUPED session, i.e. one no collaborator is
  ---sharing. The pre-collab session always qualifies; a collaborative
  ---canonical one never does, so this can't yank a shared workspace out from
  ---under another window. (The consequence is that the reverse hand-off --
  ---leaving a session with <leader>isS -- still starts fresh rather than
  ---reclaiming the shared one, deliberately: those windows may still be in use
  ---by collaborators, and renaming a session does not remove it from its group
  ---anyway, so "reclaiming" it would keep mirroring after you left.)
  ---@return boolean adopted
  local function adopt_workspace(canonical)
    -- Falling back to the pid-keyed name covers the case where this instance
    -- had a float open but never recorded it -- it is the only other name this
    -- instance's workspace can ever have lived under.
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
    if not vim.g.instant_root_port and not config.shared_local then
      owned_sessions[canonical] = true
    end
    workspace_session = canonical
    return true
  end

  ---Hand this instance's existing workspace to the session it has just joined,
  ---RIGHT NOW rather than whenever the float next happens to open.
  ---
  ---Timing is the whole point. Adoption can only fire while the canonical name
  ---is still unclaimed, and the mirror window spawned by <leader>iss claims it
  ---the first time anyone opens a float in it. So with lazy adoption the
  ---outcome depended purely on who toggled first: host first and the workspace
  ---was carried over correctly, mirror first and the mirror created an empty
  ---canonical session, after which the host found that name already alive,
  ---skipped adoption entirely, and its real workspace stayed orphaned under
  ---the old name. Claiming eagerly, before the mirror even exists, removes the
  ---ordering from the picture.
  ---
  ---No-op when there is nothing to hand over: the canonical session is still
  ---created on demand by whoever opens one first.
  function W.claim_workspace()
    local canonical = canonical_session()
    if session_alive(canonical) then
      return
    end
    adopt_workspace(canonical)
  end

  ---Ensure both the canonical session (state) and, when collaborating, this
  ---instance's own grouped session (view) exist. Returns the session this
  ---instance should attach to.
  local options_applied = false

  local function ensure_session()
    local canonical = canonical_session()
    if not session_alive(canonical) then
      adopt_workspace(canonical)
    end
    if not session_alive(canonical) then
      vim.fn.system({ "tmux", "new-session", "-d", "-s", canonical, "-c", LazyVim.root(), cmd() })
      if config.set_global_shell then
        -- -g (global, not -t canonical): a session-scoped option set on the
        -- canonical session does NOT propagate to a grouped session (verified
        -- directly -- new-window run against a grouped "mine" session fell
        -- back to bash), so a new-tab from a collaborator's own grouped
        -- session would silently miss it. Global only affects panes/windows
        -- created WITHOUT an explicit command, so it can't clobber
        -- shared_terminal.lua's own sessions (those always pass an explicit
        -- cmd) -- nor the Claude workspace, whose every window and pane passes
        -- `claude` explicitly for exactly this reason.
        vim.fn.system({ "tmux", "set-option", "-g", "default-shell", cmd() })
        vim.fn.system({ "tmux", "set-option", "-g", "default-command", cmd() })
      end
      -- Without an explicit "default" background, tmux paints every unstyled
      -- cell (window, status bar, pane borders) a hardcoded black rather than
      -- leaving it untouched -- so instead of showing through Neovim's own
      -- terminal background (which tracks the colorscheme, since nothing in
      -- this config overrides g:terminal_color_*), you get a flat black box
      -- wherever tmux itself painted anything. `bg=default` tells tmux to emit
      -- plain SGR 49 ("default background", no explicit color) instead --
      -- these apply live at render time, not at pane-creation time, so
      -- ordering relative to `new-session` above doesn't matter.
      vim.fn.system({ "tmux", "set-option", "-g", "window-style", "bg=default" })
      vim.fn.system({ "tmux", "set-option", "-g", "window-active-style", "bg=default" })
      vim.fn.system({ "tmux", "set-option", "-g", "status-style", "bg=default" })
      vim.fn.system({ "tmux", "set-option", "-g", "pane-border-style", "bg=default" })
      vim.fn.system({ "tmux", "set-option", "-g", "pane-active-border-style", "bg=default" })
      if not vim.g.instant_root_port and not config.shared_local then
        owned_sessions[canonical] = true
      end
    end

    -- Scrollback. `tmux attach` runs on the ALTERNATE screen, so Neovim's own
    -- terminal scrollback for this buffer is permanently empty -- scrolling up
    -- in the Neovim window can never reach anything tmux drew, no matter how
    -- large 'scrollback' is. The history lives in tmux, one independent buffer
    -- PER PANE, and the only way in is tmux's copy-mode. With `mouse off`
    -- (tmux's default) the wheel isn't bound to anything either, so nothing
    -- scrolls at all -- output above the viewport just looks truncated.
    --
    -- `mouse on` binds the wheel to "enter copy-mode in the pane UNDER THE
    -- CURSOR", which is exactly per-pane scrolling for splits. Neovim forwards
    -- the wheel to the job whenever the program asked for mouse reporting
    -- (mouse=a here), so this works through the float with no Neovim mapping.
    --
    -- Applied once per Neovim instance rather than on every call. They used to
    -- run on EVERY action so an already-running session (started before this
    -- block existed, or by another window) would pick them up -- but these are
    -- GLOBAL tmux options, so one application covers every session on the
    -- server, and re-issuing them per keypress was three forks of pure waste in
    -- the hot path.
    if not options_applied then
      options_applied = true
      vim.fn.system({ "tmux", "set-option", "-g", "mouse", "on" })
      vim.fn.system({ "tmux", "set-option", "-g", "history-limit", "50000" })
      vim.fn.system({ "tmux", "set-window-option", "-g", "mode-keys", "vi" })
    end

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
  W.ensure_session = ensure_session

  ---Run a tmux subcommand targeted at THIS instance's current view session.
  ---No-ops with a notice if the workspace hasn't been started yet.
  ---@param args string[] e.g. { "split-window", "-h" }
  ---Run a tmux subcommand against THIS instance's view session.
  ---
  ---Runs the command and checks ITS exit status, rather than probing
  ---`has-session` first and bailing when that probe fails. Probe-then-act was
  ---the cause of "pressing keys quickly sometimes does nothing": the probe is a
  ---separate fork whose result can be stale by the time the real command runs
  ---(a TOCTOU window), and a transient failure -- which genuinely happens while
  ---the tmux server is loaded or starting ("no server running on
  ---/tmp/tmux-1000/default", observed directly) -- made the action silently
  ---return.
  ---
  ---A failure is then TRIAGED rather than assumed. Only when the session is
  ---genuinely gone do we ensure-and-retry; otherwise tmux's own message is
  ---reported. That distinction matters: the most common real failure here is
  ---"no space for a new pane" (tmux refuses to split below a minimum size, and
  ---a float four ways split hits it quickly), which the previous version either
  ---swallowed entirely or -- worse -- reported as "no workspace yet", sending
  ---you to press <leader>ac at a workspace that was right there.
  ---@param args string[] e.g. { "split-window", "-h" }
  ---@return boolean ok
  local function tmux(args)
    local function run()
      local full = { "tmux", args[1], "-t", my_session() }
      for i = 2, #args do
        full[#full + 1] = args[i]
      end
      local out = vim.fn.system(full)
      return vim.v.shell_error == 0, vim.trim(out or "")
    end

    local ok, err = run()
    if ok then
      return true
    end

    -- Whatever we cached about this session is suspect now; re-probe for real.
    alive_cache[my_session()] = nil
    if not session_alive(my_session()) then
      ensure_session()
      ok, err = run()
      if ok then
        return true
      end
      vim.notify(config.missing_msg, vim.log.levels.WARN)
      return false
    end

    -- The session is alive, so this is a genuine tmux refusal. Say what it was.
    vim.notify(err ~= "" and ("tmux: " .. err) or ("tmux " .. args[1] .. " failed"), vim.log.levels.WARN)
    return false
  end

  ---Force a genuine pty resize round-trip, so the underlying `tmux attach`
  ---process gets a REAL SIGWINCH and does its own full reflow+redraw -- the
  ---same thing that already happens correctly whenever you resize your actual
  ---terminal window. Needed because reopening a hidden float at identical
  ---rows/cols never generates an actual size change, so nothing ever prompts
  ---tmux to repaint; its last frame from before hiding just sits stale in
  ---whatever cells the fresh content didn't happen to overwrite. Switching
  ---tmux to `bg=default` didn't cause this, it just stopped hiding it -- the
  ---stale cells kept their old black fill while everything genuinely redrawn
  ---now shows through in theme color instead.
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

  -- Per-instance global function names. 'winbar'/'statusline' click syntax and
  -- %{% %} expressions only accept a callable NAME, never a closure, so each
  -- workspace registers its own pair rather than sharing one.
  local WINBAR_FN = "TmuxWorkspaceWinbar_" .. config.id
  local CLICK_FN = "TmuxWorkspaceClick_" .. config.id

  ---The float's 'winbar' is set to this EXPRESSION, never to a rendered
  ---string, and it is handed to Snacks as part of the window config rather
  ---than assigned afterwards. Both halves matter:
  ---
  ---  - Snacks re-applies its own `opts.wo` on several paths (:update, which
  ---    VimResized reaches via on_resize, plus set_buf and show), and for a
  ---    float terminal it hard-sets `wo.winbar = ""`. Anything painted on
  ---    afterwards is wiped the next time any of those runs, with no WinEnter
  ---    to notice -- which is why the pills vanished on resize and only came
  ---    back when creating a group happened to repaint them. Passing OUR value
  ---    in `wo` means every re-apply restores the indicator instead.
  ---  - An expression stays correct across those re-applies where a rendered
  ---    string would not: the same constant always re-evaluates to the CURRENT
  ---    groups, so a stale repaint is impossible.
  ---
  ---`%{% %}` (not plain `%{ }`) because the result is itself statusline markup
  ---- highlight groups and click regions - that has to be interpreted, not
  ---printed literally.
  local WINBAR = ("%%{%%v:lua.%s()%%}"):format(WINBAR_FN)

  local refresh_indicator

  ---Click handler for a winbar tab pill. Reads my_session() itself rather than
  ---capturing a target, since the click syntax can only name a global.
  ---@param minwid integer the tmux window index, passed as the click item's minwid
  _G[CLICK_FN] = function(minwid)
    local target = my_session()
    if session_alive(target) then
      vim.fn.system({ "tmux", "select-window", "-t", target .. ":" .. minwid })
    end
    refresh_indicator()
  end

  ---Rounded-pill winbar for this workspace's tmux windows ("tabs"), mirroring
  ---the rainbow bufferline tabpage indicator in the corner of the editor
  ---tabline: one uniquely-colored pill per tmux window, and -- like clicking
  ---an editor tab to switch to it -- clickable to jump straight to that tmux
  ---window instead of only via [ / ].
  local function tab_indicator()
    local target = my_session()
    -- No separate has-session probe: list-windows already fails on a session
    -- that isn't there, and this runs on a timer, so halving the number of
    -- tmux subprocesses per refresh is worth having.
    local out = vim.fn.system({
      "tmux",
      "list-windows",
      "-t",
      target,
      "-F",
      -- window_zoomed_flag rides along here instead of a separate
      -- display-message call: one fork per indicator rebuild, not two.
      "#{window_index}:#{window_active}:#{window_zoomed_flag}",
    })
    if vim.v.shell_error ~= 0 then
      return ""
    end
    -- A zoomed group gets a marker on its pill. Without it, "some panes are
    -- hidden right now" is invisible state -- you'd see one pane and have no
    -- cue that the others still exist, which is exactly how a zoom toggle
    -- becomes confusing rather than convenient.
    local parts = {}
    for index, active, zoomed in out:gmatch("(%d+):(%d):(%d)") do
      local is_active = active == "1"
      local label = zoomed == "1" and (index .. " \u{26f6}") or index
      table.insert(parts, rainbow.pill(tonumber(index), is_active, label, "v:lua." .. CLICK_FN))
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

  ---Rebuild the pill row and, if it actually changed, redraw. Called from the
  ---TTL path below and directly by every action that changes the group list,
  ---so those feel immediate rather than waiting out the interval.
  function refresh_indicator()
    indicator.at = vim.uv.now()
    local text = tab_indicator()
    if text ~= indicator.text then
      indicator.text = text
      pcall(vim.cmd, "redrawstatus!")
    end
  end
  W.refresh_indicator = refresh_indicator

  ---What the winbar expression evaluates to. Returns the cached row and, when
  ---stale, schedules the rebuild rather than doing it inline: this runs inside
  ---a redraw, which is no place for a blocking subprocess call. `pending`
  ---keeps a burst of redraws from queueing a rebuild each.
  ---
  ---Refreshing on a timer rather than only on our own actions means groups a
  ---COLLABORATOR adds to the shared session appear here on their own.
  _G[WINBAR_FN] = function()
    if not indicator.pending and (vim.uv.now() - indicator.at) > INDICATOR_TTL then
      indicator.pending = true
      vim.schedule(function()
        indicator.pending = false
        refresh_indicator()
      end)
    end
    return indicator.text
  end

  ---The float buffer currently on screen, and the exact session it runs
  ---`tmux attach -t` against. Forward-declared here because W.show() (defined
  ---above) reads it: as a local it would otherwise not be in scope there.
  ---@type {buf: integer, target: string}?
  local attached = nil

  local pane_bound = {}

  ---Move between TMUX PANES with the same <C-hjkl> used for Neovim windows
  ---everywhere else. Buffer-local and set only on the float's own buffer, so
  ---it overrides (not adds to) the global <C-hjkl> = ":wincmd" mappings --
  ---without this, those fire instead: since the float is a single Neovim
  ---window wrapping the whole tmux client, ":wincmd h" doesn't reach tmux's
  ---panes, it jumps focus to whatever real Neovim window sits behind the
  ---float, leaving the float visible but unfocused.
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
    -- INDICATOR_TTL old.
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

  ---Drop a float buffer whose session name is no longer the one we should be
  ---attaching to.
  ---
  ---Snacks caches terminals by their COMMAND, and the session name is baked
  ---into ours -- so a name change (going collaborative, or the rename done by
  ---adopt_workspace) makes toggle() open a SECOND float instead of reusing the
  ---existing one. Both would then be live `tmux attach` clients: the stale one
  ---keeps the old buffer sitting in the background, and when both point at the
  ---same workspace tmux shrinks every pane to the smaller client's size.
  ---Deleting the buffer only ends that one attach -- the tmux session and
  ---everything running inside it are untouched.
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

  ---Toggle the float, creating the tmux session the first time this is called.
  ---Build the argv + window opts the float is opened with. Shared by toggle()
  ---and show() so they can never drift apart.
  local function float_spec(target)
    -- Table form, not a string: shared_terminal.lua monkey-patches
    -- vim.fn.termopen to wrap every STRING command through ITS OWN tmux
    -- mirroring layer whenever a collab root session is active. That would nest
    -- our "tmux attach" inside a second, outer tmux session whose job is to run
    -- that attach from a fresh detached pane -- which exits almost immediately,
    -- closing the float right after it opens. Table-form commands pass through
    -- that patch untouched, so this sidesteps it entirely -- we already handle
    -- our own collab sharing via tmux session groups.
    return { "tmux", "attach", "-t", target }, {
      win = {
        position = "float",
        width = config.float.width,
        height = config.float.height,
        border = "rounded",
        -- init.lua sets a global vim.o.winblend = 20 for floats; force this one
        -- opaque so terminal text stays readable. winbar goes through here
        -- rather than being assigned afterwards -- see WINBAR.
        wo = { winblend = 0, winbar = WINBAR },
      },
    }
  end

  ---Record the freshly-opened terminal and do the post-open housekeeping.
  ---snacks.win's `:focus()` has no `return` statement, so the value coming back
  ---from Snacks' own `show():focus()` chain is nil even when the window opened
  ---fine -- trusting it (a version of this file once did) silently skipped the
  ---winbar update on every reopen. So the terminal object is read back out of
  ---Snacks' cache instead of being taken from a return value.
  local function after_open(cmd_argv, target)
    local terminal = Snacks.terminal.get(cmd_argv, { create = false })
    if terminal and terminal.buf then
      attached = { buf = terminal.buf, target = target }
      bind_pane_nav(terminal.buf, target)
    end
    if terminal and terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
      nudge_resize(terminal.win, terminal.buf)
    end
    refresh_indicator()
    return terminal
  end

  ---Toggle the float: open it from the editor, close it from inside. This is
  ---Snacks.terminal.focus's own behaviour -- it hides when the CURRENT buffer
  ---is the terminal's, and shows otherwise.
  function W.toggle()
    local target = ensure_session()
    close_stale_float(target)
    local cmd_argv, opts = float_spec(target)
    Snacks.terminal.focus(cmd_argv, opts)
    after_open(cmd_argv, target)
  end

  ---Open the float, never close it.
  ---
  ---Deliberately does NOT go through toggle()/Snacks.terminal.focus: that hides
  ---when the current buffer is the terminal's, which is exactly wrong for "show
  ---me what I just did". It also does not rely on the `attached` bookkeeping to
  ---decide whether the float is visible -- `attached` records the buffer, not
  ---whether a WINDOW is currently displaying it, so after the float had been
  ---hidden this looked "already open" and skipped the reveal. That is the bug
  ---where <leader>aV created the agent but you still had to press <leader>ac to
  ---see it. The check now asks the only question that matters: is a window
  ---showing this buffer right now?
  function W.show()
    local target = ensure_session()
    close_stale_float(target)
    local cmd_argv, opts = float_spec(target)
    local terminal = Snacks.terminal.get(cmd_argv, opts)
    if not terminal then
      return
    end
    if not (terminal.win and vim.api.nvim_win_is_valid(terminal.win)) then
      terminal:show()
    end
    terminal:focus()
    after_open(cmd_argv, target)
  end

  ---Are we currently sitting inside this workspace's float?
  ---
  ---Asks whether a WINDOW is showing the float's buffer and the cursor is in
  ---it -- not merely whether `attached` has a buffer recorded, which stays set
  ---after the float is hidden.
  function W.in_float()
    return attached ~= nil
      and vim.api.nvim_buf_is_valid(attached.buf)
      and vim.api.nvim_get_current_buf() == attached.buf
  end

  ---Where a new pane should start -- deliberately dependent on WHERE you
  ---pressed the key, because the two cases mean different things.
  ---
  ---From inside the workspace you are pointing at a specific pane: "another one
  ---like this". Inherit that pane's directory. The workspace is shared across
  ---projects, so group 1 may be one repo and group 2 another; splitting inside
  ---a group must stay in that group's repo.
  ---
  ---From the editor you are pointing at a FILE: "a Claude for what I'm working
  ---on". Use that file's project root. Inheriting the active pane there would
  ---root the new agent in whatever project happens to be focused in the
  ---workspace -- so editing a file in project A while the workspace sits on
  ---project B would silently start your agent in the wrong repo.
  ---
  ---An explicit -c is required either way: `split-window` without one does NOT
  ---inherit the split pane's directory -- verified, splitting a pane sitting in
  ---/tmp/projA produced a pane in /home/cstralpt, the directory the tmux SERVER
  ---was started from.
  local function split_cwd()
    if not W.in_float() then
      return LazyVim.root()
    end
    local out = vim.fn.system({ "tmux", "display-message", "-p", "-t", my_session(), "#{pane_current_path}" })
    local path = vim.trim(out)
    if vim.v.shell_error == 0 and path ~= "" then
      return path
    end
    return LazyVim.root()
  end

  ---Extra argv appended to new-window / split-window. The terminal workspace
  ---appends nothing and inherits fish via the global default-command; the
  ---Claude workspace passes `claude` explicitly, because setting it globally
  ---would make EVERY tmux window on this machine run claude.
  local function with_run(args)
    if not config.set_global_shell then
      args[#args + 1] = cmd()
    end
    return args
  end

  ---New pane, stacked top/bottom (mirrors Neovim's :split).
  function W.split_horizontal()
    tmux(with_run({ "split-window", "-v", "-c", split_cwd() }))
    refresh_indicator()
  end

  ---New pane, side by side (mirrors Neovim's :vsplit).
  function W.split_vertical()
    tmux(with_run({ "split-window", "-h", "-c", split_cwd() }))
    refresh_indicator()
  end

  ---New tab (tmux window) -- a fresh group.
  function W.new_tab()
    tmux(with_run({ "new-window", "-c", split_cwd() }))
    refresh_indicator()
  end

  function W.next_tab()
    tmux({ "next-window" })
    refresh_indicator()
  end

  function W.prev_tab()
    tmux({ "previous-window" })
    refresh_indicator()
  end

  ---Every group (tmux window) that exists, in index order.
  ---@return { index: integer, active: boolean, panes: integer }[]
  function W.list_groups()
    local target = my_session()
    if not session_alive(target) then
      return {}
    end
    local out = vim.fn.systemlist({
      "tmux",
      "list-windows",
      "-t",
      target,
      "-F",
      "#{window_index}\t#{window_active}\t#{window_panes}",
    })
    if vim.v.shell_error ~= 0 then
      return {}
    end
    local groups = {}
    for _, line in ipairs(out) do
      local idx, active, panes = line:match("^(%d+)\t(%d)\t(%d+)$")
      if idx then
        groups[#groups + 1] = {
          index = tonumber(idx),
          active = active == "1",
          panes = tonumber(panes),
        }
      end
    end
    return groups
  end

  ---Move the focused pane into an EXISTING group. tmux's own `join-pane`, so
  ---the process keeps running throughout -- this relocates a live pane, it does
  ---not restart anything.
  ---@param group integer|string target: a tmux window index, or any tmux target
  ---       string. A PANE id ("%17") is accepted and is the more precise form --
  ---       tmux splits that exact pane, so the moved agent lands beside the one
  ---       you named rather than beside whichever pane in that window happened
  ---       to be active.
  ---@param stacked boolean? place it below the existing panes instead of beside
  ---       them. Defaults to false -- i.e. side by side, matching what a split
  ---       does. `stacked` rather than "vertical/horizontal" on purpose: Vim
  ---       and tmux use those two words for opposite axes (Vim's :vsplit is
  ---       tmux's -h), and this file already has split_vertical passing "-h",
  ---       so a boolean named for either word is a coin flip at every call.
  ---@return boolean moved
  function W.move_pane_to_group(group, stacked)
    local target = my_session()
    if not session_alive(target) then
      vim.notify(config.missing_msg, vim.log.levels.WARN)
      return false
    end
    -- Resolve the source pane by id FIRST. "the active pane" is a moving
    -- target: join-pane changes which window is current, so a second command
    -- that re-resolves "active" would act on a different pane than the one you
    -- asked to move.
    local src = vim.trim(vim.fn.system({ "tmux", "display-message", "-p", "-t", target, "#{pane_id}" }))
    if vim.v.shell_error ~= 0 or src == "" then
      return false
    end
    -- A window index needs the session prefix; a pane id ("%17") is already a
    -- complete, server-wide target and must be passed through untouched.
    local dest = type(group) == "number" and ("%s:%d"):format(target, group) or tostring(group)
    vim.fn.system({
      "tmux",
      "join-pane",
      -- Side by side by default, so a moved agent lands the same way
      -- <leader>aV places a new one. Defaulting to stacked meant moving an
      -- agent produced a different layout from creating one in the same group,
      -- for no reason you could see or predict.
      stacked and "-v" or "-h",
      "-s",
      src,
      "-t",
      dest,
    })
    if vim.v.shell_error ~= 0 then
      vim.notify(("Cannot move into %s"):format(dest), vim.log.levels.WARN)
      return false
    end
    -- Follow the pane to wherever it ended up. Resolved from the pane itself
    -- rather than from `dest`, since `dest` may be a pane id whose window we
    -- never computed.
    local win = vim.trim(vim.fn.system({ "tmux", "display-message", "-p", "-t", src, "#{window_index}" }))
    if win ~= "" then
      vim.fn.system({ "tmux", "select-window", "-t", ("%s:%s"):format(target, win) })
    end
    vim.fn.system({ "tmux", "select-pane", "-t", src })
    refresh_indicator()
    return true
  end

  ---Move the focused pane OUT into a brand-new group of its own (`break-pane`).
  ---The counterpart to move_pane_to_group when the group you want doesn't
  ---exist yet. No-op with a notice when the pane is already alone in its group,
  ---since tmux refuses to break out the only pane and the error is opaque.
  ---@return boolean moved
  function W.break_pane_to_group()
    local target = my_session()
    if not session_alive(target) then
      vim.notify(config.missing_msg, vim.log.levels.WARN)
      return false
    end
    local panes = vim.trim(vim.fn.system({ "tmux", "display-message", "-p", "-t", target, "#{window_panes}" }))
    if panes == "1" then
      vim.notify("Already alone in its group", vim.log.levels.WARN)
      return false
    end
    vim.fn.system({ "tmux", "break-pane", "-t", target })
    refresh_indicator()
    return vim.v.shell_error == 0
  end

  ---Show ONLY the focused pane, filling its group -- and toggle back. This is
  ---tmux's own `resize-pane -Z`, not something reimplemented: tmux keeps the
  ---other panes running and restores the exact layout on the second press, so
  ---"hide everything but this one" costs no state on our side and can never
  ---get out of sync with the real layout.
  ---
  ---Scoped to the current tmux window, so it hides the other panes in THIS
  ---group only; other groups are untouched and still one pill-click away.
  function W.zoom_pane()
    tmux({ "resize-pane", "-Z" })
    refresh_indicator()
  end

  ---Whether the focused pane is currently zoomed, for indicators.
  function W.is_zoomed()
    local target = my_session()
    if not session_alive(target) then
      return false
    end
    local out = vim.fn.system({ "tmux", "display-message", "-p", "-t", target, "#{window_zoomed_flag}" })
    return vim.v.shell_error == 0 and vim.trim(out) == "1"
  end

  ---Close the current pane. Closing the last pane in the last tab ends the
  ---underlying window (and, once every collaborator's view session has done
  ---the same, the canonical session too), same as in a real terminal.
  function W.close_pane()
    tmux({ "kill-pane" })
    refresh_indicator()
  end

  ---Every pane in this workspace, in window/pane order. The Claude workspace
  ---uses this to enumerate agents; the terminal workspace doesn't need it.
  ---@return { pane: string, window: integer, active: boolean, group_active: boolean, cwd: string }[]
  function W.list_panes()
    local target = my_session()
    if not session_alive(target) then
      return {}
    end
    local out = vim.fn.systemlist({
      "tmux",
      "list-panes",
      "-s",
      "-t",
      target,
      "-F",
      -- window_active matters as much as pane_active: pane_active is set on
      -- ONE pane per window, so every window has an "active" pane. Reading
      -- only that flag makes several panes look focused at once.
      "#{pane_id}\t#{window_index}\t#{pane_active}\t#{window_active}\t#{pane_current_path}",
    })
    if vim.v.shell_error ~= 0 then
      return {}
    end
    local panes = {}
    for _, line in ipairs(out) do
      local id, win, pactive, wactive, path = line:match("^(%S+)\t(%d+)\t(%d)\t(%d)\t(.*)$")
      if id then
        panes[#panes + 1] = {
          pane = id,
          window = tonumber(win),
          active = pactive == "1" and wactive == "1",
          group_active = wactive == "1",
          cwd = path,
        }
      end
    end
    return panes
  end

  ---Is the process behind a "-w<pid>" view session still running? Read from
  ---/proc rather than forking `kill -0`: this runs during exit, where every
  ---subprocess is latency the user waits on.
  local function pid_alive(pid)
    return vim.uv.fs_stat("/proc/" .. pid) ~= nil
  end

  ---Tear down the SHARED canonical session once this is the last Neovim in it.
  ---
  ---A shared workspace is owned by nobody -- that's what lets an agent survive
  ---you quitting and reopening Neovim -- so without this it accumulates
  ---forever, panes from days ago still running. But it must not be a plain kill
  ---either: another window may still be using it.
  ---
  ---So: reference-count by view session. Every instance attaches through its own
  ---"<canonical>-w<pid>", so the live ones ARE the reference count. Once ours is
  ---gone and no sibling remains, nothing is using the workspace and it goes too.
  ---
  ---Stale siblings are reaped by pid, not trusted: a Neovim that crashed or was
  ---SIGKILLed never ran VimLeavePre, so its view session would linger forever
  ---and pin the workspace alive for good -- the exact failure mode that makes
  ---naive refcounting worse than no cleanup at all.
  local function kill_canonical_if_last()
    local canonical = workspace_session or canonical_session()
    if not session_alive(canonical) then
      return
    end
    local mine = my_session()
    local out = vim.fn.systemlist({ "tmux", "list-sessions", "-F", "#{session_name}" })
    if vim.v.shell_error ~= 0 then
      return
    end
    -- PRIMARY signal: does any session sharing this workspace still have a
    -- client attached? tmux tracks that itself, so it survives renames, does
    -- not depend on our naming convention, and needs no stale-entry reaping --
    -- a Neovim that is SIGKILLed takes its tmux client with it, so the count
    -- drops on its own. Name-pattern refcounting broke exactly once already,
    -- when the workspace was renamed and the surviving view sessions no longer
    -- matched the pattern, which would have killed a workspace another window
    -- was still using.
    local group = vim.trim(vim.fn.system({ "tmux", "display-message", "-p", "-t", canonical, "#{session_group}" }))
    if group ~= "" then
      local rows = vim.fn.systemlist({
        "tmux",
        "list-sessions",
        "-F",
        "#{session_name}\t#{session_group}\t#{session_attached}",
      })
      if vim.v.shell_error == 0 then
        for _, row in ipairs(rows) do
          local name, g, attached = row:match("^([^\t]+)\t([^\t]*)\t(%d+)$")
          if name and g == group and attached ~= "0" and name ~= mine then
            return -- someone else still has this workspace open
          end
        end
      end
    end

    -- SECONDARY: a Neovim that never opened the float has no client attached,
    -- but is still using the workspace (it can send to agents). Those are found
    -- by their view session, and only these need the dead-pid reaping.
    --
    -- Scan every sibling BEFORE deciding, rather than returning on the first
    -- live one. Returning early left stale sessions behind whenever a live
    -- sibling happened to sort ahead of them (tmux lists alphabetically, so
    -- "-w291615" precedes "-w999999") -- harmless, since it self-heals on the
    -- next exit, but it made the leftover count depend on pid ordering.
    local others_alive = false
    for _, name in ipairs(out) do
      local pid = name:match("^" .. vim.pesc(canonical) .. "%-w(%d+)$")
      if pid and name ~= mine then
        if pid_alive(tonumber(pid)) then
          others_alive = true
        else
          vim.fn.system({ "tmux", "kill-session", "-t", name })
        end
      end
    end
    if others_alive then
      return -- someone else is still in here; leave the workspace alone
    end
    vim.fn.system({ "tmux", "kill-session", "-t", canonical })
  end

  -- Don't leave orphaned tmux sessions behind once this Neovim instance exits.
  -- Only ever kills sessions THIS instance created (owned_sessions) -- never a
  -- collab canonical session another collaborator might still be using. A
  -- shared canonical session is handled separately, by reference count.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      for name in pairs(owned_sessions) do
        if session_alive(name) then
          vim.fn.system({ "tmux", "kill-session", "-t", name })
        end
      end
      if config.kill_when_last then
        kill_canonical_if_last()
      end
    end,
  })

  return W
end

return M
