-- The Claude workspace: N Claudes as tmux panes, in groups you control.
--
-- This is the second instance of util/tmux_workspace.lua (the <C-/> terminal
-- float is the first), so groups, panes, clickable rainbow pills, <C-hjkl>
-- pane navigation and collaboration-safe session grouping are all inherited
-- rather than reimplemented.
--
-- WHY PANES. Three earlier designs failed, each for the same underlying
-- reason -- identity that Neovim owned rather than tmux:
--   1. one Claude per Neovim TAB: only ever reachable from that tab, and
--      invisible from any other window.
--   2. one Claude per Neovim terminal buffer, keyed by a slot number: not
--      addressable from another Neovim at all.
--   3. one Claude per tmux SESSION: addressable, but Neovim had to do the
--      tiling, and `split = "right", win = -1` splits the whole tabpage --
--      so three agents meant three side-by-side 35% columns and no editor.
-- A pane id (%17) is unique across the whole tmux server, so it is addressable
-- from every Neovim on the box; and tmux does the tiling, the grouping and the
-- zooming itself. Nothing here reimplements a layout.
--
--   one agent   = one pane          (%17)
--   one group   = one tmux window   ("claude tab", a pill on the winbar)
--   all of it   = one shared session, so every Neovim window sees every agent
--
-- FOCUS is tmux's own active pane -- not a variable this file keeps. That is
-- the whole reason the earlier "shared focus file" existed and could go: the
-- pane you last touched IS the focused one, it is what your next <leader>as
-- targets, and because grouped sessions share windows, two Neovim windows
-- looking at the same group already agree on it with no syncing.

local rainbow = require("util.rainbow_tabs")

local M = {}

local ws = require("util.tmux_workspace").new({
  id = "ClaudeWorkspace",
  -- No pid: every Neovim on this machine shares ONE Claude workspace, so an
  -- agent started in one terminal window is a send target in all of them.
  local_prefix = "claude-ws",
  root_prefix = "claude-ws",
  shared_local = true,
  always_group = true,
  -- The workspace is shared and owned by nobody, so nothing would ever clean it
  -- up: agents would accumulate across days. Reference-counted by view session
  -- instead -- it survives you quitting ONE Neovim, and goes away when the last
  -- one using it exits.
  kill_when_last = true,
  cmd = "claude",
  -- Never set tmux's GLOBAL default-command here -- that would make every new
  -- tmux window on this machine, including the <C-/> terminal's, run claude.
  -- Each window and pane gets `claude` passed explicitly instead.
  set_global_shell = false,
  float = { width = 0.9, height = 0.9 },
  missing_msg = "No Claude workspace yet (<leader>ac to start one)",
})

M.workspace = ws

--=============================================================================
-- Agents = panes
--=============================================================================

---@class ClaudeAgent
---@field slot integer 1-based position in the workspace, what a count-send targets
---@field pane string tmux pane id, the real identity
---@field group integer tmux window index -- the "claude tab" this agent lives in
---@field active boolean the focused agent: active pane AND active group. pane_active alone is set
---       on one pane per window, so reading it alone makes several agents look focused at once.
---@field group_active boolean this agent's group is the one currently on screen
---@field name string display label
---@field cwd string

---Every agent, in group then pane order. Read live from tmux on each call --
---there is no registry to drift out of sync with reality, which is what made
---the previous versions accumulate phantom agents.
---@return ClaudeAgent[]
function M.list()
  local agents = {}
  for _, p in ipairs(ws.list_panes()) do
    agents[#agents + 1] = {
      slot = #agents + 1,
      pane = p.pane,
      group = p.window,
      active = p.active,
      group_active = p.group_active,
      cwd = p.cwd,
      name = vim.fn.fnamemodify(p.cwd ~= "" and p.cwd or vim.fn.getcwd(), ":t"),
    }
  end
  return agents
end

---The agent sends go to: tmux's active pane in the group you're looking at.
---@return ClaudeAgent?
function M.current()
  local agents = M.list()
  for _, a in ipairs(agents) do
    if a.active then
      return a
    end
  end
  return agents[1]
end

---Last ~300 rendered lines of a pane, as a list.
local function pane_text(pane)
  local out = vim.fn.systemlist({ "tmux", "capture-pane", "-p", "-S", "-300", "-t", pane })
  if vim.v.shell_error ~= 0 then
    return {}
  end
  return out
end

---A one-line summary of what an agent is holding, for a picker row.
---
---This is CONTENT, not status: it is text tmux actually rendered, quoted
---verbatim. That distinction is why it's here at all -- inferring "working" or
---"waiting" from the same screen was guesswork and got removed, but "the last
---thing in this pane says X" is a fact, and it is the only thing that tells
---four agents in one repo apart.
---
---Prefers the prompt line (Claude draws it with a leading chevron), since
---that's what you typed and what you'd recognise; falls back to the last
---non-empty line for a pane that has scrolled past its prompt.
-- Every chevron Claude's prompt has been seen drawn with, plus plain ">" for a
-- shell. An explicit list rather than "any leading punctuation": that would
-- also match bullets, box-drawing and list markers, which fill the output.
--
-- Compared as STRING PREFIXES, never as a Lua character class. Lua patterns are
-- byte-based, so "[\u{276f}\u{203a}]" is a set of the individual BYTES of
-- those glyphs, and "^[...]%s" then requires whitespace at byte 2 -- inside a
-- 3-byte chevron. It could never match a real prompt line, which is why rows
-- silently fell through to whatever text sat below the prompt.
local PROMPT_PREFIXES = { "\u{276f}", "\u{203a}", "\u{27e9}", "\u{276d}", "\u{25b6}", ">" }

---The text after a leading prompt glyph, "" for a bare prompt, nil if this
---isn't a prompt line at all.
local function after_prompt(line)
  for _, glyph in ipairs(PROMPT_PREFIXES) do
    if line:sub(1, #glyph) == glyph then
      return vim.trim(line:sub(#glyph + 1))
    end
  end
  return nil
end

---Resolve a send/focus target. An explicit count (`2<leader>as`) wins;
---otherwise it's the active pane. Returning the count separately is what lets
---a count-send reach another agent WITHOUT moving tmux's focus.
---@param count integer? usually vim.v.count
local function resolve(count)
  local agents = M.list()
  if #agents == 0 then
    return nil
  end
  if count and count > 0 then
    if not agents[count] then
      vim.notify(("No Claude agent %d"):format(count), vim.log.levels.WARN)
      return nil
    end
    return agents[count]
  end
  return M.current()
end

---Make `agent` the active pane, selecting its group first so the workspace is
---actually showing it.
function M.focus(agent)
  if type(agent) == "number" then
    agent = M.list()[agent]
  end
  if not agent then
    return
  end
  vim.fn.system({ "tmux", "select-window", "-t", ws.session() .. ":" .. agent.group })
  vim.fn.system({ "tmux", "select-pane", "-t", agent.pane })
  ws.refresh_indicator()
  M.redraw()
end

--=============================================================================
-- Sending
--=============================================================================

---Type text into an agent exactly as if you'd typed it yourself -- no MCP
---involved. `send-keys -l` sends it literally, leaving it in Claude's prompt
---for you to review and submit, rather than firing it off.
---@param text string
---@param count integer? explicit slot (vim.v.count); nil/0 = focused agent
---@param on_sent function? called only once the text was actually delivered, so
---callers can clear state (e.g. send marks) that must survive a failed send
---Wait until a freshly spawned agent is actually ready for input, then run
---`cb`. A brand-new Claude takes several seconds to draw its prompt, and text
---typed before then is swallowed by the TUI's first redraw -- so an
---auto-spawned agent would silently eat exactly the selection you sent it.
---
---Polls asynchronously (never blocks Neovim) and gives up after ~10s, sending
---anyway rather than dropping your text.
local function when_ready(agent, cb, attempts)
  attempts = attempts or 40
  for _, line in ipairs(pane_text(agent.pane)) do
    local prompt = after_prompt(vim.trim(line))
    -- A numbered option is a MENU, not an input prompt. A fresh Claude in an
    -- untrusted folder draws "> 1. Yes, I trust this folder" -- which reads as a
    -- prompt by shape, so without this the selection you sent would be typed
    -- into that dialog instead of the conversation.
    if prompt and not prompt:match("^%d+%.%s") then
      return cb()
    end
  end
  if attempts <= 0 then
    return cb()
  end
  vim.defer_fn(function()
    when_ready(agent, cb, attempts - 1)
  end, 250)
end

---Type text into an agent exactly as if you'd typed it yourself -- no MCP
---involved. `send-keys -l` sends it literally, leaving it in Claude's prompt for
---you to review and submit, rather than firing it off.
---
---With no count this also TAKES YOU THERE: it focuses the target pane and opens
---the workspace, so sending a selection lands you in front of the agent that
---received it. A counted send (`2<leader>as`) deliberately does neither -- its
---whole purpose is nudging another agent while you stay where you are.
---
---With no agents at all it spins one up first, waits for it to be ready, and
---then sends -- so <leader>as works from a cold start without <leader>ac.
---@param text string
---@param count integer? explicit slot (vim.v.count); nil/0 = focused agent
---@param on_sent function? called only once the text was actually delivered, so
---callers can clear state (e.g. send marks) that must survive a failed send
function M.send(text, count, on_sent)
  local counted = count ~= nil and count > 0

  local function deliver(agent)
    vim.fn.system({ "tmux", "send-keys", "-t", agent.pane, "-l", text })
    if vim.v.shell_error ~= 0 then
      vim.notify(("Agent %d (%s) is gone"):format(agent.slot, agent.pane), vim.log.levels.WARN)
      return
    end
    if not counted then
      M.focus(agent)
      pcall(ws.show)
    end
    -- Always confirm WHERE it landed. With one agent this is noise you learn to
    -- ignore; with several -- especially a counted send into a group you aren't
    -- looking at -- it's the difference between catching a mis-send now and
    -- catching it five minutes later.
    vim.notify(("-> %d %s"):format(agent.slot, agent.name))
    if on_sent then
      on_sent()
    end
  end

  local agent = resolve(count)
  if agent then
    deliver(agent)
    return
  end

  -- A counted send names a slot that must already exist; spawning a fresh agent
  -- could never be slot N, so don't pretend otherwise.
  if counted then
    return
  end

  ws.ensure_session()
  agent = resolve(0)
  if not agent then
    vim.notify("Could not start a Claude agent", vim.log.levels.WARN)
    return
  end
  pcall(ws.show)
  vim.notify(("Started %s -- sending once it's ready"):format(agent.name))
  when_ready(agent, function()
    deliver(agent)
  end)
end

--=============================================================================
-- Actions (thin wrappers over the workspace)
--=============================================================================

-- Chrome Claude draws in every pane. Matched by PATTERN, not exact string --
-- these carry version numbers, changing model names and shortcut hints, so
-- equality matching let them straight through and rows came back reading
-- "Enter to confirm - Esc to cancel" or "medium / effort" for every agent,
-- which is the identical-rows problem this is meant to solve.
local CHROME_PATTERNS = {
  "Esc to cancel",
  "to interrupt",
  "shift%+tab",
  "auto mode on",
  "bypass permissions",
  "^%s*[\u{2500}\u{2501}\u{2550}%-_]+%s*$", -- horizontal rules
  "^/%a+",                                     -- slash-command status lines
  "\u{25d0}",                                 -- the effort indicator glyph
}

local function is_chrome(line)
  for _, pat in ipairs(CHROME_PATTERNS) do
    if line:find(pat) then
      return true
    end
  end
  return false
end

---A one-line hint of what an agent is holding, for a picker row.
---
---BEST EFFORT, and deliberately labelled as such. It reads text tmux actually
---rendered -- so unlike the status detection that was removed, nothing here is
---inferred -- but WHICH line is the interesting one is still a guess about a
---TUI that owes us no stability. It prefers the prompt line, skips known
---chrome, and returns nothing rather than showing chrome when it can't tell.
---
---The reliable half of the picker is the PREVIEW, which shows the pane
---verbatim. This line exists to make scanning fast, not to be trusted.
local function summary(pane)
  local lines = pane_text(pane)
  local last_nonempty
  for i = #lines, 1, -1 do
    local line = vim.trim(lines[i])
    if line ~= "" and not is_chrome(line) then
      local prompt = after_prompt(line)
      if prompt then
        -- A bare chevron is an EMPTY prompt, not content: stop here and report
        -- nothing rather than reaching further up for unrelated text.
        return prompt
      end
      last_nonempty = last_nonempty or line
    end
  end
  return last_nonempty or ""
end

-- Highlight groups are created on demand and cached. Deliberately NOT created
-- inside a picker's format callback: that runs during a redraw, which is no
-- place to be defining highlights. They're built while items are assembled.
local hl_cache = {}
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    hl_cache = {}
  end,
})

---The hue a group owns -- the SAME accent its pill carries on the workspace
---winbar, so a group is one colour everywhere you see it. tmux window indices
---are 0-based and rainbow.color is 1-based.
local function group_hl(group)
  local name = ("ClaudeGrp%d"):format(group)
  if not hl_cache[name] then
    vim.api.nvim_set_hl(0, name, { fg = rainbow.color(group + 1), bold = true })
    hl_cache[name] = true
  end
  return name
end

-- How far each successive tab within a group is mixed toward the background.
-- Shades of the group's own hue rather than unrelated accents: the tab must
-- read as belonging to its group first and being distinct second. Stops at 0.45
-- so the dimmest shade is still comfortably legible, and cycles for groups with
-- more tabs than steps.
local TAB_SHADES = { 1.0, 0.74, 0.58, 0.46 }

---A tab's colour: its group's hue, shaded by position within that group.
---@param group integer tmux window index
---@param nth integer 1-based position of this agent inside its group
local function tab_hl(group, nth)
  local name = ("ClaudeGrp%dTab%d"):format(group, nth)
  if not hl_cache[name] then
    local accent = rainbow.color(group + 1)
    local factor = TAB_SHADES[((nth - 1) % #TAB_SHADES) + 1]
    local fg = factor >= 1 and accent or rainbow.blend(accent, rainbow.base_bg(), factor)
    vim.api.nvim_set_hl(0, name, { fg = fg, bold = true })
    hl_cache[name] = true
  end
  return name
end

---Wrap a workspace action so it works from anywhere, cold.
---
---Two things every agent-creating action needs and none of them had:
---  1. ensure_session first, so pressing <leader>ao from the editor with no
---     workspace yet CREATES one instead of warning "no workspace yet". The raw
---     workspace actions no-op on a missing session, which is right for the
---     terminal float (where <C-/> is the only way in) and wrong here.
---  2. show afterwards, so you actually see what you just made. Splitting an
---     invisible workspace and then having to press <leader>ac to look at it is
---     two steps for one intention.
---Uses ws.show(), never ws.toggle(): toggling would CLOSE the float when the
---action was triggered from inside it.
local function acts(fn)
  return function(...)
    -- ensure_session() is NOT called here: ws.show() below does it, and the
    -- action itself now recovers by ensuring-and-retrying if its tmux command
    -- fails. Calling it here as well meant every keypress paid for the whole
    -- ensure path twice, which was a measurable share of the 21 blocking forks
    -- an action used to cost.
    fn(...)
    -- The reveal must not take the action down with it: the agent you just
    -- created still exists even if the float fails to open. But it is REPORTED
    -- rather than swallowed -- a silent pcall here is what made "<leader>aV
    -- didn't open anything" impossible to diagnose.
    local ok, err = pcall(ws.show)
    if not ok then
      vim.notify("Claude workspace created, but the float failed to open: " .. tostring(err), vim.log.levels.ERROR)
    end
    M.redraw()
  end
end

M.toggle = ws.toggle
M.new_group = acts(ws.new_tab)
M.split_below = acts(ws.split_horizontal)
M.split_right = acts(ws.split_vertical)
M.next_group = acts(ws.next_tab)
M.prev_group = acts(ws.prev_tab)
-- Closing is the one action that deliberately does NOT reveal: if you closed an
-- agent from the editor, popping the workspace open is the opposite of what you
-- asked for.
M.close_agent = ws.close_pane

---Show ONLY this agent, hiding the others in its group -- and toggle back.
---tmux's own zoom, so the hidden agents keep running and the exact layout
---comes back on the second press. The group's pill gets a marker while
---zoomed, so hidden panes are never invisible state.
M.zoom = acts(ws.zoom_pane)

---Move the focused agent somewhere else.
---
---Destinations are individual AGENTS, not just groups. "Move to group 1" is
---under-specified once a group holds more than one agent -- tmux splits
---whichever pane happens to be active there, so where your agent lands depends
---on state you can't see from the picker. Naming the agent to land beside makes
---the result exactly what you chose.
---
---Rows are grouped by their group and carry the same content summary as the
---focus picker, so you're choosing by what an agent is holding rather than by
---an index. "New group of its own" is the last row, which is why breaking out
---needs no key of its own.
---
---With a count (`2<leader>am`) it still goes straight to group 2, read off the
---workspace winbar pills.
---
---The agent keeps running throughout -- tmux's join-pane/break-pane relocate a
---live pane, they don't restart anything.
---@param count integer? target group index, usually vim.v.count
function M.move_to_group(count)
  local cur = M.current()
  if not cur then
    vim.notify("No Claude agent yet (<leader>ac to start one)", vim.log.levels.WARN)
    return
  end

  if count and count > 0 then
    if ws.move_pane_to_group(count) then
      vim.notify(("%s -> group %d"):format(cur.name, count))
      pcall(ws.show)
      M.redraw()
    end
    return
  end

  -- Rows are built as a small hierarchy rather than a flat list: a header per
  -- group, then the agents inside it. The question being answered is "which
  -- tab do you want to land on", and that only reads clearly if the tabs are
  -- shown under the group they belong to -- a flat list of "beside 4" gives no
  -- sense of the layout you're moving into.
  --
  -- Headers are selectable too, meaning "into this group, wherever tmux puts
  -- it". That keeps the coarse choice available without a dead, unselectable
  -- row in the middle of the list.
  local by_group, order = {}, {}
  for _, a in ipairs(M.list()) do
    if not by_group[a.group] then
      by_group[a.group] = {}
      order[#order + 1] = a.group
    end
    table.insert(by_group[a.group], a)
  end
  table.sort(order)

  local items = {}
  for _, g in ipairs(order) do
    items[#items + 1] = { kind = "group", group = g, target = g }
    for _, a in ipairs(by_group[g]) do
      -- Its own pane is not a destination.
      if a.pane ~= cur.pane then
        items[#items + 1] = {
          kind = "pane",
          target = a.pane,
          group = a.group,
          slot = a.slot,
          summary = summary(a.pane),
        }
      end
    end
  end
  items[#items + 1] = { kind = "new", target = nil }

  local function label_of(item)
    if item.kind == "new" then
      return "new group of its own"
    elseif item.kind == "group" then
      return ("group %d"):format(item.group)
    end
    return ("    beside %d  %s"):format(item.slot, item.summary ~= "" and item.summary or "(empty)")
  end

  local ok = pcall(function()
    Snacks.picker.pick({
      title = ("Move %s to"):format(cur.name),
      items = items,
      format = function(item)
        if item.kind == "new" then
          return { { "+ ", "SnacksPickerSpecial" }, { "new group of its own", "SnacksPickerSpecial" } }
        elseif item.kind == "group" then
          return {
            { ("\u{25be} group %d"):format(item.group), "SnacksPickerLabel" },
            { "   (anywhere in it)", "SnacksPickerDimmed" },
          }
        end
        return {
          { "    beside " },
          { ("%d "):format(item.slot), "ClaudeAgentSlot" .. item.slot },
          { item.summary ~= "" and item.summary or "(empty)", item.summary ~= "" and "SnacksPickerLabel" or "SnacksPickerDimmed" },
        }
      end,
      confirm = function(picker, item)
        picker:close()
        if not item then
          return
        end
        local moved = item.kind == "new" and ws.break_pane_to_group() or ws.move_pane_to_group(item.target)
        if moved then
          vim.notify(("%s -> %s"):format(cur.name, label_of(item)))
          pcall(ws.show)
          M.redraw()
        end
      end,
    })
  end)
  if ok then
    return
  end

  vim.ui.select(items, {
    prompt = ("Move %s to"):format(cur.name),
    format_item = label_of,
  }, function(choice)
    if not choice then
      return
    end
    local moved = choice.kind == "new" and ws.break_pane_to_group() or ws.move_pane_to_group(choice.target)
    if moved then
      vim.notify(("%s -> %s"):format(cur.name, label_of(choice)))
      pcall(ws.show)
      M.redraw()
    end
  end)
end

---Pick an agent.
---
---Rows lead with what's IN each pane, because the identifying fields don't
---identify: four agents in one repo render as four identical
---"mobile-app ~/planckifi/mobile-app" rows, which is a list you cannot choose
---from. The directory moves to the preview, where it's still available but
---isn't occupying the column your eye scans.
---
---Falls back to vim.ui.select when snacks.picker isn't around, so this keeps
---working without it -- just without the preview.
function M.pick()
  local agents = M.list()
  if #agents == 0 then
    vim.notify("No Claude agents yet (<leader>ac to start one)", vim.log.levels.WARN)
    return
  end

  -- Grouped, not flat: a bare list of "1 g0 / 2 g0 / 3 g1" makes you read the
  -- group column on every row to reconstruct a structure the picker could just
  -- show. Headers carry their group's own accent -- the same one its pill has
  -- on the workspace winbar -- and each tab inside is a shade of that hue, so a
  -- row tells you which group it belongs to before you've read any text.
  local by_group, order = {}, {}
  for _, a in ipairs(agents) do
    if not by_group[a.group] then
      by_group[a.group] = {}
      order[#order + 1] = a.group
    end
    table.insert(by_group[a.group], a)
  end
  table.sort(order)

  local items = {}
  for _, g in ipairs(order) do
    items[#items + 1] = {
      kind = "group",
      group = g,
      hl = group_hl(g),
      agent = by_group[g][1], -- selecting a header lands on the group's first tab
      text = ("group %d"):format(g),
    }
    for nth, a in ipairs(by_group[g]) do
      local text = summary(a.pane)
      items[#items + 1] = {
        kind = "pane",
        agent = a,
        nth = nth,
        hl = tab_hl(g, nth),
        preview = { text = table.concat(pane_text(a.pane), "\n"), ft = "text" },
        -- What fuzzy matching searches: the pane's content as well as its
        -- coordinates, so "vsdaasd" finds the agent you typed that into.
        text = ("%d %d %s %s %s"):format(a.slot, a.group, a.name, a.cwd, text),
        summary = text,
      }
    end
  end

  local ok = pcall(function()
    Snacks.picker.pick({
      title = "Claude agents",
      items = items,
      format = function(item)
        if item.kind == "group" then
          return { { ("\u{25be} group %d"):format(item.group), item.hl } }
        end
        local a = item.agent
        return {
          -- The indent guide is the group's own hue, so the whole block reads
          -- as one column; the number is that hue shaded by position.
          { a.active and " \u{258c}" or " \u{2502}", group_hl(a.group) },
          { (" %d "):format(a.slot), item.hl },
          { item.summary ~= "" and item.summary or "(empty)", item.summary ~= "" and "SnacksPickerLabel" or "SnacksPickerDimmed" },
        }
      end,
      preview = function(ctx)
        ctx.preview:reset()
        local buf = ctx.preview:scratch()
        local a = ctx.item.agent
        ctx.preview:set_title(("%d  %s  %s"):format(a.slot, a.name, vim.fn.fnamemodify(a.cwd, ":~")))
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, pane_text(a.pane))
      end,
      confirm = function(picker, item)
        picker:close()
        if item then
          M.focus(item.agent)
          pcall(ws.show)
        end
      end,
    })
  end)
  if ok then
    return
  end

  -- No snacks.picker: plain select, same row content.
  local plain = {}
  for _, item in ipairs(items) do
    plain[#plain + 1] = {
      agent = item.agent,
      label = item.kind == "group" and ("group %d"):format(item.group)
        or ("   %s%d  %s"):format(item.agent.active and ">" or " ", item.agent.slot, item.summary),
    }
  end
  vim.ui.select(plain, {
    prompt = "Claude agents",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      M.focus(choice.agent)
      pcall(ws.show)
    end
  end)
end

--=============================================================================
-- Statusline
--=============================================================================

---Click handler for a statusline agent pill. 'statusline' click syntax only
---accepts a callable NAME, not a closure, so this is registered globally --
---the same pattern the workspace winbar uses.
function _G.ClaudeAgentPillClick(slot)
  M.focus(slot)
  ws.show()
end

---lualine component: one rainbow pill per agent.
---
---Color carries IDENTITY: each agent takes the accent for its slot from the
---same cycle as the tabpage chips and the workspace's own group pills, so the
---whole config reads as one system.
---
---Filled = the active pane, i.e. where <leader>as goes. Outlined = everything
---else. That is rainbow_tabs' own filled-vs-outlined argument: a shape
---difference reads at a glance even between two pills whose hues are
---neighbours. The number is printed on the pill, so a count-send (2<leader>as)
---is always read, never recalled.
---
---Deliberately no status glyphs. Neovim cannot see inside a Claude process --
---the only signals are scraping its rendered terminal (guesswork, and useless
---under bypass-permissions where the prompts it looked for never appear) or
---hooks, which would mean changing global Claude settings. Rather than paint a
---confident glyph over a guess, this shows only what is knowable.
---
---Returns "" with no agents, so a plain editing session has a clean right side.
function M.lualine()
  local agents = M.list()
  if #agents == 0 then
    return ""
  end
  local parts = {}
  for _, a in ipairs(agents) do
    local label = ("%d %s"):format(a.slot, a.name)
    parts[#parts + 1] = rainbow.pill(a.slot, a.active, label, "v:lua.ClaudeAgentPillClick")
  end
  return table.concat(parts, " ") .. "%#lualine_c_normal#"
end

function M.redraw()
  vim.schedule(function()
    pcall(vim.cmd.redrawstatus)
  end)
end

--=============================================================================
-- Setup
--=============================================================================

---Per-slot highlight groups for picker rows, using the SAME accent cycle as
---the statusline pills and the workspace winbar -- so an agent is one colour
---everywhere and the picker row you pick matches the pill you were looking at.
---Defined for a fixed range rather than on demand: the picker's format callback
---runs inside a redraw, which is no place to be creating highlight groups.
local function define_slot_hls()
  for i = 1, #rainbow.accents * 2 do
    vim.api.nvim_set_hl(0, "ClaudeAgentSlot" .. i, { fg = rainbow.color(i), bold = true })
  end
end

local started = false

function M.setup()
  if started then
    return
  end
  started = true
  define_slot_hls()
  vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function()
      vim.schedule(define_slot_hls)
    end,
  })
  -- One slow timer, and all it does is repaint: the agent list is read live
  -- from tmux, so this exists only so agents another Neovim window starts show
  -- up here on their own. Two `tmux list-*` calls every 5s, flat regardless of
  -- how many agents are running.
  local timer = vim.uv.new_timer()
  timer:start(1000, 5000, vim.schedule_wrap(M.redraw))
end

return M
