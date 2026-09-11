-- The <C-/> floating terminal: one instance of util/tmux_workspace.lua.
--
-- Everything this file used to implement -- session grouping for
-- collaboration, the <leader>iss workspace hand-off, clickable rainbow pills,
-- <C-hjkl> pane navigation, the reopen resize nudge -- now lives in that
-- factory, unchanged, because util/claude_agents.lua needed the identical
-- behaviour for its Claude workspace and having two copies meant every future
-- fix landing in only one of them.
--
-- Session names are preserved EXACTLY as they were ("nvim-float-<pid>" outside
-- collaboration, "floatterm-root<port>" inside it). They are not cosmetic:
-- adopt_workspace() renames the first into the second on <leader>iss, so a
-- changed prefix would make a live workspace unreachable at exactly the moment
-- it matters most.
local fish = vim.fn.exepath("fish")
if fish == "" then
  fish = vim.o.shell
end

-- Declared before the call, not as `local W = ...`: the `keys` closure below
-- names W, and a local only exists AFTER the statement that declares it -- so
-- inside its own initializer the name was the global W, which is nil.
local W
W = require("util.tmux_workspace").new({
  id = "FloatingTerm",
  what = "terminal float",
  local_prefix = "nvim-float",
  root_prefix = "floatterm",
  cmd = fish,
  -- The terminal workspace, and only it, sets tmux's GLOBAL default-shell and
  -- default-command, so a bare `new-window` from a grouped collaborator
  -- session still gets fish (a session-scoped option does not propagate into a
  -- session group -- verified: it fell back to bash).
  set_global_shell = true,
  -- Don't leak the workspace on exit. Outside collaboration the pid-keyed
  -- session is in owned_sessions and dies with this Neovim anyway, so this
  -- changes nothing there. While collaborating it is the ONLY thing that
  -- reaps "floatterm-root<port>": that name is shared, so it is deliberately
  -- never owned by any single instance, and it was surviving every window
  -- that ever used it -- leaving dev servers (`pnpm start` and friends)
  -- running in detached panes until the machine rebooted. kill_when_last
  -- refcounts by attached client and view session, reaping stale pids, so
  -- the workspace only goes once no collaborator is left in it.
  kill_when_last = true,
  float = { width = 0.97, height = 0.95 },
  missing_msg = "No floating terminal yet (<C-/> to start one)",
  -- `-` opens oil everywhere else; here it opens oil to pick where THIS pane's
  -- shell should cd (W.browse_dir below). Bound on the float's own buffers like
  -- the editor mirrors, so the global oil `-` never runs inside the float
  -- window again -- that swapped the terminal out for a listing.
  keys = {
    {
      "-",
      function()
        W.browse_dir()
      end,
      "browse for a directory to cd this pane to",
    },
  },
})

---Shells that can take a typed `cd`. Anything else in the foreground -- a dev
---server, an editor, a REPL -- would get the text as input, so the browser
---refuses rather than types into it.
local SHELLS = { fish = true, bash = true, zsh = true, sh = true, nu = true }

---`-` inside the terminal float: pick a directory with oil (util/dir_browser
---.lua) and cd the focused pane's shell there. A cd, not a respawn: the Claude
---workspace restarts its pane because an agent's directory is fixed at start,
---but a shell just changes directory, and respawning would kill whatever the
---pane was running.
function W.browse_dir()
  local pane
  for _, p in ipairs(W.list_panes()) do
    if p.active then
      pane = p
    end
  end
  if not pane then
    vim.notify("No floating terminal yet (<C-/> to start one)", vim.log.levels.WARN)
    return
  end
  local running =
    vim.trim(vim.fn.system({ "tmux", "display-message", "-p", "-t", pane.pane, "#{pane_current_command}" }))
  if not SHELLS[running] then
    vim.notify(("This pane is running %s, not a shell -- nowhere to type a cd"):format(running), vim.log.levels.WARN)
    return
  end
  W.dismiss_scrollback()
  require("util.dir_browser").open({
    start = pane.cwd ~= "" and pane.cwd or LazyVim.root(),
    region = W.pane_region(),
    label = "terminal pane",
    verb = "cd here",
    on_choose = function(dir)
      vim.fn.system({ "tmux", "send-keys", "-t", pane.pane, "cd " .. vim.fn.shellescape(dir), "Enter" })
      W.refresh_indicator()
    end,
  })
end

return W
