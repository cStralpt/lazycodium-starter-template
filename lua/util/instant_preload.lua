-- The collaboration layer's own magic for buffers that are LISTED but not
-- LOADED: gets real content into them in the BACKGROUND, so this window shares
-- its files rather than a set of empty stubs -- without <leader>iss ever
-- waiting on it.
--
-- WHY. instant.nvim answers a joining window's REQUEST by walking
-- nvim_list_bufs() and sending one INITIAL message per buffer whose 'buftype'
-- is empty -- its lua/instant.lua:1077-1116:
--
--     local allbufs = vim.api.nvim_list_bufs()
--     ... if buftype == "" then table.insert(bufs, buf) end
--     ... allprev[buf]                    -- the lines it puts on the wire
--
-- Nothing in that filter asks whether the buffer is LOADED, and an unloaded
-- buffer has no lines to read -- so it goes out EMPTY. The joining window then
-- faithfully creates a buffer, names it README.md, and fills it with nothing.
--
-- That is the reported "the mirror doesn't really have the shared buffers
-- until I open the file in the root window". Reproduced directly, two headless
-- Neovims against this config:
--
--     host:   :edit fileA.txt   +   :badd fileB.txt   (listed, never loaded)
--     mirror, after joining:
--         buf=2 lines=2 name=fileA.txt   "line A1"
--         buf=3 lines=1 name=fileB.txt   ""            <- the empty stub
--
-- Unloaded listed buffers are not exotic -- they are exactly what restoring a
-- session leaves behind, since a restore lists every buffer but loads each one
-- lazily, when you first look at it. A window you have just reopened is
-- therefore the WORST case: nearly every buffer it would share is empty.
--
-- An empty stub is worse than a missing one, too. It is a real, named,
-- modified buffer sitting over a file full of content, so a stray :wa in the
-- window that received it writes the emptiness to disk.
--
-- WHY IN THE BACKGROUND, AND WHY THAT IS SAFE. The first version of this ran
-- the whole sweep synchronously, before the session started, on the theory
-- that a buffer had to carry its content BEFORE instant.nvim ever registered
-- it. That theory was wrong, and the cost was immediately obvious: loading a
-- buffer fires BufReadPost, which means filetype detection, treesitter and LSP
-- attach for every file in a restored session -- all of it in front of the
-- mirror window even being spawned, turning an instant <leader>iss into a
-- visible stall.
--
-- It is unnecessary because loading a buffer LATER propagates on its own.
-- instantOpenOrCreateBuffer re-sends INITIAL for it using loc2rem[buf] -- the
-- SAME remote id it was first registered under -- and the receiving side's
-- "already known" branch overwrites that buffer's content in place instead of
-- creating a second one. Verified end to end, with the host loading the buffer
-- only AFTER the mirror had already joined and taken the empty stub:
--
--     [BEFORE host loads fileB]  fileB.txt -> 1 line(s) ""
--     [AFTER  host loads fileB]  fileB.txt -> 2 line(s) "line B1"
--
-- So a mirror that joins mid-sweep is not a problem to be prevented: it gets
-- whatever is ready, and the rest fills in underneath it as the sweep catches
-- up. Nothing has to block.
--
-- ONLY THE HOST DOES THIS. lua/plugins/instant.lua calls it from host_session
-- and nowhere else, deliberately. A window that JOINS a session must not push
-- its own restored buffers into it: those are a different agent's ids for
-- paths the host already shares, so the receiving side would try to create a
-- SECOND buffer with a name it already has -- E95. Everything a mirror needs
-- flows the other way anyway, and shared_tabs.lua already avoids opening files
-- locally for exactly this reason.
local shared_tabs = require("util.shared_tabs")

local M = {}

-- Loading is disk I/O plus every BufReadPost consumer in the config, so a file
-- big enough to hurt is left alone: it stays unloaded and shares empty exactly
-- as it did before. One stub is a better trade than a stalled editor.
local MAX_BYTES = 10 * 1024 * 1024

-- One buffer per tick. The point is not throughput -- it is that Neovim gets
-- the main loop back between every single load, so a sweep over a large
-- restored session is invisible instead of a freeze.
local TICK_MS = 15

local running = false

---Would this buffer be shared empty?
---@param buf integer
local function needs_load(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_is_loaded(buf) then
    return false
  end
  -- Deliberately the same test instant.nvim's responder uses, rather than a
  -- tidier one: the set this loads has to be the set that gets shared, or the
  -- stubs simply move to whatever the two filters disagree about.
  if vim.bo[buf].buftype ~= "" then
    return false
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return false
  end
  local stat = vim.uv.fs_stat(name)
  return stat ~= nil and stat.type == "file" and stat.size <= MAX_BYTES
end

---Begin filling in this window's unloaded buffers, one per tick.
---Idempotent -- a second call while a sweep is running is a no-op.
function M.start()
  if running or not vim.g.instant_root_port then
    return
  end

  local queue = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if needs_load(buf) then
      queue[#queue + 1] = buf
    end
  end
  if #queue == 0 then
    return
  end

  running = true
  local index = 0
  local timer = vim.uv.new_timer()
  timer:start(
    TICK_MS,
    TICK_MS,
    vim.schedule_wrap(function()
      index = index + 1
      -- Leaving the session mid-sweep stops it: the rest stay unloaded, which
      -- is exactly where they would have been anyway.
      if index > #queue or not vim.g.instant_root_port then
        timer:stop()
        if not timer:is_closing() then
          timer:close()
        end
        running = false
        return
      end

      local buf = queue[index]
      -- Re-checked, not trusted: several ticks have passed since the queue was
      -- built, and the buffer may have been opened, wiped or written since.
      if needs_load(buf) then
        -- bufload(), not :edit or nvim_win_set_buf: it reads the file into the
        -- buffer in place, leaving every window, its cursor and the current
        -- buffer exactly where they were.
        --
        -- Wrapped in suppress() because the BufReadPost this fires would
        -- otherwise make shared_tabs broadcast a "file" event naming whatever
        -- buffer is CURRENT -- one duplicate per buffer loaded, aimed at every
        -- other window. Wrapped per load rather than around the whole sweep so
        -- a file the user opens themselves mid-sweep still broadcasts.
        --
        -- pcall'd because one unreadable file (vanished, permissions) must not
        -- kill the sweep; a buffer that fails to load is no worse off than it
        -- was.
        pcall(shared_tabs.suppress, function()
          vim.fn.bufload(buf)
        end)
      end
    end)
  )
end

return M
