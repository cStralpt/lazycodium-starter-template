-- The collaboration layer's own magic for terminals: transparently makes
-- ANY :terminal spawned anywhere (Claude, a plain shell, whatever) mirror
-- across collaborative windows, without the feature that spawned it ever
-- knowing collaboration exists. No plugin calls into this file -- it patches
-- vim.fn.termopen itself once, and every call to it (from any plugin,
-- present or future) goes through the wrapping automatically.
--
-- Scope is (root session port, tab number, the command being run):
--   - no root session active (vim.g.instant_root_port unset -- collaboration
--     never touched) -> termopen is left COMPLETELY untouched, not even
--     wrapped through tmux. Normal, non-collaborative usage is 100%
--     unaffected: no tmux dependency, no indirection, identical to before
--     this file existed.
--   - root session active + matching tab NUMBER in another window in that
--     SAME root session -> shared tmux session, so whatever's running
--     mirrors live across those windows. Tab number is the only
--     correspondence available across windows, since instant.nvim doesn't
--     sync tab/window layout, only file buffer content.
--   - root session active, different tab -> a DIFFERENT tmux session: tabs
--     stay independent even while collaborating, only matching tabs mirror.
--   - the command itself is also part of the key, so two DIFFERENT commands
--     opened in the same tab (e.g. "claude" and "fish") don't collide into
--     one tmux session.
local M = {}

local function tab_id()
  return vim.api.nvim_tabpage_get_number(0)
end

local function wrap(cmd, cwd)
  cwd = cwd or vim.fn.getcwd(0)
  local label = tostring(cmd):match("^%S+") or "term"
  local name = ("%s-root%s-tab%d"):format(label, tostring(vim.g.instant_root_port), tab_id())
  return string.format(
    "tmux has-session -t %s 2>/dev/null || tmux new-session -d -s %s -c %s %s; tmux attach -t %s",
    name,
    name,
    vim.fn.shellescape(cwd),
    cmd,
    name
  )
end

local installed = false

---Patches vim.fn.termopen so every terminal spawned anywhere automatically
---mirrors across collaborative windows once a root session exists.
---Idempotent -- safe to call more than once. Requires tmux
---(`!paru -S tmux` if not installed) for the mirroring itself to work; with
---no root session active this never touches tmux at all.
function M.install()
  if installed then
    return
  end
  installed = true

  local original_termopen = vim.fn.termopen
  vim.fn.termopen = function(cmd, opts)
    -- Only string commands are wrapped (tmux needs one shell command line);
    -- table-form argv commands pass through untouched, and so does anything
    -- run outside a root session -- both cases behave exactly as if this
    -- patch didn't exist.
    if vim.g.instant_root_port and type(cmd) == "string" then
      cmd = wrap(cmd, opts and opts.cwd)
    end
    -- vim.fn.termopen(cmd, nil) is NOT the same call as vim.fn.termopen(cmd)
    -- -- passing an explicit nil second argument through to the VimL bridge
    -- errors with "E475: Invalid argument: expected dictionary" instead of
    -- being treated as "no opts given". Every plain termopen(cmd) call
    -- (common -- e.g. Snacks.terminal, or claude-code.lua's own spawn_new)
    -- would break the instant this patch installed, even with no root
    -- session active, if opts were forwarded unconditionally.
    if opts ~= nil then
      return original_termopen(cmd, opts)
    end
    return original_termopen(cmd)
  end
end

return M
