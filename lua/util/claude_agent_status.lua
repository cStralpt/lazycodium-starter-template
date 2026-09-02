-- What each Claude agent is actually doing, as reported by Claude itself.
--
-- claude_agents.lua deliberately shipped without status glyphs, and its comment
-- said why: Neovim cannot see inside a Claude process, so the only options were
-- scraping the rendered pane (guesswork, and blind under bypass-permissions
-- where the prompts it looked for never appear) or hooks, "which would mean
-- changing global Claude settings".
--
-- The reasoning held; the conclusion no longer does. Hooks do not have to be
-- global -- `claude --settings <file>` loads an extra settings file for exactly
-- the processes this workspace starts, so the workspace can wire up its own
-- reporting without touching ~/.claude/settings.json or affecting a Claude you
-- run anywhere else. See claude/hooks.settings.json and claude/agent-status.sh.
--
-- The result is fact, not inference: "working" means Claude ran a tool, and
-- "waiting" means Claude raised a permission prompt. Those are events it fired
-- itself, which is the bar the original comment set and refused to fake.
--
-- SHAPE OF THE DATA. One file per pane in a tmpfs directory, containing one
-- word. A directory of tiny files rather than one shared file because there is
-- no writer coordination available -- N Claude processes, each knowing only
-- itself, no lock -- and per-pane files make a concurrent write impossible by
-- construction rather than by luck.

local M = {}

---Statuses, in the order they matter when you are scanning the statusline for
---something to do. The glyph is deliberately the ONLY thing status controls:
---colour is already spoken for by identity (an agent's accent is the same in
---the pill, the picker row and the workspace winbar), so painting status in
---colour too would put two meanings on one channel and break the "one agent =
---one colour, everywhere" rule the rest of the config keeps.
---
---No spinner for `working`. An animated glyph means a redraw every tick
---forever, and the statusline is repainted by a timer this module does not
---own; a static ellipsis says the same thing and costs nothing.
M.GLYPHS = {
  waiting = "!", -- blocked on you: permission prompt, elicitation, input
  done = "\u{2713}", -- ✓ finished its turn, output unread
  working = "\u{2026}", -- … running tools
  idle = "", -- alive, nothing to say -- an empty pill is the resting state
}

---Permission mode, flagged only at the two ends where it changes what you can
---expect from an agent. `default` and `acceptEdits` get nothing: they behave
---the way the glyphs already describe.
---
---The bypass flag earns its place by explaining an absence -- an agent running
---with permissions skipped will never raise a prompt, so it can never show `!`,
---and without the flag you would be waiting for a signal that cannot arrive.
M.MODES = {
  plan = "\u{25c7}", -- ◇ won't edit anything
  bypassPermissions = "\u{26a1}", -- ⚡ won't stop to ask
}

---Statuses that mean the agent wants something from you. Only these spend the
---extra width on a task label and an age -- see M.render.
local ATTENTION = { waiting = true, done = true }

---How long a state has lasted, at statusline resolution. Seconds below a
---minute, then minutes, then hours: nobody needs "1h 23m 11s" on a pill, and a
---value that changes every second would repaint forever.
local function age(since)
  local secs = os.time() - (tonumber(since) or 0)
  if secs < 60 then
    return ("%ds"):format(math.max(secs, 0))
  elseif secs < 3600 then
    return ("%dm"):format(secs / 60)
  end
  return ("%dh"):format(secs / 3600)
end

---tmpfs, not ~/.cache: these are statements about processes that are alive
---right now, and they should not outlive a reboot. XDG_RUNTIME_DIR is also
---already per-user and 0700, which a shared /tmp path would not be.
M.dir = (vim.env.XDG_RUNTIME_DIR or "/tmp") .. "/nvim-claude-agents"

---@class ClaudeAgentInfo
---@field status string one of M.GLYPHS' keys
---@field since number unix time the CURRENT state began -- not when it was last
---       reported, so a run of PostToolUse "working" reports doesn't reset it
---@field mode string? permission_mode as Claude reported it
---@field task string? the prompt that started this turn, capped at 160 chars
---@field reply string? the agent's closing message for that turn, capped the
---       same way and cleared the moment a new prompt arrives -- so an answer
---       is never shown beside a task it doesn't belong to

---pane id ("%17") -> ClaudeAgentInfo. Rebuilt wholesale on every fs event
---rather than patched per-file: there are as many entries as you have agents,
---so a full rescan is a handful of stats, and a rescan cannot leave a deleted
---pane behind the way an incremental update can.
local cache = {}

local function rescan()
  cache = {}
  local fs = vim.uv.fs_scandir(M.dir)
  if not fs then
    return
  end
  while true do
    local name, kind = vim.uv.fs_scandir_next(fs)
    if not name then
      break
    end
    -- Skip the write-then-rename temporaries; they are someone else's
    -- half-written file by definition.
    if kind == "file" and not name:find("%.tmp") then
      local fd = io.open(M.dir .. "/" .. name, "r")
      if fd then
        -- key=value lines, because the writer is a POSIX shell script and this
        -- is the richest format it can produce without a JSON dependency on
        -- every hook invocation. The value runs to end of line, so a task
        -- containing "=" survives.
        local rec = {}
        for line in fd:lines() do
          local k, v = line:match("^(%w+)=(.*)$")
          if k then
            rec[k] = v
          end
        end
        fd:close()
        if rec.status and M.GLYPHS[rec.status] then
          rec.since = tonumber(rec.since) or os.time()
          -- Empty strings are the shell's way of saying "unset"; normalise so
          -- callers only ever test for nil.
          rec.mode = rec.mode ~= "" and rec.mode or nil
          rec.task = rec.task ~= "" and rec.task or nil
          rec.reply = rec.reply ~= "" and rec.reply or nil
          cache["%" .. name] = rec
        end
      end
    end
  end
end

---@param pane string tmux pane id, e.g. "%17"
---@return ClaudeAgentInfo? nil if this agent has never reported -- a Claude
---        started before the hooks existed, or one running without them.
function M.info(pane)
  return cache[pane]
end

---@param pane string
---@return string? status word, or nil
function M.get(pane)
  local rec = cache[pane]
  return rec and rec.status
end

---Everything the pill says about an agent beyond its number and name.
---
---WIDTH IS SPENT WHERE ATTENTION IS DUE. Three agents at full detail would be
---~75 columns and would re-clutter the bar that was just cleared, so only the
---agents that want something from you -- `waiting`, `done` -- get the task
---label and the age. A busy agent stays as narrow as it was, and the pill's
---own width becomes a signal you can read without reading any text.
---
---  1 api …                     working, nothing to say yet
---  2 api ⚡ ✓ add tests 14m     unread for 14 minutes, and it never asks
---  3 api ◇ !                    in plan mode and blocked on you
---
---@param pane string
---@return string "" when there is nothing to report, so callers can always
---        concatenate without checking.
function M.render(pane)
  local rec = cache[pane]
  if not rec then
    return ""
  end
  local parts = {}
  local mode = rec.mode and M.MODES[rec.mode]
  if mode then
    parts[#parts + 1] = mode
  end
  local glyph = M.GLYPHS[rec.status]
  if glyph ~= "" then
    parts[#parts + 1] = glyph
  end
  if ATTENTION[rec.status] then
    if rec.task then
      -- Truncated hard rather than at a word boundary: a pill is a fixed budget
      -- and a label that sometimes takes 20 columns defeats the point. The
      -- ellipsis marks the cut so a truncated task can't be misread as a short
      -- one. No collision with the `working` glyph -- that never renders on a
      -- status this branch runs for.
      local task = rec.task:gsub("%s+", " ")
      parts[#parts + 1] = #task > 14 and (task:sub(1, 14) .. "\u{2026}") or task
    end
    parts[#parts + 1] = age(rec.since)
  end
  return table.concat(parts, " ")
end

---One line saying what this agent is about, for somewhere with room to print
---it -- the picker, not the pill.
---
---WHICH LINE DEPENDS ON THE STATE, because the question changes with it. While
---an agent is working or blocked you want to know what it was put on: that is
---what separates two agents in the same repo, and it holds still while the pane
---scrolls underneath. Once it is done the question becomes "is this worth
---switching to", and only its closing message answers that.
---
---Also returns a direction marker -- `›` is you talking, `‹` is the agent
---answering. Without it a row is ambiguous between a demand and a result, which
---are very different things to be reading in a list you are choosing from.
---
---@param pane string
---@return string text "" when nothing was reported -- callers fall back to
---        scraping the pane, which is all there was before hooks existed.
---@return string marker "" alongside an empty text.
function M.summary(pane)
  local rec = cache[pane]
  if not rec then
    return "", ""
  end
  if rec.status == "done" and rec.reply then
    return (rec.reply:gsub("%s+", " ")), "\u{2039}"
  end
  if rec.task then
    return (rec.task:gsub("%s+", " ")), "\u{203a}"
  end
  return "", ""
end

---@param pane string
---@return string glyph alone, for callers with no room for the rest
function M.glyph(pane)
  local rec = cache[pane]
  return rec and M.GLYPHS[rec.status] or ""
end

local started = false

---Watches the directory and repaints when it changes.
---
---An fs_event on the DIRECTORY, not per-file: files appear and vanish as agents
---come and go, and a watch on a path that does not exist yet never fires. The
---directory is created here for the same reason -- the first hook to run would
---create it, but the watch has to be attached before that, not after.
function M.setup(on_change)
  if started then
    return
  end
  started = true
  vim.fn.mkdir(M.dir, "p")
  rescan()

  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end
  handle:start(M.dir, {}, function()
    -- Off the event loop thread: rescan does file IO and the callback may not
    -- call most of the API. Scheduling also coalesces the burst of events a
    -- single write-then-rename produces into one repaint.
    vim.schedule(function()
      rescan()
      if on_change then
        on_change()
      end
    end)
  end)

  -- Files outlive the process that wrote them if a Claude is SIGKILLed, since
  -- nothing gets to run SessionEnd. Harmless while running -- every read is
  -- keyed by a pane tmux still lists, so an orphan is simply never looked up --
  -- but worth sweeping once so the directory does not accumulate across a long
  -- uptime. Only panes tmux does not know about are removed.
  vim.schedule(function()
    local live = {}
    for _, line in ipairs(vim.fn.systemlist({ "tmux", "list-panes", "-a", "-F", "#{pane_id}" })) do
      live[line] = true
    end
    if vim.v.shell_error ~= 0 then
      return -- no tmux server: every file is unverifiable, so touch none
    end
    for pane in pairs(cache) do
      if not live[pane] then
        os.remove(M.dir .. "/" .. pane:sub(2))
      end
    end
    rescan()
  end)
end

return M
