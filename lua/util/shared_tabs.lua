-- The collaboration layer's own magic for tabs: makes tab creation AND
-- which file each tab holds mirror across every window in the same root
-- session, the same way shared_terminal.lua makes terminals mirror -- no
-- plugin or feature opts into this or knows it's happening.
--
-- Two things this deliberately does NOT mirror, both fixed after an
-- earlier version got this wrong:
--   1. Navigation. Switching tabs (gt/gT, clicking a tab) or switching to
--      an already-open buffer within a tab used to be hooked on BufEnter,
--      which fires for that too -- so simply LOOKING at something forced
--      every other window to jump there as well. Fixed by hooking
--      BufNewFile/BufReadPost instead (the same pair instant.nvim itself
--      uses internally) -- these only fire when a file is actually being
--      read from disk for the first time, never on ordinary navigation
--      between buffers that are already open.
--   2. Focus theft. Replaying a remote event used to `:tabnext` to the
--      affected tab, which changes YOUR OWN active tab -- so someone else
--      opening a file anywhere would yank your view over to it. Fixed by
--      updating the target tab's window directly via the API
--      (nvim_tabpage_get_win + nvim_win_set_buf) without ever switching
--      which tab YOU currently have open, and by restoring your original
--      tab after any operation (tab creation, tab close) that would
--      otherwise switch it as a side effect.
-- This is what actually delivers "same tabs/content, independent
-- movement" -- the same principle instant.nvim's own file sync already
-- gives you (shared buffer, independent cursor), just one level up at the
-- tab layer. It is still not full "mirror literally everything": that
-- would require a shared screen (Neovim's own --remote-ui does this, at
-- the cost of forcing one shared cursor across every window -- the
-- opposite of what this whole feature exists for).
--
-- Mechanism: each window appends a tiny event to a per-root-session file
-- on TabNew/BufReadPost/TabClosed, and polls that same file for events
-- from OTHER windows, replaying them locally.
local M = {}

-- Broadcasting/snapshotting always uses the TRUE absolute path (this is a
-- statement of fact: "this is the real file"). But the corresponding
-- buffer instant.nvim's OWN separate content-sync creates on the receiving
-- side is subject to its cwd-relative-or-basename encoding quirk -- so
-- searching for it needs the PREDICTED name, applied here at lookup time,
-- not baked into what gets broadcast. See lua/util/instant_bufname.lua.
local find_synced_buf = require("util.instant_bufname").find_synced_buf

local my_pid = vim.fn.getpid()

local function event_path(port)
  return vim.fn.stdpath("cache") .. "/instant-tabevents-" .. port .. ".jsonl"
end

local function append_event(port, event)
  local f = io.open(event_path(port), "a")
  if f then
    f:write(vim.fn.json_encode(event) .. "\n")
    f:close()
  end
end

local function read_lines(port)
  local f = io.open(event_path(port), "r")
  if not f then
    return {}
  end
  local lines = {}
  for line in f:lines() do
    table.insert(lines, line)
  end
  f:close()
  return lines
end

local installed = false
-- True while REPLAYING a remote event -- without this, replaying it would
-- itself fire TabNew/BufReadPost, get broadcast again, and every window
-- would ping-pong the same event back and forth forever. Held true across
-- an async gap for "file" events (see apply_event) -- a known, accepted
-- race if two remote events land in the same ~400ms poll tick, the first
-- one's async completion could reset this before the second one's replay
-- finishes; low-frequency event stream in practice, not worth a full queue.
local replaying = false
-- port -> number of event lines already processed. Initialized to the
-- file's CURRENT length the first time a port is seen (not 0), so freshly
-- joining/hosting a long-running session doesn't replay its entire
-- tab/file HISTORY on the first poll.
local last_seen = {}

local function bump_last_seen(port)
  last_seen[port] = #read_lines(port)
end

local function snapshot_path(port)
  return vim.fn.stdpath("cache") .. "/instant-tabsnapshot-" .. port .. ".json"
end

---Deletes any pre-existing event log/snapshot for `port` and clears this
---process's own tracking of it, so a NEW session starting on a port
---removes all risk of inheriting an OLD, unrelated session's stale state
---for that same port number (rare even with a wide port range, but a
---real, confirmed-possible failure mode otherwise -- see random_port()'s
---comment in lua/plugins/instant.lua). Exposed because instant.lua calls
---this at the exact moment a NEW host session starts, before writing its
---own fresh snapshot.
function M.reset(port)
  os.remove(event_path(port))
  os.remove(snapshot_path(port))
  last_seen[port] = nil
end

---Finds a real file (buftype "") in `tabpage`, searching EVERY window in
---it -- not just nvim_tabpage_get_win's single "current" window. That
---distinction is exactly what caused a real, confirmed bug: every tab in
---this whole feature's workflow is a file window split next to a Claude
---terminal, and Neovim tracks only ONE "current" window per tab (whichever
---was last focused). If that happens to be the terminal split -- extremely
---likely, since that's where you actually type -- nvim_tabpage_get_win()
---returns the terminal, its buftype isn't "", and the file sitting right
---next to it was invisible to this code entirely: silently recorded as
---"no file here" in the snapshot despite a real file being right there.
local function find_file_in_tabpage(tabpage)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "" then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" then
        return name
      end
    end
  end
  return nil
end
M.find_file_in_tabpage = find_file_in_tabpage

---Same search as find_file_in_tabpage, but returns the WINDOW handle
---instead of the filename -- for actually WRITING an incoming file update
---into the right place. apply_event's "file" replay and
---bootstrap_from_snapshot both used to call nvim_tabpage_get_win()
---directly instead of this, which has the identical bug find_file_in_tabpage
---was written to fix, just on the writing side instead of the reading
---side: a remote file update would land in whichever window Vim considers
---"current" for that tab -- the Claude terminal, if that's where the
---cursor was last -- silently updating the WRONG window while the actual
---file window sitting right next to it stayed untouched. That's exactly
---why a window would look permanently "stuck" on whatever it opened
---locally: every incoming update from elsewhere was being written into the
---terminal pane instead of the file pane. Falls back to
---nvim_tabpage_get_win() only if the tab has no real file window at all
---(e.g. every window in it is a terminal) -- updating something is better
---than updating nothing in that edge case.
local function find_file_window_in_tabpage(tabpage)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" then
      return win
    end
  end
  return vim.api.nvim_tabpage_get_win(tabpage)
end

---Puts `buf` in `win` and cleans up the buffer it displaced if that buffer
---was a throwaway empty one.
---
---This exists because `:tabnew` (below, and in apply_event) creates a fresh
---empty UNNAMED buffer for the tab it opens, and nvim_win_set_buf then
---swaps the window onto the synced buffer WITHOUT disposing of it -- unlike
---`:edit`, which wipes an empty/unnamed/unmodified current buffer as it
---reuses it. The orphan stays loaded and 'buflisted', so bufferline shows a
---[No Name] entry for every tab this bootstrap created, plus one for the
---mirror's own startup buffer. Confirmed directly: a mirror whose snapshot
---had 4 tabs came up with exactly 3 stray [No Name] buffers, while the host
---(which only ever opens files via :edit) had none -- exactly the reported
---"[No Name] tabs in the mirror, nothing like it on the root session".
---
---Only genuinely disposable buffers are wiped: unnamed, unmodified, empty,
---and not on screen in any other window.
local function display_buf(win, buf)
  local old = vim.api.nvim_win_get_buf(win)
  if not pcall(vim.api.nvim_win_set_buf, win, buf) then
    return
  end
  if old == buf or not vim.api.nvim_buf_is_valid(old) then
    return
  end
  if vim.api.nvim_buf_get_name(old) ~= "" or vim.bo[old].modified then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(old, 0, -1, false)
  if #lines > 1 or (lines[1] or "") ~= "" then
    return
  end
  if #vim.fn.win_findbuf(old) > 0 then
    return -- still visible somewhere else; leave it alone
  end
  pcall(vim.api.nvim_buf_delete, old, { force = false })
end
M.display_buf = display_buf

---Captures every tab's current file (or nil for a blank/special one) into
---a per-port snapshot file. Exposed (not local) because instant.lua calls
---this directly at the exact moment a session starts hosting -- see the
---comment above M.write_snapshot for why that specific timing matters and
---the TabNew/BufReadPost hooks below aren't enough on their own.
function M.write_snapshot(port)
  local snap = {}
  -- Which tab the host is ACTUALLY on, so a mirror can land there instead
  -- of wherever tab creation happens to leave it (the last one). This is
  -- not cosmetic: tab NUMBER is the correspondence key for everything
  -- terminal-related in this feature -- floating_term.lua's tmux session,
  -- shared_terminal.lua's wrap(), claude-code.lua's tmux_tab_session_name()
  -- are all "<something>-root<port>-tab<N>". A mirror sitting on a
  -- different tab number than its host therefore resolves EVERY one of
  -- those to a different session and opens an empty terminal, while the
  -- host's real one (still running, still in `tmux ls`) is nowhere to be
  -- seen -- "I pressed <leader>iss and lost all my terminals and their
  -- groups". Recorded per-entry rather than as a sibling key so the
  -- snapshot stays a plain JSON array (`#snap` is load-bearing below), and
  -- a snapshot written before this existed just has no entry flagged.
  local current = vim.fn.tabpagenr()
  -- The host's cwd travels with the snapshot because the receiver cannot
  -- derive it: instant.nvim encodes a shared buffer's name relative to the
  -- SENDER's cwd, so predicting that name needs the sender's cwd, not the
  -- reader's. See util/instant_bufname.lua.
  local cwd = vim.fn.getcwd()
  for i, t in ipairs(vim.api.nvim_list_tabpages()) do
    table.insert(snap, { file = find_file_in_tabpage(t), cwd = cwd, current = (i == current) or nil })
  end
  local f = io.open(snapshot_path(port), "w")
  if f then
    f:write(vim.fn.json_encode(snap))
    f:close()
  end
end

local function read_snapshot(port)
  local f = io.open(snapshot_path(port), "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.fn.json_decode, content)
  return (ok and type(data) == "table") and data or nil
end

-- NOTE: none of these three re-write the snapshot anymore (an earlier
-- version did). The snapshot is written EXACTLY ONCE, by instant.lua at
-- the moment a session starts hosting, and covers only what predates the
-- event system entirely (tabs open before anyone had a root session, so
-- they never fired these hooks in the first place). Re-writing it on every
-- change was actively harmful: whichever window's write landed LAST won,
-- unconditionally overwriting the file with THAT window's own view --
-- which could easily be less complete than another window's if it hadn't
-- caught up on recent events yet, silently discarding tabs from the
-- on-disk snapshot. Everything that happens AFTER hosting starts belongs
-- to the event log instead, which is append-only and can't lose history
-- that way -- see M.install's bootstrap logic, which replays the FULL log
-- for a freshly-joining window rather than trusting the snapshot to still
-- be current.
local function broadcast_tabnew()
  local port = vim.g.instant_root_port
  if not port or replaying then
    return
  end
  append_event(port, { kind = "new", pid = my_pid })
  bump_last_seen(port)
end

-- BufNewFile/BufReadPost -- NOT BufEnter -- so this fires only when a file
-- is actually being opened for the first time, never on plain navigation
-- to an already-open buffer/tab. See the file-level comment for why that
-- distinction matters.
local function broadcast_file()
  local port = vim.g.instant_root_port
  if not port or replaying then
    return
  end
  if vim.bo.buftype ~= "" then
    return -- skip terminal/dashboard/help/etc.
  end
  local file = vim.fn.expand("%:p")
  if file == "" then
    return
  end
  append_event(port, {
    kind = "file",
    pid = my_pid,
    tab = vim.api.nvim_tabpage_get_number(0),
    file = file,
    -- See M.write_snapshot: the receiver needs OUR cwd, not its own, to
    -- predict what instant.nvim will have named this file on its end.
    cwd = vim.fn.getcwd(),
  })
  bump_last_seen(port)
end

-- TabClosed's <afile> is documented to hold the CLOSED tab's number
-- (already gone from tabpagenr("$") by the time this fires).
local function broadcast_tabclosed(args)
  local port = vim.g.instant_root_port
  if not port or replaying then
    return
  end
  local closed_tab = tonumber(args.file)
  if not closed_tab then
    return
  end
  append_event(port, { kind = "closed", pid = my_pid, tab = closed_tab })
  bump_last_seen(port)
end

-- tab number -> a counter bumped every time something new is queued for
-- that tab. Buffer lookups run concurrently now (see bootstrap_from_snapshot
-- and apply_event), so two of them can be in flight for the same tab at
-- once -- e.g. the snapshot's file for tab 3 and, moments later, a replayed
-- event moving tab 3 to a different file. Without a claim, whichever poll
-- happened to resolve LAST would win, which is the wrong answer whenever
-- that's the older one (the stale file would visibly overwrite the newer
-- one, at random). Each queued lookup takes the current token and only
-- applies its result if it is still the latest claim on that tab.
local tab_claims = {}

local function claim_tab(tab)
  tab_claims[tab] = (tab_claims[tab] or 0) + 1
  return tab_claims[tab]
end

local function tab_claim_current(tab, token)
  return tab_claims[tab] == token
end

-- Poll until the buffer instant.nvim created for `file` shows up, then hand
-- its bufnr to `apply` (or nil if it never did). Polling rather than a fixed
-- delay because a synced buffer arrives whenever the network and the peer's
-- startup get around to it. `sender_cwd` is the cwd of the window that
-- shared the file -- see util/instant_bufname.lua for why identifying the
-- buffer needs it, and why a wrong/missing one now degrades gracefully
-- instead of never matching at all.
local function poll_for_buffer(file, sender_cwd, attempts_left, apply)
  local buf = find_synced_buf(file, sender_cwd)
  if buf then
    apply(buf)
    return
  end
  if attempts_left > 0 then
    vim.defer_fn(function()
      poll_for_buffer(file, sender_cwd, attempts_left - 1, apply)
    end, 200)
  else
    apply(nil)
  end
end

---Runs `fn` (which may itself change the current tab, e.g. :tabnew or
---:tabclose) then restores whichever tab was active before it ran --
---so replaying a remote event never steals YOUR focus, only updates the
---other tab's content in the background.
local function preserving_current_tab(fn)
  local original = vim.fn.tabpagenr()
  fn()
  pcall(vim.cmd, original .. "tabnext")
end

-- Applies a snapshot taken with M.write_snapshot: creates every tab it
-- records, then fills each one's window with the recorded file as that
-- file's content actually arrives (via instant.nvim's own sync, separately
-- and on its own schedule), all WITHOUT changing which tab is currently
-- active beyond landing on the host's. Only covers what predates the event
-- system (see the comment above broadcast_tabnew) -- `on_done` is what lets
-- the caller chain the FULL event-log replay after this, to pick up
-- everything since.
--
-- The tab STRUCTURE is built synchronously, up front, and the per-tab file
-- lookups then run CONCURRENTLY. An earlier version instead walked the
-- snapshot one tab at a time, creating tab i+1 only after tab i's file had
-- been found -- which made a single unresolvable entry stall everything
-- behind it for the full 30s poll timeout. That was the direct cause of the
-- "the second <leader>iss is far slower than the first, and warns that it
-- gave up waiting": the snapshot is written once, when hosting starts, so
-- by the time you spawn a second mirror it can easily name a file the host
-- has since closed -- and instant.nvim only ever shares buffers that are
-- CURRENTLY open, so such an entry can never resolve, no matter how long
-- you wait. Reproduced directly: a host with a 3-tab snapshot that then
-- closed tab 1's file left a joining mirror sitting at 1 tab for a full 30s,
-- 2 tabs at 35s, and still not finished at 95s. Concurrent lookups make one
-- dead entry cost that tab alone -- it just stays blank -- instead of
-- costing every tab after it 30s each. (instant.lua now also re-writes the
-- snapshot on every mirror spawn, so dead entries are rare to begin with.)
local function bootstrap_from_snapshot(port, on_done)
  local snap = read_snapshot(port)
  if not snap or #snap == 0 then
    if on_done then
      on_done()
    end
    return
  end

  -- `replaying` only needs to cover the SYNCHRONOUS :tabnew calls (they
  -- fire TabNew, which broadcast_tabnew hooks -- has to be suppressed to
  -- avoid re-broadcasting our own replay). display_buf below does NOT
  -- trigger BufNewFile/BufReadPost (no disk read happens, it's just
  -- switching which already-loaded buffer a window shows) -- so it doesn't
  -- need guarding, and holding `replaying` across the ASYNC poll waits was
  -- purely harmful: it silently suppressed any of YOUR OWN genuine actions
  -- (opening a file, creating a tab) for as long as that window stayed
  -- open, causing exactly the "sometimes a window doesn't get synced"
  -- flakiness this fixes.
  replaying = true
  while vim.fn.tabpagenr("$") < #snap do
    if not pcall(vim.cmd, "tabnew") then
      break
    end
  end
  replaying = false

  -- Land on the tab the HOST was on (see M.write_snapshot for why tab
  -- numbers have to line up). Without this, whichever tab `tabnew` created
  -- last is where this window stays -- always the highest-numbered one,
  -- which is the host's tab only by coincidence.
  for i, entry in ipairs(snap) do
    if entry.current and vim.fn.tabpagenr("$") >= i then
      pcall(vim.cmd, i .. "tabnext")
      break
    end
  end

  local tabpages = vim.api.nvim_list_tabpages()
  for i, entry in ipairs(snap) do
    if entry.file and tabpages[i] then
      local win = find_file_window_in_tabpage(tabpages[i])
      local token = claim_tab(i)
      poll_for_buffer(entry.file, entry.cwd, 150, function(buf)
        if buf and tab_claim_current(i, token) and vim.api.nvim_win_is_valid(win) then
          display_buf(win, buf)
        end
      end)
    end
  end

  -- The structure is in place and every lookup is in flight; the event-log
  -- replay chained here is free to start now rather than waiting on files
  -- that may never arrive. Its own events are applied on top, and the
  -- per-tab claim tokens make the later one win if both target a tab.
  if on_done then
    on_done()
  end
end

---`on_done` (optional) is what lets a caller that needs events applied
---STRICTLY IN ORDER (replay_range below) wait for each one to actually
---finish -- important there because a "closed" event's tab NUMBER only
---makes sense relative to whichever tabs already exist at that point in
---the sequence; applying two events out of order (e.g. a later "file" for
---tab 3 alongside an unfinished earlier "closed" of tab 2) could target
---the wrong tab entirely. The regular incremental poll (M.install) doesn't
---pass one -- events arriving one at a time, a poll tick apart, don't have
---that ordering risk.
local function apply_event(event, on_done)
  if event.pid == my_pid then
    if on_done then
      on_done()
    end
    return
  end
  if event.kind == "new" then
    preserving_current_tab(function()
      replaying = true
      pcall(vim.cmd, "tabnew")
      replaying = false
    end)
    if on_done then
      on_done()
    end
  elseif event.kind == "file" then
    -- Don't have that many tabs yet -- its "new" event should have arrived
    -- first (same shared log, processed in order); if it was somehow
    -- missed, just drop this rather than guess where to put it.
    if vim.fn.tabpagenr("$") < event.tab then
      if on_done then
        on_done()
      end
      return
    end
    local tabpages = vim.api.nvim_list_tabpages()
    local win = find_file_window_in_tabpage(tabpages[event.tab])
    -- No `replaying` guard needed here -- display_buf doesn't trigger
    -- BufNewFile/BufReadPost (see bootstrap_from_snapshot's comment above
    -- for why holding it across this async wait was actively harmful).
    --
    -- on_done fires IMMEDIATELY, not when the buffer turns up. Only the tab
    -- STRUCTURE (new/closed) has to be applied in strict order -- that's
    -- what tab numbers are relative to -- and this event doesn't touch it.
    -- Waiting here instead put a 30s timeout in front of every remaining
    -- event in the queue whenever one file couldn't be resolved (a file the
    -- sharer has since closed can never resolve at all), which is what made
    -- catching up on a long-running session crawl. The claim token keeps
    -- the concurrent lookups from overwriting each other out of order.
    local token = claim_tab(event.tab)
    poll_for_buffer(event.file, event.cwd, 150, function(buf)
      if buf and tab_claim_current(event.tab, token) and vim.api.nvim_win_is_valid(win) then
        display_buf(win, buf)
      end
    end)
    if on_done then
      on_done()
    end
  elseif event.kind == "closed" then
    -- Out of range (already closed some other way, or never had that many
    -- tabs) or the only tab left (Neovim refuses to close the last one) --
    -- either way, pcall absorbs it rather than erroring.
    preserving_current_tab(function()
      replaying = true
      pcall(vim.cmd, event.tab .. "tabclose")
      replaying = false
    end)
    if on_done then
      on_done()
    end
  elseif on_done then
    on_done()
  end
end

---Replays event-log lines `from`..`to` (inclusive), IN ORDER, waiting for
---each to finish before starting the next -- see apply_event's `on_done`
---comment for why order matters here specifically. Used both for a fresh
---window's full-history catchup and, functionally the same thing, the
---regular incremental poll in M.install (which just always happens to
---have a range of length <= a few, one poll tick apart).
local function replay_range(lines, from, to, on_done)
  local function step(i)
    if i > to then
      if on_done then
        on_done()
      end
      return
    end
    local ok, event = pcall(vim.fn.json_decode, lines[i])
    if ok then
      apply_event(event, function()
        step(i + 1)
      end)
    else
      step(i + 1)
    end
  end
  step(from)
end

-- Module-level, NOT local to M.install(): a vim.loop/vim.uv timer handle
-- with nothing keeping a reference to it after the function that created
-- it returns is eligible for Lua's garbage collector to reclaim, which
-- silently stops it firing -- non-deterministically, so it can look like it
-- works in a quick test and then mysteriously stop in real, longer-lived
-- usage. Keeping the handle here for the module's whole lifetime prevents
-- that.
local poll_timer

function M.install()
  if installed then
    return
  end
  installed = true

  vim.api.nvim_create_autocmd("TabNew", { callback = broadcast_tabnew })
  vim.api.nvim_create_autocmd({ "BufNewFile", "BufReadPost" }, { callback = broadcast_file })
  vim.api.nvim_create_autocmd("TabClosed", { callback = broadcast_tabclosed })

  -- port -> true while EITHER the initial bootstrap+full-log-replay OR an
  -- ordinary incremental catchup is still running for it (both are async
  -- now, via replay_range). Without this, a still-in-flight replay's
  -- last_seen[port] wouldn't be updated yet when the NEXT 400ms tick
  -- fires, so that tick would see the same stale last_seen and start a
  -- SECOND, overlapping replay of an overlapping (or, for the bootstrap
  -- case, entirely duplicate) range -- so this just makes "already
  -- replaying this port" a reason to skip a tick, the same way an
  -- ordinary mutex would.
  local processing = {}

  poll_timer = vim.loop.new_timer()
  poll_timer:start(
    400,
    400,
    vim.schedule_wrap(function()
      local port = vim.g.instant_root_port
      if not port or processing[port] then
        return
      end
      local lines = read_lines(port)
      if last_seen[port] == nil then
        -- Freshly seeing this port: apply the snapshot (the host's tab
        -- layout at the moment it started hosting -- covers only what
        -- predates the event system, see M.write_snapshot), THEN replay
        -- the log from its very START (not from "now") -- otherwise
        -- anything that happened between the original snapshot and THIS
        -- window joining (e.g. some other window opening a new tab in the
        -- meantime) would be silently skipped forever: this window's
        -- catchup baseline would already be past it before ever seeing it.
        -- That gap was a real, confirmed bug -- one window ending up
        -- permanently missing a tab every other window has.
        processing[port] = true
        local target = #lines
        bootstrap_from_snapshot(port, function()
          replay_range(lines, 1, target, function()
            last_seen[port] = target
            processing[port] = nil
          end)
        end)
        return
      end
      if #lines <= last_seen[port] then
        return
      end
      processing[port] = true
      replay_range(lines, last_seen[port] + 1, #lines, function()
        last_seen[port] = #lines
        processing[port] = nil
      end)
    end)
  )
end

return M
