-- Claude Code inside Neovim -- two separate mechanisms, on purpose:
--
-- 1. Everyday agents (<leader>a...): N concurrent plain `claude` CLI
--    processes, held in util/claude_agents.lua. Identity used to be the
--    Neovim TAB NUMBER, which is why <leader>as / <leader>aM / <leader>al
--    could only ever reach one Claude and did nothing at all from a Claude
--    running in the <C-/> tmux float. It's now an explicit slot, with one
--    "focused" agent that every send targets by default -- shared across
--    collaborating windows, so focusing an agent in one window makes
--    <leader>as land there from any other window too.
--
-- 2. The MCP-integrated review session (<leader>aI...): coder/claudecode.nvim
--    can only ever hold ONE live MCP connection per Neovim process (one
--    WebSocket server, one lock file) -- a hard architectural limit of the
--    plugin, not a config choice. So it stays a single shared session under
--    its own prefix, giving you inline diff accept/reject and the
--    ClaudeCodeAdd-based mention commands whenever you deliberately want that
--    deeper review workflow, separate from the quick per-agent chats.

local agents = require("util.claude_agents")

-- Ordered, toggle-based "send marks" -- one key (<leader>mm) toggles the
-- current line in/out of a per-buffer list, shown live via a sign-column
-- marker (extmarks track the line even if you edit above it). No letters
-- to remember, no name collisions; <leader>aM/<leader>aIM send the list in
-- the order lines were added, then clear it.
local send_marks_ns = vim.api.nvim_create_namespace("claude_send_marks")
vim.api.nvim_set_hl(0, "ClaudeSendMark", { link = "DiagnosticSignInfo", default = true })

---send_marks[bufnr] = { extmark_id, ... } in insertion order.
local send_marks = {}

---Toggles a single 0-indexed line's mark on/off. Returns true if it ended
---up marked, false if it was unmarked. Shared by the normal- and
---visual-mode entry points below.
local function toggle_mark_line(buf, line0)
  local ids = send_marks[buf] or {}
  send_marks[buf] = ids

  for idx, id in ipairs(ids) do
    local pos = vim.api.nvim_buf_get_extmark_by_id(buf, send_marks_ns, id, {})
    if pos[1] == line0 then
      vim.api.nvim_buf_del_extmark(buf, send_marks_ns, id)
      table.remove(ids, idx)
      return false
    end
  end

  local id = vim.api.nvim_buf_set_extmark(buf, send_marks_ns, line0, 0, {
    sign_text = "»",
    sign_hl_group = "ClaudeSendMark",
  })
  table.insert(ids, id)
  return true
end

local function toggle_send_mark()
  local buf = vim.api.nvim_get_current_buf()
  local line0 = vim.fn.line(".") - 1
  local marked = toggle_mark_line(buf, line0)
  local count = #(send_marks[buf] or {})
  vim.notify(("%s line %d (%d marked)"):format(marked and "Marked" or "Unmarked", line0 + 1, count))
end

---Visual-mode counterpart: toggles every line in the selection, so marking
---a block you just selected doesn't require repeating <leader>mm per line.
local function toggle_send_mark_visual()
  vim.cmd("normal! \27") -- leave visual mode so '< '> marks are set
  local buf = vim.api.nvim_get_current_buf()
  local s, e = vim.fn.line("'<") - 1, vim.fn.line("'>") - 1
  for line0 = s, e do
    toggle_mark_line(buf, line0)
  end
  local count = #(send_marks[buf] or {})
  vim.notify(("Toggled lines %d-%d (%d marked)"):format(s + 1, e + 1, count))
end

---Returns 1-indexed line numbers in insertion order. Reads extmark
---positions live, so lines shifted by edits since marking still resolve
---correctly.
local function get_send_mark_lines(buf)
  local ids = send_marks[buf]
  if not ids or #ids == 0 then
    return {}
  end
  local lines = {}
  for _, id in ipairs(ids) do
    local pos = vim.api.nvim_buf_get_extmark_by_id(buf, send_marks_ns, id, {})
    if pos[1] then
      table.insert(lines, pos[1] + 1)
    end
  end
  return lines
end

local function clear_send_marks(buf)
  vim.api.nvim_buf_clear_namespace(buf, send_marks_ns, 0, -1)
  send_marks[buf] = {}
end

---Builds the same "file:start-end" + fenced-code-block format <leader>as
---sends, one block per contiguous run of marked lines -- so three marks in
---a row become one 391-393 block with the real code, not three separate
---single-line mentions.
local function build_marked_blocks(buf, lines)
  local file = vim.fn.fnamemodify(vim.fn.expand("%:p"), ":.")
  local sorted = {}
  for _, line in ipairs(lines) do
    table.insert(sorted, line)
  end
  table.sort(sorted)

  local parts = {}
  local i = 1
  while i <= #sorted do
    local s = sorted[i]
    local e = s
    while sorted[i + 1] == e + 1 do
      e = sorted[i + 1]
      i = i + 1
    end
    local content = vim.api.nvim_buf_get_lines(buf, s - 1, e, false)
    table.insert(parts, ("%s:%d-%d\n```\n%s\n```"):format(file, s, e, table.concat(content, "\n")))
    i = i + 1
  end
  return table.concat(parts, "\n") .. "\n"
end

local M = {
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

    -- The Claude workspace: agents are tmux PANES, groups are tmux windows.
    -- These mirror the <leader>t* terminal bindings one for one, so there is
    -- no second vocabulary to learn -- if you know <leader>tn/ts/tv/t]/tx for
    -- the <C-/> float, you already know these.
    { "<leader>ac", agents.toggle, desc = "Toggle the Claude workspace" },
    { "<leader>an", agents.new_group, desc = "Claude: new group (claude tab)" },
    { "<leader>ao", agents.split_below, desc = "Claude: another agent below" },
    { "<leader>aV", agents.split_right, desc = "Claude: another agent right" },
    { "<leader>a]", agents.next_group, desc = "Claude: next group" },
    { "<leader>a[", agents.prev_group, desc = "Claude: prev group" },
    { "<leader>ax", agents.close_agent, desc = "Claude: close this agent" },
    -- Hide every other agent in this group, and press again to bring them all
    -- back. tmux's own zoom, so nothing is lost and the layout is restored
    -- exactly; the group's pill is marked while zoomed so hidden agents are
    -- never invisible state.
    { "<leader>az", agents.zoom, desc = "Claude: show only this agent (zoom)" },
    { "<leader>af", agents.pick, desc = "Claude: pick an agent" },
    -- Move this agent to another group. Bare = a picker of every group, named
    -- by the project it holds, plus "new group of its own" -- so breaking out
    -- doesn't need a key of its own. With a count (2<leader>am) it goes
    -- straight to group 2, read off the winbar pills.
    { "<leader>am", function() agents.move_to_group(vim.v.count) end, desc = "Claude: move agent to a group" },

    -- Sends go to the FOCUSED agent -- which is simply tmux's active pane, so
    -- it's whichever one you last touched, and two Neovim windows looking at
    -- the same group already agree on it. Every send takes an optional COUNT
    -- as an accelerator, read off the statusline pill rather than memorised:
    -- `2<leader>as` delivers to agent 2 without moving focus, so you can nudge
    -- another agent mid-thought and stay where you are.
    {
      "<leader>al",
      function()
        local file = vim.fn.fnamemodify(vim.fn.expand("%:p"), ":.")
        agents.send(("@%s:%d "):format(file, vim.fn.line(".")), vim.v.count)
      end,
      desc = "Mention current line to the focused Claude",
    },
    {
      "<leader>aM",
      function()
        local buf = vim.api.nvim_get_current_buf()
        local count = vim.v.count
        local lines = get_send_mark_lines(buf)
        if #lines == 0 then
          vim.notify("No marked lines in this buffer (<leader>mm to mark)", vim.log.levels.WARN)
          return
        end
        agents.send(build_marked_blocks(buf, lines), count, function()
          clear_send_marks(buf)
        end)
      end,
      desc = "Send all marked lines to the focused Claude",
    },
    {
      "<leader>as",
      function()
        local count = vim.v.count
        vim.cmd("normal! \27") -- leave visual mode so '< '> marks are set
        local s, e = vim.fn.line("'<"), vim.fn.line("'>")
        local file = vim.fn.fnamemodify(vim.fn.expand("%:p"), ":.")
        local lines = vim.api.nvim_buf_get_lines(0, s - 1, e, false)
        agents.send(("%s:%d-%d\n```\n%s\n```\n"):format(file, s, e, table.concat(lines, "\n")), count)
      end,
      mode = "v",
      desc = "Send visual selection to the focused Claude",
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
        local buf = vim.api.nvim_get_current_buf()
        local file = vim.fn.expand("%:p")
        local lines = get_send_mark_lines(buf)
        if #lines == 0 then
          vim.notify("No marked lines in this buffer (<leader>mm to mark)", vim.log.levels.WARN)
          return
        end
        local mentioned = {}
        for _, line in ipairs(lines) do
          local ok = pcall(vim.cmd, ("ClaudeCodeAdd %s %d %d"):format(vim.fn.fnameescape(file), line, line))
          if not ok then
            vim.notify("Failed to mention line " .. line .. " (marks left intact)", vim.log.levels.WARN)
            return
          end
          table.insert(mentioned, tostring(line))
        end
        clear_send_marks(buf)
        vim.notify("Mentioned lines -> " .. table.concat(mentioned, ", "))
        vim.cmd("ClaudeCodeFocus")
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
    agents.setup()

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

table.insert(M.keys, { "<leader>mm", toggle_send_mark, mode = "n", desc = "Toggle send-mark on this line" })
table.insert(
  M.keys,
  { "<leader>mm", toggle_send_mark_visual, mode = "v", desc = "Toggle send-mark on selected lines" }
)
table.insert(M.keys, {
  "<leader>mc",
  function()
    clear_send_marks(vim.api.nvim_get_current_buf())
    vim.notify("Cleared all send marks in this buffer")
  end,
  desc = "Clear all send marks",
})

return M
