-- The MCP-integrated review session, and nothing else.
--
-- coder/claudecode.nvim can hold only ONE live MCP connection per Neovim
-- process (one WebSocket server, one lock file) -- a hard architectural limit
-- of the plugin, not a config choice. So it stays a single shared session under
-- the <leader>aI prefix, giving inline diff accept/reject and the
-- ClaudeCodeAdd-based mention commands.
--
-- The everyday agent keys (<leader>ac/aV/an/ao/af/am/az/ax and the sends) are
-- NOT here, deliberately. They use util/claude_agents.lua and tmux and touch
-- this plugin nowhere -- but while they lived in this spec's `keys` table they
-- were lazy TRIGGERS for it, so every <leader>a ran lazy.nvim's stub, loaded
-- this plugin, registered 31 mappings and replayed the pending keys before
-- anything happened. That, plus a `{ "<leader>a", "" }` group entry which made
-- <leader>a a COMPLETE mapping as well as a prefix (forcing a full
-- timeoutlen=300ms disambiguation wait on every press), is why <leader>a felt
-- laggy no matter which key followed it. They are plain, eager mappings in
-- config/keymaps.lua now.

local M = {
  "coder/claudecode.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {
    -- Every session this plugin spawns skips permission prompts, matching the
    -- tmux workspace agents (util/claude_agents.lua). Only affects Claudes
    -- started from Neovim.
    terminal_cmd = "claude --dangerously-skip-permissions",
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
    { "<leader>aI", "", desc = "+ai-review (mcp)", mode = { "n", "v" } },
    { "<leader>aIc", "<cmd>ClaudeCode<cr>", desc = "Toggle review session" },
    { "<leader>aIf", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus review session" },
    { "<leader>aIr", "<cmd>ClaudeCode --resume<cr>", desc = "Resume review session" },
    { "<leader>aIC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue review session" },
    { "<leader>aIm", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Select model" },
    { "<leader>aIb", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add current buffer as context" },
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
        local marks = require("util.send_marks")
        local buf = vim.api.nvim_get_current_buf()
        local file = vim.fn.expand("%:p")
        local lines = marks.lines(buf)
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
        marks.clear(buf)
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

return M
