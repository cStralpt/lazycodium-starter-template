-- A hardcoded port would make every hosted session collide with any other
-- one still running (EADDRINUSE), and a failed StartServer call tears down
-- whatever session that window already had. So each host picks a random,
-- likely-free port automatically.
--
-- Every session a host starts on this machine gets recorded here (port,
-- file, cwd, when) so <leader>isp can show a picker of ALL known sessions to
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
  -- The host's cwd is recorded alongside the file because a joiner cannot
  -- infer it, and needs it to predict what instant.nvim will have named
  -- the synced buffer on its own end -- see util/instant_bufname.lua.
  table.insert(filtered, { port = port, file = file, cwd = vim.fn.getcwd(), time = os.time() })
  save_registry(filtered)
end

---The cwd the host of `port` recorded for itself, if this machine knows
---about that session at all.
local function session_cwd(port)
  for _, entry in ipairs(load_registry()) do
    if tostring(entry.port) == tostring(port) then
      return entry.cwd
    end
  end
  return nil
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

---What file <leader>iss/isj should target, WITHOUT assuming the current
---buffer represents it. It doesn't, reliably: this whole feature's normal
---layout is a file window split next to a Claude terminal, and if your
---cursor happens to be in the terminal pane (likely -- that's where you
---type) when you press the key, vim.fn.expand("%:p") returns the
---terminal's name, not the file's -- a confirmed, real bug (a mirror
---spawned while focused in the terminal had nothing to target and landed
---on a blank dashboard, despite a real file sitting right next to it).
---Falls back to searching every window in the CURRENT tab for a real file
---if the current buffer itself isn't one.
local function current_tab_file()
  local file = vim.fn.expand("%:p")
  if file ~= "" and vim.bo.buftype == "" then
    return file
  end
  return require("util.shared_tabs").find_file_in_tabpage(vim.api.nvim_get_current_tabpage()) or ""
end

-- 61000-65535: outside the kernel's ephemeral/auto-assigned range
-- (32768-60999 on this machine, per /proc/sys/net/ipv4/ip_local_port_range),
-- so nothing else on this laptop grabs these ports on its own.
--
-- This used to be a 100-value range (64900-64999) -- deliberately widened
-- to ~4500 values after finding that was a real, significant bug: every
-- file this feature writes (shared_tabs.lua's event log, its tab snapshot,
-- shared_terminal.lua's tmux session name) is named BY PORT NUMBER. With
-- only 100 possible values, the birthday paradox makes a collision with an
-- earlier, already-abandoned session's port likely fast -- ~85% after just
-- 20 uses of <leader>iss in one real session, easily reached. A collision
-- doesn't just risk EADDRINUSE (already retried below); it means a NEW
-- session inherits an OLD, unrelated session's stale event log and
-- snapshot, silently replaying/bootstrapping garbage from it -- explaining
-- exactly "works, then randomly doesn't, then works again": it only broke
-- on draws that happened to collide with old state. See also
-- host_session()'s explicit stale-file cleanup below, which removes this
-- risk entirely rather than just making it rarer.
local function random_port()
  math.randomseed(vim.loop.hrtime())
  return math.random(61000, 65535)
end

---Actually checks whether `port` is free instead of picking a random
---number and only finding out it's taken when InstantStartServer itself
---fails. bind() alone doesn't reliably detect this -- confirmed directly:
---two separate sockets can both bind() the same port successfully (looks
---like SO_REUSEADDR), the conflict only surfaces at listen() -- so this
---tests through to listen(), matching what InstantStartServer itself
---actually does. Doesn't fully eliminate the race (something else could
---grab the port in the gap between this check and the real
---InstantStartServer call moments later) -- the EADDRINUSE-triggered retry
---loop below still exists as the actual guarantee -- but avoids picking an
---already-listened-on port in the first place rather than only discovering
---it after the fact.
local function port_available(port)
  local sock = vim.loop.new_tcp()
  sock:bind("127.0.0.1", port)
  local ok = sock:listen(1, function() end)
  sock:close()
  return ok == 0
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

-- Identifying a synced buffer is NOT just "look for its absolute path":
-- instant.nvim renames it using a cwd-relative-or-basename encoding that
-- only round-trips to the original path when the file happens to sit inside
-- the sender's cwd, which real usage constantly violates. See
-- lua/util/instant_bufname.lua, which owns that logic (and its fallback for
-- when the two ends' cwds don't match at all).
local find_synced_buf = require("util.instant_bufname").find_synced_buf

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
local function spawn_mirror_window(port, file, cwd)
  local script = string.format(
    [[
-- instant.nvim is lazy-loaded on <leader>iss/isj/isS, so a fresh nvim has
-- none of its :Instant* commands defined yet until something triggers that
-- load -- calling them directly errors with "E492: Not an editor command".
require('lazy').load({ plugins = { 'instant.nvim' } })
-- The FILE, not a name computed here: identifying the synced buffer is the
-- receiver's job (util/instant_bufname.lua), because only the receiver
-- knows its own cwd -- which is what instant.nvim resolves the name it
-- sends against. The host's cwd travels along as the sender's half of that
-- encoding.
local file = %s
local sender_cwd = %s
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
  if not file then
    return
  end
  local find_synced_buf = require('util.instant_bufname').find_synced_buf
  local attempts = 0
  local function try_focus()
    attempts = attempts + 1
    local buf = find_synced_buf(file, sender_cwd)
    if buf then
      -- display_buf, not nvim_win_set_buf: the latter leaves this window's
      -- previous (empty, unnamed, startup) buffer loaded and listed, which
      -- is one of the stray [No Name] entries the mirror used to show.
      require('util.shared_tabs').display_buf(0, buf)
      vim.notify('instant.nvim: focused ' .. vim.api.nvim_buf_get_name(buf), vim.log.levels.INFO)
      return
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
          .. file
          .. "'. Buffers present: "
          .. table.concat(seen, " "),
        vim.log.levels.WARN
      )
    end
  end
  vim.defer_fn(try_focus, 300)
end, 300)
]],
    file and file ~= "" and lua_quote(file) or "nil",
    cwd and cwd ~= "" and lua_quote(cwd) or "nil",
    port,
    port
  )
  local script_path = vim.fn.stdpath("cache") .. "/instant-join-" .. port .. ".lua"
  local f = io.open(script_path, "w")
  f:write(script)
  f:close()

  -- jobstart's `cwd` option (and its documented default, "the current
  -- directory") does NOT reliably reach nvim here -- confirmed directly:
  -- after `:cd /tmp/myproject` on the host, the spawned mirror's getcwd()
  -- came back as $HOME, not /tmp/myproject. foot (or something in its
  -- child-shell startup) resets the working directory rather than
  -- inheriting what it was launched with. foot's own `-D`/
  -- --working-directory flag sidesteps that inheritance chain entirely by
  -- setting it explicitly, which is why both that AND jobstart's `cwd` are
  -- set below -- belt and suspenders, but only -D is actually load-bearing.
  local cwd = vim.fn.getcwd(0)
  local nvim_args = { "nvim", "-c", "luafile " .. script_path }

  -- Terminals to open the mirror in, most preferred first; the first one
  -- actually installed wins. foot is the normal path -- everything below it
  -- exists so <leader>iss still works on a machine without foot, rather than
  -- failing with a bare "foot: executable not found" job error.
  --
  -- Every entry sets a working directory explicitly wherever the terminal
  -- has a flag for it, because each spells that flag (and its "now run this
  -- command" separator) differently. That directory is load-bearing, not
  -- cosmetic: the generated join script never :cd's, so the mirror resolves
  -- the synced buffer name against whatever cwd it happens to start in (see
  -- util/instant_bufname.lua). A mirror that lands in $HOME instead of the
  -- project silently fails to find the file and times out after 30s.
  --
  -- The last two have no such flag and lean on jobstart's `cwd` alone --
  -- which per the note above is not reliable, so they are genuinely a
  -- last resort, not equals of the ones above them.
  local terminals = {
    -- Matches the zero-padding windows that Super+C and the fish nvim/nv
    -- wrappers open. Keep the pad value in sync with ~/.local/bin/nvim-foot.
    { "foot", { "-o", "main.pad=0x0 center", "-D", cwd } },
    { "ghostty", { "--working-directory=" .. cwd, "-e" } },
    { "kitty", { "--directory", cwd } },
    { "alacritty", { "--working-directory", cwd, "-e" } },
    { "wezterm", { "start", "--cwd", cwd } },
    { "konsole", { "--workdir", cwd, "-e" } },
    { "gnome-terminal", { "--working-directory=" .. cwd, "--" } },
    { "xfce4-terminal", { "--working-directory=" .. cwd, "-x" } },
    -- Debian's generic alternative, then the one X terminal that is
    -- essentially always present. Both take -e and neither takes a cwd.
    { "x-terminal-emulator", { "-e" } },
    { "xterm", { "-e" } },
  }

  for _, term in ipairs(terminals) do
    if vim.fn.executable(term[1]) == 1 then
      local argv = { term[1] }
      vim.list_extend(argv, term[2])
      vim.list_extend(argv, nvim_args)
      vim.fn.jobstart(argv, { detach = true, cwd = cwd })
      return
    end
  end

  vim.notify(
    "instant.nvim: no supported terminal found to open the mirror window."
      .. " The session IS hosted on port "
      .. port
      .. " -- join it manually from another nvim with <leader>isj.",
    vim.log.levels.ERROR
  )
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
  local file = current_tab_file()
  local cwd = vim.fn.getcwd()

  -- If THIS window is already part of a session -- as the original host, or
  -- as a mirror that was itself joined earlier -- don't start a competing
  -- server. Earlier versions did, which chained sessions together instead
  -- of sharing one: press <leader>iss in a mirror, and that mirror would
  -- spin up its OWN independent server and spawn a NEW mirror joined to
  -- ITSELF, not to the original session. Instead, just add one more mirror
  -- to whatever session this window is already in.
  if vim.g.instant_root_port then
    print("Root session is on port " .. vim.g.instant_root_port .. " -- opening another mirror of it")
    -- Re-snapshot the tab layout as it is RIGHT NOW, before the new mirror
    -- can read it. The snapshot used to be written exactly once, when the
    -- session first started hosting, so every later mirror bootstrapped
    -- from a picture of the past: tabs that have since been closed, and --
    -- the damaging part -- files that are no longer open anywhere.
    -- instant.nvim only shares buffers that are CURRENTLY open, so a
    -- snapshot entry naming a closed file can never be resolved and the
    -- mirror waits out the full 30s poll timeout on it. That is the
    -- reported "the second <leader>iss is much slower than the first" plus
    -- its "gave up waiting for ..." warning. Writing a fresh snapshot here
    -- costs nothing and means each mirror mirrors what you actually have
    -- open. (shared_tabs.lua's bootstrap no longer serialises on these
    -- lookups either, so a stale entry that does slip through now costs
    -- only its own tab.)
    require("util.shared_tabs").write_snapshot(vim.g.instant_root_port)
    spawn_mirror_window(vim.g.instant_root_port, file, cwd)
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
    if not port_available(port) then
      goto continue
    end
    local ok = pcall(vim.cmd, "InstantStartServer 127.0.0.1 " .. port)
    if ok then
      is_hosting = true
      vim.g.instant_root_port = port
      vim.cmd("InstantStartSession 127.0.0.1 " .. port)
      add_session(port, file)

      -- Hand the floating terminal's existing workspace to this brand-new
      -- session immediately, while its name is still unclaimed -- BEFORE
      -- spawn_mirror_window below puts a second window in the race. See
      -- util/floating_term.lua's claim_workspace for what goes wrong when
      -- this is left until the next <C-/> instead.
      require("util.floating_term").claim_workspace()

      -- Clear any stale event log/snapshot a PREVIOUS, unrelated session
      -- may have left behind under this exact port number -- see
      -- random_port()'s comment above for why this was a real, confirmed
      -- bug (a new session silently inheriting old garbage state), not
      -- just theoretical. Then snapshot the FULL current tab layout right
      -- now, at the exact moment this window becomes a root session -- not
      -- just future changes. Tabs opened before this point never fired
      -- shared_tabs.lua's TabNew/BufReadPost hooks (they early-return when
      -- there's no root_port yet), so without an explicit snapshot here, a
      -- mirror spawned a moment later would only ever have the ONE tab you
      -- happened to be on, not the two or three you already had open.
      local shared_tabs = require("util.shared_tabs")
      shared_tabs.reset(port)
      shared_tabs.write_snapshot(port)

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

      if file ~= "" then
        print("Root session: hosting " .. file .. " on port " .. port .. " -- opening mirror window")
      else
        print(
          "Root session started on port "
            .. port
            .. " -- no file open here, so the mirror window opens blank too."
            .. " Open a file, then press <leader>iss again to mirror it."
        )
      end
      spawn_mirror_window(port, file, cwd)
      return
    end
    ::continue::
  end
  print("Could not find a free port after 5 attempts")
end

-- Same polling idea as spawn_mirror_window's generated script, but running
-- in-process (no jobstart/script file needed) since this join happens in
-- the current nvim, not a spawned one.
local function poll_and_focus(file, sender_cwd, attempts_left)
  local buf = find_synced_buf(file, sender_cwd)
  if buf then
    -- See the generated script above: display_buf disposes of the empty
    -- unnamed buffer it replaces instead of orphaning it as a [No Name].
    require("util.shared_tabs").display_buf(0, buf)
    return
  end
  if attempts_left > 0 then
    vim.defer_fn(function()
      poll_and_focus(file, sender_cwd, attempts_left - 1)
    end, 200)
  else
    local seen = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) then
        table.insert(seen, "[" .. vim.api.nvim_buf_get_name(b) .. "]")
      end
    end
    vim.notify(
      "instant.nvim: gave up waiting for '" .. file .. "'. Buffers present: " .. table.concat(seen, " "),
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
---@param fallback_cwd string? the host's cwd, for the same reason
local function do_join(port, fallback_file, fallback_cwd)
  pcall(vim.cmd, "InstantStop")
  local file = current_tab_file()
  if file == "" and fallback_file and fallback_file ~= "" then
    file = fallback_file
  end
  -- Whoever shared this file did the naming, so the prediction has to use
  -- THEIR cwd. Ours only coincides with it for the auto-spawned mirror.
  local sender_cwd = fallback_cwd or session_cwd(port)
  vim.cmd("InstantJoinSession 127.0.0.1 " .. port)
  vim.g.instant_root_port = tonumber(port)
  -- Same reasoning as host_session's call: claim while the name is still
  -- unclaimed. Normally a no-op here (the host got there first); it only
  -- does anything when nobody in the session has opened a float yet, in
  -- which case this window's own workspace becomes the shared one rather
  -- than being abandoned.
  require("util.floating_term").claim_workspace()
  if file ~= "" then
    vim.defer_fn(function()
      poll_and_focus(file, sender_cwd, 150)
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
    table.insert(items, { label = label, port = entry.port, file = entry.file, cwd = entry.cwd })
  end

  vim.ui.select(items, {
    prompt = "Join instant.nvim session:",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      do_join(choice.port, choice.file, choice.cwd)
    end
  end)
end

return {
  "jbyuki/instant.nvim",
  init = function()
    vim.g.instant_username = vim.env.USER or "user"
    -- instant.nvim's `g:instant_only_cwd` defaults to TRUE, which makes it
    -- silently refuse to share any buffer whose path isn't under the
    -- sender's cwd -- see its instantOpenOrCreateBuffer(): it computes
    -- fnamemodify(name, ":.") and, when that shortens nothing (i.e. the
    -- file is outside cwd), skips the buffer entirely. No error, no notice,
    -- the file just never appears in the other window. That is exactly the
    -- reported "sometimes some files/buffers aren't shared across session
    -- windows": whether a file syncs depended on whether it happened to
    -- live under the cwd of whichever window opened it, which for this
    -- workflow (one Neovim, several sibling project dirs -- mobile-app,
    -- api, agent-api) is roughly a coin flip. Files outside cwd fall back
    -- to a basename-only name on the wire, which util/instant_bufname.lua
    -- already predicts.
    vim.g.instant_only_cwd = false
    -- The collaboration layer's own magic: makes any terminal spawned
    -- anywhere (Claude, a shell, whatever) transparently mirror across
    -- collaborative windows once a root session exists. No other plugin
    -- opts into this or knows it's happening -- see util/shared_terminal.lua.
    -- Same idea for tab creation -- see util/shared_tabs.lua. `init` runs at
    -- startup for every window, lazy-loaded plugin or not, so both are
    -- active well before any <leader>iss press.
    require("util.shared_terminal").install()
    require("util.shared_tabs").install()
  end,
  keys = {
    { "<leader>iss", host_session, desc = "Instant: host session + open mirror window" },
    { "<leader>isj", join_session, desc = "Instant: join session (manual port)" },
    { "<leader>isS", stop_session, desc = "Instant: stop/leave" },
    { "<leader>isp", pick_session, desc = "Instant: pick a session to join/switch to" },
  },
}
