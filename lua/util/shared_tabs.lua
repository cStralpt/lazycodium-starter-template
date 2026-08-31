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

---Captures every tab's current file (or nil for a blank/special one) into
---a per-port snapshot file. Exposed (not local) because instant.lua calls
---this directly at the exact moment a session starts hosting -- see the
---comment above M.write_snapshot for why that specific timing matters and
---the TabNew/BufReadPost hooks below aren't enough on their own.
function M.write_snapshot(port)
  local snap = {}
  for _, t in ipairs(vim.api.nvim_list_tabpages()) do
    local win = vim.api.nvim_tabpage_get_win(t)
    local buf = vim.api.nvim_win_get_buf(win)
    local file = nil
    if vim.bo[buf].buftype == "" then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" then
        file = name
      end
    end
    table.insert(snap, { file = file })
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

local function broadcast_tabnew()
  local port = vim.g.instant_root_port
  if not port or replaying then
    return
  end
  append_event(port, { kind = "new", pid = my_pid })
  bump_last_seen(port)
  M.write_snapshot(port)
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
  M.write_snapshot(port)
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
  M.write_snapshot(port)
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
-- time before you've navigated anywhere yourself.
local function bootstrap_from_snapshot(port)
  local snap = read_snapshot(port)
  if not snap or #snap == 0 then
    return
  end
  local function do_tab(i)
    if i > #snap then
      return
    end
    replaying = true
    if vim.fn.tabpagenr("$") < i then
      pcall(vim.cmd, "tabnew")
    end
    local tabpages = vim.api.nvim_list_tabpages()
    local win = vim.api.nvim_tabpage_get_win(tabpages[i])
    local file = snap[i].file
    if not file then
      replaying = false
      do_tab(i + 1)
      return
    end
    poll_for_buffer(expected_bufname(file), 150, function(buf)
      if buf then
        pcall(vim.api.nvim_win_set_buf, win, buf)
      end
      replaying = false
      do_tab(i + 1)
    end)
  end
  do_tab(1)
end

local function apply_event(event)
  if event.pid == my_pid then
    return
  end
  if event.kind == "new" then
    preserving_current_tab(function()
      replaying = true
      pcall(vim.cmd, "tabnew")
      replaying = false
    end)
  elseif event.kind == "file" then
    -- Don't have that many tabs yet -- its "new" event should have arrived
    -- first (same shared log, processed in order); if it was somehow
    -- missed, just drop this rather than guess where to put it.
    if vim.fn.tabpagenr("$") < event.tab then
      return
    end
    local tabpages = vim.api.nvim_list_tabpages()
    local win = vim.api.nvim_tabpage_get_win(tabpages[event.tab])
    replaying = true
    poll_for_buffer(expected_bufname(event.file), 150, function(buf)
      if buf then
        pcall(vim.api.nvim_win_set_buf, win, buf)
      end
      replaying = false
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
  end
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

  poll_timer = vim.loop.new_timer()
  poll_timer:start(
    400,
    400,
    vim.schedule_wrap(function()
      local port = vim.g.instant_root_port
      if not port then
        return
      end
      local lines = read_lines(port)
      if last_seen[port] == nil then
        -- Freshly seeing this port: bootstrap from whatever snapshot
        -- exists (the host's full tab layout at the moment it started
        -- hosting -- see M.write_snapshot) BEFORE switching to incremental
        -- event tracking, so pre-existing tabs the event log never saw
        -- (created before anyone had a root session at all) still show up.
        last_seen[port] = #lines
        bootstrap_from_snapshot(port)
        return
      end
      if #lines <= last_seen[port] then
        return
      end
      for i = last_seen[port] + 1, #lines do
        local ok, event = pcall(vim.fn.json_decode, lines[i])
        if ok then
          apply_event(event)
        end
      end
      last_seen[port] = #lines
    end)
  )
end

return M
