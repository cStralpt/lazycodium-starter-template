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

return require("util.tmux_workspace").new({
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
})
