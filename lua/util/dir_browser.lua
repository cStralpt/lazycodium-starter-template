-- An oil.nvim float used as a DIRECTORY PICKER: walk the tree with oil's own
-- keys, then choose the directory on screen. Behind `-` inside both workspace
-- floats (util/claude_agents.lua restarts the agent there, util/floating_term
-- .lua cds the shell there), so the browsing is one implementation.
--
-- Hierarchical on purpose, next to the flat project picker on <leader>at/ad:
-- from ~/org/api the sibling ~/org/web is "- then <CR>", which is how a
-- ~/<org>/<project> layout is actually navigated, and the listing shows what
-- a directory holds before you commit to it.
--
-- Everything oil does that would leave this float is disabled here. oil's
-- <C-h>/<C-s>/<C-t> open the entry in a split or tab, and from inside a float
-- that split lands in the editor layout BEHIND the workspace -- a stray oil
-- window at the edge of the screen. <C-hjkl> are window navigation everywhere
-- else and would walk you out of the browser leaving it open. And <CR> on a
-- FILE would open it in the workspace float's window, where snacks' fixbuf
-- re-homes it into the editor. This is a directory picker: none of that.
local M = {}

---Per-window state. Keyed by window rather than buffer because every directory
---oil shows is its own buffer in the SAME window, and the callback belongs to
---the browsing session, not to one listing.
---@type table<integer, { on_choose: fun(dir: string), confirm_keys: string[] }>
local browsers = {}

---The keys of the browser, on ONE oil buffer. Runs once per buffer: for the
---first from M.open, for every directory you navigate to after that from the
---BufWinEnter hook below.
local function bind(buf, win)
  local b = browsers[win]
  if not b then
    return
  end
  local oil = require("oil")
  local function confirm()
    local dir = oil.get_current_dir(buf)
    oil.close()
    if not dir then
      return
    end
    -- One tick later: oil's own WinLeave handler for the float is scheduled
    -- on close, and the workspace's reveal must land after it, not under it.
    vim.schedule(function()
      b.on_choose(dir)
    end)
  end
  local function close()
    oil.close()
  end
  local o = { buffer = buf }
  -- ` is oil's own "cd to this directory" key; here it means the same thing
  -- about the pane instead of the editor.
  for _, key in ipairs(b.confirm_keys) do
    vim.keymap.set("n", key, confirm, vim.tbl_extend("force", o, { desc = "Choose this directory" }))
  end
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, close, vim.tbl_extend("force", o, { desc = "Close" }))
  end
  -- <CR>: into a directory, oil's own way; on a file, a reminder instead.
  vim.keymap.set("n", "<CR>", function()
    local entry = oil.get_cursor_entry()
    if entry and entry.type == "directory" then
      oil.select({})
    else
      vim.notify("Directories only -- ` chooses the one you are looking at", vim.log.levels.INFO)
    end
  end, vim.tbl_extend("force", o, { desc = "Enter directory" }))
  -- Window navigation and oil's split/tab/preview openers (see the header),
  -- and every way into insert mode: an oil buffer is editable by design --
  -- that is how oil renames -- but this one is for choosing, not editing, and
  -- a stray `i` here left you typing into the listing.
  for _, key in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>", "<C-s>", "<C-t>", "<C-p>" }) do
    vim.keymap.set("n", key, "<Nop>", vim.tbl_extend("force", o, { desc = "which_key_ignore" }))
  end
  for _, key in ipairs({ "i", "a", "o", "A", "I", "O", "c", "C", "s", "S", "R" }) do
    vim.keymap.set("n", key, "<Nop>", vim.tbl_extend("force", o, { desc = "which_key_ignore" }))
  end
end

local hooked = false
local function hook()
  if hooked then
    return
  end
  hooked = true
  -- Bind on a buffer once it is shown in a browser window -- deferred a tick,
  -- and from TWO events, because oil sets its own keymaps twice: synchronously
  -- at BufReadCmd, and again from an async initialize once the url is
  -- normalized. A binding made at BufWinEnter alone was overwritten by that
  -- second pass (` went back to oil's :cd), so OilEnter -- fired from the
  -- render callback, after it -- binds too. BufWinEnter is still needed: oil
  -- keeps buffers alive for a while after they leave the screen, and a
  -- directory you had open in a normal oil window moments ago is reused as-is
  -- when the browser walks into it, never rendering (or firing OilEnter)
  -- again. Binding twice is harmless; vim.schedule keeps either event from
  -- being followed by a set_keymaps in the same call stack.
  local function bind_shown(buf)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        if browsers[win] then
          bind(buf, win)
        end
      end
    end)
  end
  vim.api.nvim_create_autocmd("BufWinEnter", {
    desc = "dir_browser: keep the browser's keys on every directory it shows",
    callback = function(ev)
      if vim.api.nvim_buf_get_name(ev.buf):match("^oil://") then
        bind_shown(ev.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    pattern = "OilEnter",
    desc = "dir_browser: rebind after oil's own (second) keymap pass",
    callback = function(ev)
      if ev.data and ev.data.buf then
        bind_shown(ev.data.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    desc = "dir_browser: forget a closed browser",
    callback = function(ev)
      browsers[tonumber(ev.match)] = nil
    end,
  })
end

---@class DirBrowserOpts
---@field start string directory to open at
---@field label string who is choosing, for the title -- "Claude agent 2", "terminal pane"
---@field verb string what confirming does, for the title -- "restart agent here", "cd here"
---@field on_choose fun(dir: string)
---@field confirm_keys? string[] extra keys that confirm, besides `
---@field region? { row: integer, col: integer, width: integer, height: integer } editor cells to
---       lay the browser over -- the focused tmux pane (W.pane_region). nil = the whole window
---       the browser is opened from.

---Open the browser. Call from the window the browser should return to when it
---closes: oil records the current window as the one to focus afterwards. A
---workspace dismisses its scrollback snapshot first for exactly that reason --
---the snapshot closes itself the moment focus leaves it, and a browser opened
---from it came back to a window that no longer existed, landing in the editor.
---@param opts DirBrowserOpts
function M.open(opts)
  hook()
  local confirm_keys = { "`" }
  vim.list_extend(confirm_keys, opts.confirm_keys or {})
  -- The window the browser is opened from is what it is laid out over and
  -- what it returns focus to: the workspace float.
  local anchor = vim.api.nvim_get_current_win()
  local apos = vim.api.nvim_win_get_position(anchor)
  local aw, ah = vim.api.nvim_win_get_width(anchor), vim.api.nvim_win_get_height(anchor)
  local azindex = vim.api.nvim_win_get_config(anchor).zindex or 0
  -- The workspace lands back at its prompt in insert mode when its scrollback
  -- is dismissed (just before this), and that mode followed the cursor into
  -- the browser -- into an editable buffer. Twice: here for the mode the
  -- float is opened from, and below once the oil window exists.
  vim.cmd("stopinsert")
  require("oil").open_float(opts.start, nil, function()
    -- Runs on the first buffer's BufWinEnter/OilEnter, after the hook above
    -- saw a window it did not know yet -- so the first buffer is bound here by
    -- hand; the hook takes over from the next directory on.
    if not vim.w.is_oil_win then
      return
    end
    local win = vim.api.nvim_get_current_win()
    vim.cmd("stopinsert")
    browsers[win] = { on_choose = opts.on_choose, confirm_keys = confirm_keys }
    -- Strings only: window variables cannot hold functions. plugins/oil.lua
    -- reads this to title the float on every directory it shows.
    vim.w.dir_browser = { label = opts.label, verb = opts.verb }

    -- THE PANE `-` WAS PRESSED IN, changing content -- the way `-` takes over
    -- the window it is pressed in everywhere else. The terminal buffer cannot
    -- simply be swapped for oil's (snacks' fixbuf puts it back and re-homes
    -- the intruder into the editor -- see W.scrollback), so, like the
    -- scrollback, this is a second float laid over the focused pane's cells
    -- (opts.region): the frame on the pane's edge cells, the listing inside,
    -- the path as the title and the keys as the footer, and the pane next to
    -- it untouched. Without a region it covers the whole window it was opened
    -- from, frame on frame. Not oil's own float, which is sized to the whole
    -- editor with whatever 'winborder' says -- "" here, so no frame, no
    -- title, and a listing that explained nothing.
    --
    -- relative = "editor", not "win": oil re-applies row/col as editor
    -- coordinates on every directory change, which would send a
    -- window-relative float to the top-left corner. row/col here are the
    -- OUTER corner, border included, which is also what
    -- nvim_win_get_position() reports for the workspace float.
    local r = opts.region
    local geometry = r
        and {
          row = r.row,
          col = r.col,
          width = math.max(r.width - 2, 20),
          height = math.max(r.height - 2, 5),
        }
      or { row = apos[1], col = apos[2], width = aw, height = ah }
    vim.api.nvim_win_set_config(win, {
      relative = "editor",
      row = geometry.row,
      col = geometry.col,
      width = geometry.width,
      height = geometry.height,
      border = "rounded",
      title = require("oil.util").get_title(win),
      title_pos = "center",
      footer = (" <CR> open  \u{b7}  - up  \u{b7}  ` %s  \u{b7}  q cancel "):format(opts.verb),
      footer_pos = "center",
      zindex = azindex + 2,
    })
    bind(vim.api.nvim_get_current_buf(), win)
  end)
end

return M
