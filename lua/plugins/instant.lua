-- A hardcoded port would make every hosted session collide with any other
-- one still running (EADDRINUSE), and a failed StartServer call tears down
-- whatever session that window already had. So each host picks a random,
-- likely-free port automatically; join still lets you type any port
-- manually (prefilled with the last known one for convenience).
local function state_path()
  return vim.fn.stdpath("cache") .. "/instant-last-session.json"
end

local function save_state(port, file)
  local f = io.open(state_path(), "w")
  if f then
    f:write(vim.fn.json_encode({ port = port, file = file }))
    f:close()
  end
end

local function load_state()
  local f = io.open(state_path(), "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.fn.json_decode, content)
  return ok and data or nil
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
      save_state(port, file)
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

local function join_session()
  pcall(vim.cmd, "InstantStop")

  local state = load_state()
  local default_port = state and tostring(state.port) or ""
  local port = vim.fn.input("Join port: ", default_port)
  if port == "" then
    print("No port given, join cancelled")
    return
  end
  -- Target whatever file YOU already have open, same as the host: if
  -- nothing is open, there's nothing to auto-focus, so just join and leave
  -- the window as-is.
  local target_name = expected_bufname(vim.fn.expand("%:p"))
  vim.cmd("InstantJoinSession 127.0.0.1 " .. port)
  vim.g.instant_root_port = tonumber(port)
  if target_name then
    vim.defer_fn(function()
      poll_and_focus(target_name, 150)
    end, 300)
  end
end

local function stop_session()
  pcall(vim.cmd, "InstantStop")
  if is_hosting then
    vim.cmd("InstantStopServer")
    is_hosting = false
  end
  vim.g.instant_root_port = nil
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
  },
}
