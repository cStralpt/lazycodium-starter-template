-- The collaboration layer's own magic for the 'modified' flag: keeps it
-- meaning what Neovim says it means -- "this buffer differs from the file on
-- disk" -- instead of "instant.nvim wrote to this buffer".
--
-- WHY. Joining a session replaces every shared buffer wholesale with the
-- host's content (instant.nvim's lua/instant.lua:1458, and again at :1490 for
-- files the joining window did not already have open):
--
--     vim.api.nvim_buf_set_lines(buf, 0, -1, false, prev)
--
-- An API write ALWAYS sets 'modified', even when what it wrote is byte for
-- byte what was already there. Verified directly, outside this config:
--
--     :edit file          -> modified = false
--     set_lines(its own lines straight back) -> modified = true
--
-- So the moment a mirror window joined, every file it shared grew the
-- bufferline's unsaved dot and every :q asked "Save changes to api/.env?" --
-- while the root window it mirrors showed nothing modified at all, because
-- nobody had actually changed a thing. The content was identical on both
-- sides; only the flag disagreed.
--
-- The flag goes stale the other way round too, in EITHER window: the host
-- types (both sides now genuinely modified -- correct), then the host saves.
-- Nothing on the wire says "saved", so the other window goes on claiming
-- unsaved changes it does not have, and its next :q prompts for them.
--
-- FIX. When a buffer settles, compare it against the file on disk and clear
-- 'modified' only when the two are identical. That is the flag's own
-- definition, so this cannot hide real work: a local edit, or a remote edit
-- the host has not written yet, both still differ from disk and stay marked.
-- Every check below fails CLOSED -- unreadable file, size cap, an encoding
-- that makes the comparison meaningless -- and leaves the buffer marked.
--
-- Scope is the root session, the same rule shared_terminal.lua uses for
-- termopen: with no vim.g.instant_root_port set, nothing here ever touches a
-- buffer, so ordinary non-collaborative editing behaves exactly as it did
-- before this file existed.
local M = {}

-- A burst of remote edits is one comparison, not one per keystroke.
local DEBOUNCE_MS = 250

-- Never read a multi-megabyte file back just to second-guess a flag.
local MAX_BYTES = 2 * 1024 * 1024

local timers = {}
local attached = {}

---The bytes `:w` would write for this buffer.
---
---The line ending and the trailing-newline rule are read off the BUFFER, not
---off globals: they came from this window's own read of this very file, so a
---CRLF file or one with no final newline compares equal to itself instead of
---looking permanently different and never clearing.
local function buf_bytes(buf)
  local sep = "\n"
  local ff = vim.bo[buf].fileformat
  if ff == "dos" then
    sep = "\r\n"
  elseif ff == "mac" then
    sep = "\r"
  end
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), sep)
  if vim.bo[buf].endofline then
    text = text .. sep
  end
  return text
end

local function disk_bytes(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local bytes = f:read("*a")
  f:close()
  return bytes
end

---Clear 'modified' if -- and ONLY if -- this buffer already matches its file.
---@param buf integer
local function reconcile(buf)
  -- Not collaborating: leave every flag exactly as Neovim set it.
  if not vim.g.instant_root_port then
    return
  end
  if not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modified then
    return
  end
  -- Terminals, quickfix, help, the workspace floats: not file-backed, so
  -- "differs from disk" is not a question that has an answer for them.
  if vim.bo[buf].buftype ~= "" then
    return
  end

  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    -- instant.nvim also creates buffers for remote files before it has a name
    -- for them, and the same wholesale set_lines marks those modified as well.
    -- An EMPTY unnamed buffer has nothing to save, so its dot is pure noise --
    -- one with text in it is somebody's real scratch buffer and is left alone.
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if #lines == 0 or (#lines == 1 and lines[1] == "") then
      vim.bo[buf].modified = false
    end
    return
  end

  local stat = vim.uv.fs_stat(name)
  -- No file on disk means a genuinely new, never-written buffer: it MUST stay
  -- modified, or its content is one :q away from being lost silently.
  if not stat or stat.type ~= "file" or stat.size > MAX_BYTES then
    return
  end

  -- A non-UTF-8 'fileencoding' means :w would transcode on the way out, so
  -- these two byte strings are not comparable -- they simply won't match, and
  -- the buffer correctly keeps its flag.
  if disk_bytes(name) == buf_bytes(buf) then
    vim.bo[buf].modified = false
  end
end

---@param buf integer
local function schedule(buf)
  local timer = timers[buf]
  if timer then
    timer:stop()
  else
    timer = vim.uv.new_timer()
    timers[buf] = timer
  end
  timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
    reconcile(buf)
  end))
end

local function release(buf)
  attached[buf] = nil
  local timer = timers[buf]
  if timer then
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
    timers[buf] = nil
  end
end

---Watch a buffer for changes made by anyone -- including instant.nvim.
---
---nvim_buf_attach, not TextChanged: the writes that cause this whole problem
---come from another client's API calls, usually on a buffer that is not even
---the current one, and TextChanged only fires for edits the USER makes in the
---current buffer. on_lines sees every change whatever its source.
---
---The callback itself runs in a fast-event context, where most of the API is
---off limits, so it does the only safe thing available -- kick a libuv timer.
---All the real work happens in reconcile(), on the main loop, via
---vim.schedule_wrap.
---@param buf integer
local function attach(buf)
  if attached[buf] or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if vim.bo[buf].buftype ~= "" then
    return
  end
  attached[buf] = true
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      schedule(buf)
    end,
    -- :edit / :e! re-read the file, which is itself a "now it matches disk"
    -- moment worth re-checking.
    on_reload = function()
      schedule(buf)
    end,
    on_detach = function()
      release(buf)
    end,
  })
end

local installed = false

---Idempotent -- safe to call more than once.
function M.install()
  if installed then
    return
  end
  installed = true

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    attach(buf)
  end
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    callback = function(args)
      attach(args.buf)
      -- instant.nvim fires `doautocmd BufRead` right after it has both written
      -- and named a buffer it created, so this is also the first moment a
      -- freshly synced file can be checked at all.
      schedule(args.buf)
    end,
  })

  -- The other half: a change on the WIRE is not the only way the flag goes
  -- wrong. When the host saves, this window's buffer does not change at all --
  -- so on_lines never fires, and only a look at the disk can notice that the
  -- unsaved changes it is advertising have already been written. These are the
  -- cheap moments to take that look: reconcile() returns immediately unless a
  -- buffer is actually flying the flag, so in the normal case this costs a
  -- function call and reads nothing.
  vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "CursorHold" }, {
    callback = function(args)
      reconcile(args.buf)
    end,
  })
end

return M
