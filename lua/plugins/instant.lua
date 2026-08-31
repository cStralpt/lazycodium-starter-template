-- A hardcoded port would make every hosted session collide with any other
-- one still running (EADDRINUSE), and a failed StartServer call tears down
-- whatever session that window already had. So each host picks a random,
-- likely-free port automatically.
--
-- Every session a host starts on this machine gets recorded here (port,
-- file, when) so <leader>isp can show a picker of ALL known sessions to
-- join, not just the most recent one -- a single "last session" file isn't
-- enough once more than one is running at a time. A host removes its own
-- entry on <leader>isS; entries aren't otherwise verified live (no active
-- probe), so a session whose host crashed/quit without stopping cleanly may
-- linger until picked and found unreachable.
local function registry_path()
  return vim.fn.stdpath("cache") .. "/instant-sessions.json"
end

local function load_registry()
  local f = io.open(registry_path(), "r")
  if not f then
    return {}
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.fn.json_decode, content)
  return (ok and type(data) == "table") and data or {}
end

local function save_registry(list)
  local f = io.open(registry_path(), "w")
  if f then
    f:write(vim.fn.json_encode(list))
    f:close()
  end
end

---Records/refreshes a session. De-duped by port -- re-hosting on the same
---port (shouldn't normally happen given random ports, but just in case)
---replaces rather than duplicates the entry.
local function add_session(port, file)
  local list = load_registry()
  local filtered = {}
  for _, entry in ipairs(list) do
    if entry.port ~= port then
      table.insert(filtered, entry)
    end
  end
  table.insert(filtered, { port = port, file = file, time = os.time() })
  save_registry(filtered)
end

local function remove_session(port)
  local list = load_registry()
  local filtered = {}
  for _, entry in ipairs(list) do
    if entry.port ~= port then
      table.insert(filtered, entry)
    end
  end
  save_registry(filtered)
end

-- 64900-64999: outside the kernel's ephemeral/auto-assigned range
-- (32768-60999 on this machine, per /proc/sys/net/ipv4/ip_local_port_range),
-- so nothing else on this laptop grabs these ports on its own.
local function random_port()
  math.randomseed(vim.loop.hrtime())
  return math.random(64900, 64999)
end

-- How the plugin actually shares buffers (from reading its source, not the
-- docs -- the docs don't cover this):
--   - HOST: whatever normal file buffers you already have open when a
--     client connects get sent over automatically. Nothing extra needed.
--   - JOINER: on connect, the plugin silently creates its OWN scratch
--     buffer per shared file and fills it from the network, then names it
--     via nvim_buf_set_name using the SAME cwd-relative-path-or-basename
--     logic on both ends (see below) -- but never displays it in any
--     window, and takes an unpredictable amount of time to actually arrive
--     depending on file size and network scheduling. That's why this polls
--     for the exact expected name instead of guessing off a fixed delay.
--   - `:InstantOpenAll` is UNRELATED to any of this: it globs every file in
--     the cwd off disk and runs `:args` on them. Calling it after joining
--     (an earlier version of this file did) doesn't surface the synced
--     buffer -- it dumps the window into whatever random file happened to
--     glob-match (the LazyVim dashboard, in practice), which is exactly
--     what broke navigation before.

-- instant.lua broadcasts a buffer under a cwd-relative name (or bare
-- basename), then the RECEIVING side calls nvim_buf_set_name() with that
-- string -- but nvim_buf_set_name silently normalizes relative names to an
-- ABSOLUTE path resolved against ITS OWN cwd (confirmed directly: setting a
-- scratch buffer's name to "lazy-lock.json" from cwd /tmp reads back as
-- "/tmp/lazy-lock.json", never the relative string). So the stored buffer
-- name is never the relative string an earlier version of this file
-- compared against -- that's why matching always failed. Since the mirror
-- inherits the host's cwd (jobstart's default), that normalization round-
-- trips right back to the host's own absolute path -- so just compare
-- against the absolute path directly instead of re-deriving a relative one.
local function expected_bufname(file)
  return file ~= "" and file or nil
end

local function lua_quote(s)
  return "'" .. s:gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
end

-- Opens a new foot window that auto-joins the just-started session on
-- `port`, and -- if the host had a real file open -- polls for that exact
-- file's synced buffer and switches the window to it once it arrives.
-- Manual joining from any OTHER window via <leader>isj still works fine
-- (e.g. a window on another machine, or one that missed the auto-spawned
-- mirror) -- this is just the convenience path for mirroring your own host.
--
-- If the host has nothing open (dashboard, [No Name], etc.) there is
-- nothing to target: the mirror just opens normally (dashboard too), same
-- as any fresh nvim. Once you open a file on the host, its content starts
-- being shared from that point on (the plugin also hooks BufRead), but the
-- already-open mirror window won't auto-switch to it -- press <leader>iss
-- again to get a mirror aimed at the file you're now on.
local function spawn_mirror_window(port, target_name)
  local script = string.format(
    [[
-- instant.nvim is lazy-loaded on <leader>iss/isj/isS, so a fresh nvim has
-- none of its :Instant* commands defined yet until something triggers that
-- load -- calling them directly errors with "E492: Not an editor command".
require('lazy').load({ plugins = { 'instant.nvim' } })
local target_name = %s
vim.defer_fn(function()
  local ok, err = pcall(vim.cmd, 'InstantJoinSession 127.0.0.1 %d')
  if not ok then
    vim.notify('instant.nvim: JoinSession failed: ' .. tostring(err), vim.log.levels.ERROR)
    return
  end
  -- Mark THIS window as already part of the ROOT session (never a value
  -- this window invents itself -- always the exact port it was told to
  -- join), so if <leader>iss gets pressed again in here, it adds another
  -- mirror to the SAME root session instead of forking off an independent
  -- one (see host_session's "already part of a session" check).
  vim.g.instant_root_port = %d
  vim.notify('instant.nvim: joined root session on port ' .. vim.g.instant_root_port, vim.log.levels.INFO)
  if not target_name then
    return
  end
  local attempts = 0
  local function try_focus()
    attempts = attempts + 1
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) == target_name then
        vim.api.nvim_win_set_buf(0, b)
        vim.notify('instant.nvim: focused ' .. target_name, vim.log.levels.INFO)
        return
      end
    end
    -- 150 attempts * 200ms = 30s -- the mirror window's own LazyVim startup
    -- (dashboard, ~30 plugins, possibly first-run treesitter/mason installs)
    -- can easily eat several seconds before the join+sync even gets a
    -- chance to run, so a short timeout gives up right before the buffer
    -- would have appeared.
    if attempts < 150 then
      vim.defer_fn(try_focus, 200)
    else
      -- Dump what buffers DID show up, so the mismatch (wrong name? never
      -- created at all?) is visible instead of a bare timeout.
      local seen = {}
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) then
          table.insert(seen, "[" .. vim.api.nvim_buf_get_name(b) .. "]")
        end
      end
      vim.notify(
        "instant.nvim: gave up waiting for '"
          .. target_name
          .. "'. Buffers present: "
          .. table.concat(seen, " "),
        vim.log.levels.WARN
      )
    end
  end
  vim.defer_fn(try_focus, 300)
end, 300)
]],
    target_name and lua_quote(target_name) or "nil",
    port,
    port
  )
  local script_path = vim.fn.stdpath("cache") .. "/instant-join-" .. port .. ".lua"
  local f = io.open(script_path, "w")
  f:write(script)
  f:close()
  vim.fn.jobstart({ "foot", "nvim", "-c", "luafile " .. script_path }, { detach = true })
end

-- Whether THIS nvim process is currently running a server -- tracked
-- ourselves rather than trusting instant.nvim's own state, because
-- InstantStopServer does its real work inside vim.schedule(): calling it
-- when no server exists throws asynchronously, outside any pcall wrapped
-- around the vim.cmd() call. Worse, ws_server is a single module-level
-- variable (not per-session), so calling StopServer at the wrong moment can
-- silently kill a server you just started a moment earlier -- exactly what
-- happened when host_session() used to call it unconditionally as a
-- "safety" guard on every press.
local is_hosting = false

-- Retries a few times in the rare case the random port is already taken.
local function host_session()
  local file = vim.fn.expand("%:p")
  local target_name = expected_bufname(file)

  -- If THIS window is already part of a session -- as the original host, or
  -- as a mirror that was itself joined earlier -- don't start a competing
  -- server. Earlier versions did, which chained sessions together instead
  -- of sharing one: press <leader>iss in a mirror, and that mirror would
  -- spin up its OWN independent server and spawn a NEW mirror joined to
  -- ITSELF, not to the original session. Instead, just add one more mirror
  -- to whatever session this window is already in.
  if vim.g.instant_root_port then
    print("Root session is on port " .. vim.g.instant_root_port .. " -- opening another mirror of it")
    spawn_mirror_window(vim.g.instant_root_port, target_name)
    return
  end

  -- Re-pressing <leader>iss in a window that's already hosting/connected
  -- otherwise crashes with "E5108: Client is already connected" (instant.lua
  -- refuses to start a second client without an explicit stop first).
  -- InstantStop (disconnecting the CLIENT side) is genuinely synchronous and
  -- pcall-safe, unlike InstantStopServer -- so only that is called here.
  pcall(vim.cmd, "InstantStop")

  for _ = 1, 5 do
    local port = random_port()
    local ok = pcall(vim.cmd, "InstantStartServer 127.0.0.1 " .. port)
    if ok then
      is_hosting = true
      vim.g.instant_root_port = port
      vim.cmd("InstantStartSession 127.0.0.1 " .. port)
      add_session(port, file)

      -- Keep the registry entry's file live-updated as the host switches
      -- files, so the picker never shows what you had open when you first
      -- pressed <leader>iss instead of what's actually open now. Guarded on
      -- is_hosting (not port) so it self-disables after <leader>isS stops
      -- this host -- otherwise it'd silently resurrect the just-removed
      -- registry entry the next time you switch buffers in this window.
      vim.api.nvim_create_augroup("InstantHostFileTracking", { clear = true })
      vim.api.nvim_create_autocmd("BufEnter", {
        group = "InstantHostFileTracking",
        callback = function()
          if not is_hosting then
            return
          end
          if vim.bo.buftype ~= "" then
            return -- skip terminal/dashboard/help/etc.
          end
          local current_file = vim.fn.expand("%:p")
          if current_file ~= "" then
            add_session(port, current_file)
          end
        end,
      })

      if target_name then
        print("Root session: hosting " .. target_name .. " on port " .. port .. " -- opening mirror window")
      else
        print(
          "Root session started on port "
            .. port
            .. " -- no file open here, so the mirror window opens blank too."
            .. " Open a file, then press <leader>iss again to mirror it."
        )
      end
      spawn_mirror_window(port, target_name)
      return
    end
  end
  print("Could not find a free port after 5 attempts")
end

-- Same polling idea as spawn_mirror_window's generated script, but running
-- in-process (no jobstart/script file needed) since this join happens in
-- the current nvim, not a spawned one.
local function poll_and_focus(target_name, attempts_left)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) == target_name then
      vim.api.nvim_win_set_buf(0, b)
      return
    end
  end
  if attempts_left > 0 then
    vim.defer_fn(function()
      poll_and_focus(target_name, attempts_left - 1)
    end, 200)
  else
    local seen = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) then
        table.insert(seen, "[" .. vim.api.nvim_buf_get_name(b) .. "]")
      end
    end
    vim.notify(
      "instant.nvim: gave up waiting for '" .. target_name .. "'. Buffers present: " .. table.concat(seen, " "),
      vim.log.levels.WARN
    )
  end
end

---Shared by manual join (<leader>isj) and the session picker (<leader>isp)
----- also what makes SWITCHING sessions a single action: if this window is
---already in one, InstantStop leaves it first, then joins the new port, so
---picking a different session from the list just works without a separate
---explicit "leave" step.
---@param fallback_file string? what to target if THIS window has no file of
---its own open -- the picker passes the registry's record of what the host
---was on when it started that session, so joining from a bare dashboard
---still lands you on a real file instead of just leaving it on dashboard
---with the session connected but nothing displayed.
local function do_join(port, fallback_file)
  pcall(vim.cmd, "InstantStop")
  local file = vim.fn.expand("%:p")
  if file == "" and fallback_file and fallback_file ~= "" then
    file = fallback_file
  end
  local target_name = expected_bufname(file)
  vim.cmd("InstantJoinSession 127.0.0.1 " .. port)
  vim.g.instant_root_port = tonumber(port)
  if target_name then
    vim.defer_fn(function()
      poll_and_focus(target_name, 150)
    end, 300)
  end
end

local function join_session()
  local list = load_registry()
  local last = list[#list]
  local default_port = last and tostring(last.port) or ""
  local port = vim.fn.input("Join port: ", default_port)
  if port == "" then
    print("No port given, join cancelled")
    return
  end
  do_join(port)
end

local function stop_session()
  local port = vim.g.instant_root_port
  pcall(vim.cmd, "InstantStop")
  if is_hosting then
    vim.cmd("InstantStopServer")
    is_hosting = false
    if port then
      remove_session(port)
    end
  end
  vim.g.instant_root_port = nil
end

---Picker of every known session on this machine (hosted here, ever, and
---not yet explicitly stopped) -- select one to switch to it directly,
---instead of remembering/typing/pasting a port. See do_join for why
---switching is a single action even when already in a different session.
local function pick_session()
  local list = load_registry()
  if #list == 0 then
    vim.notify("instant.nvim: no known sessions -- host one with <leader>iss first", vim.log.levels.WARN)
    return
  end
  -- Most recently started first.
  table.sort(list, function(a, b)
    return (a.time or 0) > (b.time or 0)
  end)

  local items = {}
  for _, entry in ipairs(list) do
    local age = os.time() - (entry.time or os.time())
    local age_str = age < 60 and (age .. "s ago") or ((math.floor(age / 60)) .. "m ago")
    local current = (vim.g.instant_root_port == entry.port) and " (current)" or ""
    local label = string.format(
      "port %d -- %s -- %s%s",
      entry.port,
      entry.file and entry.file ~= "" and vim.fn.fnamemodify(entry.file, ":t") or "no file",
      age_str,
      current
    )
    table.insert(items, { label = label, port = entry.port, file = entry.file })
  end

  vim.ui.select(items, {
    prompt = "Join instant.nvim session:",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      do_join(choice.port, choice.file)
    end
  end)
end

return {
  "jbyuki/instant.nvim",
  init = function()
    vim.g.instant_username = vim.env.USER or "user"
    -- The collaboration layer's own magic: makes any terminal spawned
    -- anywhere (Claude, a shell, whatever) transparently mirror across
    -- collaborative windows once a root session exists. No other plugin
    -- opts into this or knows it's happening -- see util/shared_terminal.lua.
    -- `init` runs at startup for every window, lazy-loaded plugin or not,
    -- so this is active well before any <leader>iss press.
    require("util.shared_terminal").install()
  end,
  keys = {
    { "<leader>iss", host_session, desc = "Instant: host session + open mirror window" },
    { "<leader>isj", join_session, desc = "Instant: join session (manual port)" },
    { "<leader>isS", stop_session, desc = "Instant: stop/leave" },
    { "<leader>isp", pick_session, desc = "Instant: pick a session to join/switch to" },
  },
}
