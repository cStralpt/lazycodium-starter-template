-- Ordered, toggle-based "send marks" for sending code to a Claude agent.
--
-- Lives in its own module rather than inside plugins/claude-code.lua so that
-- binding <leader>mm / <leader>aM does not drag coder/claudecode.nvim in with
-- it. Nothing here touches that plugin -- the marks are plain extmarks and the
-- send goes through util/claude_agents.lua -- and every key that loaded it
-- unnecessarily paid lazy.nvim's load-and-replay dance on first press.

local M = {}

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

function M.toggle()
  local buf = vim.api.nvim_get_current_buf()
  local line0 = vim.fn.line(".") - 1
  local marked = toggle_mark_line(buf, line0)
  local count = #(send_marks[buf] or {})
  vim.notify(("%s line %d (%d marked)"):format(marked and "Marked" or "Unmarked", line0 + 1, count))
end

---Visual-mode counterpart: toggles every line in the selection, so marking
---a block you just selected doesn't require repeating <leader>mm per line.
function M.toggle_visual()
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
function M.lines(buf)
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

function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf, send_marks_ns, 0, -1)
  send_marks[buf] = {}
end

---Builds the same "file:start-end" + fenced-code-block format <leader>as
---sends, one block per contiguous run of marked lines -- so three marks in
---a row become one 391-393 block with the real code, not three separate
---single-line mentions.
function M.blocks(buf, lines)
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


return M
