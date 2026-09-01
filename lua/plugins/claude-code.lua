-- Claude Code inside Neovim -- two separate mechanisms, on purpose:
--
-- 1. Everyday per-tab Claude (<leader>ac / at / aw): a plain `claude` CLI
--    process per tab via snacks.nvim. Each tab gets its OWN session, keyed
--    by tab number so it never collides with another tab's. <leader>ac and
--    <leader>at always resolve to the SAME session for that tab no matter
--    which one spun it up -- toggling behaves identically either way.
--
-- 2. The MCP-integrated review session (<leader>aI...): coder/claudecode.nvim
--    can only ever hold ONE live MCP connection per Neovim process (one
--    WebSocket server, one lock file) -- that's a hard architectural limit
--    of the plugin, not a config choice. So it stays a single shared session
--    under its own prefix, giving you inline diff accept/reject and the
--    ClaudeCodeAdd-based mention commands whenever you deliberately want
--    that deeper review workflow, separate from the quick per-tab chats.

-- [tabnr] = { buf = terminal bufnr, win = winid|nil (nil = hidden), floating = bool }
-- Managed with plain Neovim APIs (not Snacks terminal identity/tid matching)
-- so toggling is explicit state, not inferred from a recreated object.
local tab_claude = {}

local function tab_id()
  return vim.api.nvim_tabpage_get_number(0)
end

---Always opens a genuinely NEW window against an explicit buffer -- never
---relies on ":vsplit"/"botright" ex-command semantics (which split whatever
---window happens to be "current" and can silently no-op under some layouts,
---leaving a buffer-swap to land on your editor window instead of a new split).
---@param floating boolean
---@param buf integer? pass an existing terminal buffer to show it; nil creates a fresh scratch buffer (for a new spawn)
local function open_win(floating, buf)
  buf = buf or vim.api.nvim_create_buf(false, true)
  if floating then
    local width = math.floor(vim.o.columns * 0.85)
    local height = math.floor(vim.o.lines * 0.85)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2),
      style = "minimal",
      border = "rounded",
    })
    -- global `vim.o.winblend = 20` (init.lua) applies to every float by
    -- default; force this one opaque so text stays readable, without
    -- touching winblend for anything else (poups, other floats, etc.)
    vim.wo[win].winblend = 0
    return win, buf
  end
  local win = vim.api.nvim_open_win(buf, true, {
    split = "right",
    win = -1, -- split off the WHOLE tabpage layout, not just whatever window is current
    width = math.floor(vim.o.columns * 0.35),
  })
  return win, buf
end

---Hide the window only. The job/buffer keeps running in the background.
local function hide(state)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, false)
  end
  state.win = nil
end

---Show the already-running terminal buffer in a fresh window.
local function show_existing(state)
  state.win = open_win(state.floating, state.buf)
  vim.cmd("startinsert")
end

local function spawn_new(state, cmd)
  local win, buf = open_win(state.floating, nil)
  state.win = win
  vim.fn.termopen(cmd, { cwd = vim.fn.getcwd(0) })
  state.buf = buf
  -- Matches shared_terminal.lua's wrap() label exactly, so
  -- tmux_tab_session_name() below can find the right shared session
  -- regardless of whether this tab was started via <leader>ac or <leader>at.
  state.cmd_label = tostring(cmd):match("^%S+") or "term"
  vim.cmd("startinsert")
end

---Toggle/create this tab's terminal. If it doesn't exist yet, it's spawned
---running `cmd` ("claude" from <leader>ac, a plain shell from <leader>at).
---If it already exists -- however it was started -- this just shows/hides
---THAT SAME one; the `cmd` argument is ignored once a terminal is running,
---so <leader>ac and <leader>at always converge on one session per tab.
local function open_tab_claude(cmd)
  local id = tab_id()
  local state = tab_claude[id]
  if not state then
    state = { floating = false }
    tab_claude[id] = state
  end

  local alive = state.buf and vim.api.nvim_buf_is_valid(state.buf)

  if not alive then
    spawn_new(state, cmd)
    return
  end

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    hide(state)
  else
    show_existing(state)
  end
end

---Move this tab's Claude between a floating window and a right split
---WITHOUT touching the running job -- same conversation, different chrome.
local function toggle_tab_claude_layout()
  local id = tab_id()
  local state = tab_claude[id]
  if not (state and state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    vim.notify("No Claude terminal in this tab yet (<leader>ac to start one)", vim.log.levels.WARN)
    return
  end
  hide(state)
  state.floating = not state.floating
  show_existing(state)
end

---Name of the shared tmux session `shared_terminal.lua` would attach this
---tab's terminal to, under collaboration -- must match its `wrap()` naming
---exactly (label-rootPORT-tabN). `label` is whatever command first spawned
---this tab's terminal ("claude" via <leader>ac, or the shell via <leader>at
----- see the comment on tab_claude above). Returns nil outside a root
---session, since without collaboration there's only ever this one Neovim
---instance and the local `alive` check already covers everything.
local function tmux_tab_session_name()
  if not vim.g.instant_root_port then
    return nil
  end
  local state = tab_claude[tab_id()]
  local label = state and state.cmd_label or "claude"
  return ("%s-root%s-tab%d"):format(label, tostring(vim.g.instant_root_port), tab_id())
end

---Retries the has-session/send-keys check instead of testing once and
---giving up immediately. A single immediate check has a real, confirmed
---timing race: if the OTHER window's <leader>ac was JUST pressed, its own
---termopen -> shell -> "tmux new-session" chain may not have finished
---creating the session yet -- an immediate check fails not because
---anything's misnamed (verified directly: root_port and tab_id match
---exactly between a host and its mirror when checked via RPC) but purely
---because the session doesn't exist YET. This is what "works, then
---randomly doesn't, for no apparent reason" actually was. ~3s of retrying
---(10 attempts, 300ms apart) covers that race without hanging indefinitely
---on a session that's genuinely never going to exist.
local function try_send_via_tmux(session, text, attempts_left, on_fail)
  vim.fn.system({ "tmux", "has-session", "-t", session })
  if vim.v.shell_error == 0 then
    vim.fn.system({ "tmux", "send-keys", "-t", session, "-l", text })
    vim.notify("Sent to this tab's terminal (open in another window)", vim.log.levels.INFO)
    return
  end
  if attempts_left > 0 then
    vim.defer_fn(function()
      try_send_via_tmux(session, text, attempts_left - 1, on_fail)
    end, 300)
  else
    on_fail()
  end
end

---Type text directly into THIS tab's terminal job (same effect as you typing
---it yourself -- works whether "claude" or a plain shell is running there,
---no MCP required). This is what keeps mention/send scoped to the Claude
---actually open in the current tab, unlike the <leader>aI* commands which
---can only ever reach the one singleton MCP review session.
---
---If THIS Neovim instance has no local window for the tab's terminal, that
---does NOT mean nothing is running for this tab -- under collaboration,
---another window sharing the same root session/tab may already have it open
---(same tmux session, per shared_terminal.lua). In that case the text is
---delivered straight into that shared session via tmux, and no window opens
---here: only the window that already has it visible shows any effect.
---<leader>ac/<leader>at are unaffected and still explicitly toggle/spawn a
---window in whichever terminal they're pressed in.
local function send_to_tab_terminal(text)
  local id = tab_id()
  local state = tab_claude[id]
  local alive = state and state.buf and vim.api.nvim_buf_is_valid(state.buf)

  if not alive then
    local session = tmux_tab_session_name()
    if session then
      try_send_via_tmux(session, text, 10, function()
        vim.notify("No Claude terminal in this tab yet (<leader>ac to start one)", vim.log.levels.WARN)
      end)
      return
    end
    vim.notify("No Claude terminal in this tab yet (<leader>ac to start one)", vim.log.levels.WARN)
    return
  end

  vim.fn.chansend(vim.b[state.buf].terminal_job_id, text)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
  else
    show_existing(state)
  end
  vim.cmd("startinsert")
end

return {
  "coder/claudecode.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {
    terminal = {
      split_side = "right",
      split_width_percentage = 0.35,
      git_repo_cwd = true,
    },
    diff = {
      layout = "vertical",
      keep_terminal_focus = false,
    },
  },
  cmd = {
    "ClaudeCode",
    "ClaudeCodeFocus",
    "ClaudeCodeSelectModel",
    "ClaudeCodeAdd",
    "ClaudeCodeSend",
    "ClaudeCodeTreeAdd",
    "ClaudeCodeStatus",
    "ClaudeCodeDiffAccept",
    "ClaudeCodeDiffDeny",
  },
  keys = {
    { "<leader>a", "", desc = "+ai", mode = { "n", "v" } },

    -- Everyday per-tab Claude (plain CLI, no MCP). Both converge on ONE
    -- terminal per tab (see open_tab_claude) -- they only differ in what
    -- gets run the first time that tab's terminal is created.
    { "<leader>ac", function() open_tab_claude("claude") end, desc = "Toggle this tab's Claude" },
    {
      "<leader>at",
      function()
        local shell = vim.fn.executable("fish") == 1 and "fish" or vim.o.shell
        open_tab_claude(shell)
      end,
      desc = "Toggle this tab's terminal (fish, cd + run claude manually)",
    },
    { "<leader>aw", toggle_tab_claude_layout, desc = "Toggle this tab's Claude: float <-> right split" },

    -- Mention/send scoped to THIS TAB's Claude (chansend, no MCP) -- unlike
    -- the <leader>aI* mention commands below, these follow whichever Claude
    -- is actually open in the current tab.
    {
      "<leader>al",
      function()
        local file = vim.fn.fnamemodify(vim.fn.expand("%:p"), ":.")
        send_to_tab_terminal(("@%s:%d "):format(file, vim.fn.line(".")))
      end,
      desc = "Mention current line to this tab's Claude",
    },
    {
      "<leader>aM",
      function()
        local file = vim.fn.fnamemodify(vim.fn.expand("%:p"), ":.")
        local mentioned = {}
        for i = string.byte("a"), string.byte("z") do
          local mark = string.char(i)
          local pos = vim.api.nvim_buf_get_mark(0, mark)
          if pos[1] > 0 then
            table.insert(mentioned, ("@%s:%d"):format(file, pos[1]))
          end
        end
        if #mentioned == 0 then
          vim.notify("No local marks (a-z) set in this buffer", vim.log.levels.WARN)
          return
        end
        send_to_tab_terminal(table.concat(mentioned, " ") .. " ")
      end,
      desc = "Mention all marked lines to this tab's Claude",
    },
    {
      "<leader>as",
      function()
        vim.cmd("normal! \27") -- leave visual mode so '< '> marks are set
        local s, e = vim.fn.line("'<"), vim.fn.line("'>")
        local file = vim.fn.fnamemodify(vim.fn.expand("%:p"), ":.")
        local lines = vim.api.nvim_buf_get_lines(0, s - 1, e, false)
        send_to_tab_terminal(("%s:%d-%d\n```\n%s\n```\n"):format(file, s, e, table.concat(lines, "\n")))
      end,
      mode = "v",
      desc = "Send visual selection to this tab's Claude",
    },

    -- MCP-integrated review session (shared, singleton, +ai review group)
    { "<leader>aI", "", desc = "+ai-review (mcp)", mode = { "n", "v" } },
    { "<leader>aIc", "<cmd>ClaudeCode<cr>", desc = "Toggle review session" },
    { "<leader>aIf", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus review session" },
    { "<leader>aIr", "<cmd>ClaudeCode --resume<cr>", desc = "Resume review session" },
    { "<leader>aIC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue review session" },
    { "<leader>aIm", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Select model" },
    { "<leader>aIb", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add current buffer as context" },
    -- Visual-mode ClaudeCodeSend removed: buggy against the singleton MCP
    -- session (targeted whatever review session existed, not predictably),
    -- and <leader>as (tab-scoped, chansend-based) does the same job better.
    { "<leader>aIs", "<cmd>ClaudeCodeTreeAdd<cr>", desc = "Add file from tree", ft = { "neo-tree", "oil" } },
    { "<leader>aIa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
    { "<leader>aId", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Reject diff" },
    {
      "<leader>aIl",
      function()
        local file = vim.fn.expand("%:p")
        local line = vim.fn.line(".")
        vim.cmd(("ClaudeCodeAdd %s %d %d"):format(vim.fn.fnameescape(file), line, line))
        vim.cmd("ClaudeCodeFocus")
      end,
      desc = "Mention current line",
    },
    {
      "<leader>aIM",
      function()
        local file = vim.fn.expand("%:p")
        local mentioned = {}
        for i = string.byte("a"), string.byte("z") do
          local mark = string.char(i)
          local pos = vim.api.nvim_buf_get_mark(0, mark)
          if pos[1] > 0 then
            vim.cmd(("ClaudeCodeAdd %s %d %d"):format(vim.fn.fnameescape(file), pos[1], pos[1]))
            table.insert(mentioned, mark .. ":" .. pos[1])
          end
        end
        if #mentioned > 0 then
          vim.notify("Mentioned marks -> " .. table.concat(mentioned, ", "))
          vim.cmd("ClaudeCodeFocus")
        else
          vim.notify("No local marks (a-z) set in this buffer", vim.log.levels.WARN)
        end
      end,
      desc = "Mention all marked lines",
    },
    {
      "<leader>aID",
      function()
        vim.ui.input({
          prompt = "Spin review session in dir: ",
          default = vim.fn.getcwd() .. "/",
          completion = "dir",
        }, function(dir)
          if not dir or dir == "" then
            return
          end
          dir = vim.fn.fnamemodify(vim.fn.expand(dir), ":p")
          local bufnr = require("claudecode.terminal").get_active_terminal_bufnr()
          if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
          end
          vim.cmd("cd " .. vim.fn.fnameescape(dir))
          vim.cmd("ClaudeCode")
        end)
      end,
      desc = "Spin review session in a directory",
    },
    {
      "<leader>aIw",
      function()
        local term = require("claudecode.terminal")
        vim.g.claude_review_floating = not vim.g.claude_review_floating
        term.close()
        term.open(
          vim.g.claude_review_floating
              and { snacks_win_opts = { position = "float", width = 0.85, height = 0.85, border = "rounded" } }
            or { snacks_win_opts = {} }
        )
      end,
      desc = "Toggle review session: float <-> right split",
    },
  },
  config = function(_, opts)
    require("claudecode").setup(opts)

    -- Auto-enter insert mode whenever you land in the MCP review terminal
    -- window, however you got there, so jumping back in drops you straight
    -- into typing. (snacks.nvim's `interactive` default already does this
    -- for the per-tab terminals above.)
    vim.api.nvim_create_autocmd("TermOpen", {
      pattern = "*",
      callback = function(args)
        if vim.api.nvim_buf_get_name(args.buf):match("claude") then
          vim.api.nvim_create_autocmd("WinEnter", {
            buffer = args.buf,
            callback = function()
              vim.cmd("startinsert")
            end,
          })
        end
      end,
    })
  end,
}
