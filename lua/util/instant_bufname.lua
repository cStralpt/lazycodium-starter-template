-- Predicts the buffer name instant.nvim actually gives a synced file on the
-- RECEIVING side of a sync -- shared by lua/plugins/instant.lua and
-- lua/util/shared_tabs.lua so both use one correct source of truth instead
-- of two copies that can drift.
--
-- instant.lua (the third-party plugin) does NOT send the original absolute
-- path over the wire. It computes fnamemodify(file, ':.') (cwd-relative);
-- if that doesn't shorten anything (the file is OUTSIDE the sender's cwd),
-- it falls back to just the bare basename ':t', losing the directory
-- entirely. The receiving side then calls nvim_buf_set_name() with
-- whatever string it got, which Neovim normalizes to an ABSOLUTE path
-- resolved against the RECEIVER's own cwd (confirmed directly: setting a
-- scratch buffer's name to "lazy-lock.json" from cwd /tmp reads back as
-- "/tmp/lazy-lock.json", never the relative string).
--
-- An earlier version of this logic assumed that round-trip always lands
-- back on the ORIGINAL absolute path -- true only when the file happens to
-- be inside the cwd. Outside it (the common case: a shell's cwd rarely
-- matches whatever file you're editing), the actual result is
-- `receiver_cwd/basename`, not the original path -- so matching against
-- the original path just never finds anything, silently.
--
-- This predicts the ACTUAL result by replaying the exact same
-- cwd-relative-or-basename encoding, then resolving it back to absolute
-- using the CURRENT process's cwd. That's only correct when sender and
-- receiver share a cwd -- true for the auto-spawned mirror window
-- (jobstart inherits the host's cwd by default), not guaranteed for a
-- manually-run <leader>isj/picker join from an unrelated cwd.
local M = {}

function M.expected_bufname(file)
  if file == "" then
    return nil
  end
  local cwdname = vim.fn.fnamemodify(file, ":.")
  local sent = cwdname
  if cwdname == file then
    sent = vim.fn.fnamemodify(file, ":t")
  end
  return vim.fn.fnamemodify(sent, ":p")
end

return M
