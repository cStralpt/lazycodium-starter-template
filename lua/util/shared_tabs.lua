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
local expected_bufname = require("util.instant_bufname").expected_bufname

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

---Captures every tab's current file (or nil for a blank/special one) into
---a per-port snapshot file. Exposed (not local) because instant.lua calls
---this directly at the exact moment a session starts hosting -- see the
---comment above M.write_snapshot for why that specific timing matters and
---the TabNew/BufReadPost hooks below aren't enough on their own.
function M.write_snapshot(port)
  local snap = {}
  for _, t in ipairs(vim.api.nvim_list_tabpages()) do
    table.insert(snap, { file = find_file_in_tabpage(t) })
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
  append_event(port, { kind = "file", pid = my_pid, tab = vim.api.nvim_tabpage_get_number(0), file = file })
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

-- Poll for a buffer with EXACTLY `file` as its name (the absolute-path
-- convention instant.lua's own synced buffers use -- see that file's notes
-- on nvim_buf_set_name normalizing relative names to absolute ones), then
-- hand its bufnr to `apply` once found (or nil if it never showed up). A
-- light, self-contained duplicate of the same search in
-- lua/plugins/instant.lua, kept local rather than shared to avoid coupling
-- this file to instant.lua's internals.
local function poll_for_buffer(file, attempts_left, apply)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) == file then
      apply(b)
      return
    end
  end
  if attempts_left > 0 then
    vim.defer_fn(function()
      poll_for_buffer(file, attempts_left - 1, apply)
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

-- Applies a snapshot taken with M.write_snapshot: creates each tab (if
-- needed) and fills its window with the recorded file, one tab at a time
-- (waiting for each file's content to actually be synced -- via
-- instant.nvim's own mechanism, separately -- before moving to the next),
-- all WITHOUT changing which tab is currently active, other than landing
-- wherever bootstrap naturally leaves off since this runs once at join
-- time before you've navigated anywhere yourself. Only covers what
-- predates the event system (see the comment above broadcast_tabnew) --
-- `on_done` is what lets the caller chain the FULL event-log replay after
-- this finishes, to pick up everything since.
local function bootstrap_from_snapshot(port, on_done)
  local snap = read_snapshot(port)
  if not snap or #snap == 0 then
    if on_done then
      on_done()
    end
    return
  end
  local function do_tab(i)
    if i > #snap then
      if on_done then
        on_done()
      end
      return
    end
    -- `replaying` only needs to cover the SYNCHRONOUS :tabnew call (it
    -- fires TabNew, which broadcast_tabnew hooks -- has to be suppressed
    -- to avoid re-broadcasting our own replay). nvim_win_set_buf below
    -- does NOT trigger BufNewFile/BufReadPost (no disk read happens, it's
    -- just switching which already-loaded buffer a window shows) -- so it
    -- doesn't need guarding, and holding `replaying` across the ASYNC
    -- poll_for_buffer wait (up to 30s per tab, compounding across however
    -- many tabs are in the snapshot) was purely harmful: it silently
    -- suppressed any of YOUR OWN genuine actions (opening a file,
    -- creating a tab) for as long as that window stayed open, causing
    -- exactly the "sometimes a window doesn't get synced" flakiness this
    -- fixes.
    if vim.fn.tabpagenr("$") < i then
      replaying = true
      pcall(vim.cmd, "tabnew")
      replaying = false
    end
    local tabpages = vim.api.nvim_list_tabpages()
    local win = find_file_window_in_tabpage(tabpages[i])
    local file = snap[i].file
    if not file then
      do_tab(i + 1)
      return
    end
    poll_for_buffer(expected_bufname(file), 150, function(buf)
      if buf then
        pcall(vim.api.nvim_win_set_buf, win, buf)
      end
      do_tab(i + 1)
    end)
  end
  do_tab(1)
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
    -- No `replaying` guard needed here -- nvim_win_set_buf doesn't trigger
    -- BufNewFile/BufReadPost (see bootstrap_from_snapshot's comment above
    -- for why holding it across this async wait was actively harmful).
    poll_for_buffer(expected_bufname(event.file), 150, function(buf)
      if buf then
        pcall(vim.api.nvim_win_set_buf, win, buf)
      end
      if on_done then
        on_done()
      end
    end)
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
