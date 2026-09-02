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
-- using the CURRENT process's cwd.
--
-- Note the two cwds are DIFFERENT cwds, and that matters: the encoding
-- happens on the SENDER, the resolution on the RECEIVER. Deriving both
-- from the receiver's own cwd (as this used to) is only correct while the
-- two happen to match -- true for the auto-spawned mirror window (foot -D
-- gives it the host's cwd), not for a manual <leader>isj/picker join, nor
-- for a host that has :cd'd since. When they differ the prediction is
-- wrong in BOTH directions (e.g. sender cwd /a/b sends "x.ts" -> receiver
-- with cwd /a really gets /a/x.ts, while a receiver-derived prediction
-- says /a/b/x.ts), so the polling lookups in instant.lua and
-- shared_tabs.lua simply never find the buffer and time out: the file
-- silently never appears in that window. Callers that know the sender's
-- cwd should pass it.
local M = {}

---@param file string absolute path, as recorded by the SENDER
---@param sender_cwd string? the sender's cwd at the time it shared `file`;
---omitted falls back to this process's own cwd, i.e. the old
---"assume both ends match" behaviour.
function M.expected_bufname(file, sender_cwd)
  if file == nil or file == "" then
    return nil
  end
  local sent
  if sender_cwd and sender_cwd ~= "" then
    -- fnamemodify(file, ":.") against an EXPLICIT cwd rather than this
    -- process's -- fnamemodify itself has no way to be told which cwd to
    -- shorten against, so the prefix test is done by hand.
    local prefix = sender_cwd:gsub("/+$", "") .. "/"
    sent = vim.startswith(file, prefix) and file:sub(#prefix + 1) or vim.fn.fnamemodify(file, ":t")
  else
    local cwdname = vim.fn.fnamemodify(file, ":.")
    sent = (cwdname == file) and vim.fn.fnamemodify(file, ":t") or cwdname
  end
  return vim.fn.fnamemodify(sent, ":p")
end

---The buffer instant.nvim created for `file` on THIS side of a sync, or nil
---if it hasn't arrived (or can't be identified unambiguously).
---
---Session membership is scoped by session id (the root port) and nothing
---else -- cwd has no business deciding whether two windows see the same
---file. It only leaks in here because instant.nvim's wire format carries a
---cwd-relative-or-basename STRING as the buffer's name rather than any
---stable id, so the receiving side has to work out which local buffer that
---string became. expected_bufname() models that encoding exactly and is
---the precise answer whenever the sender's cwd is known.
---
---The basename fallback covers the cases where it ISN'T known or has since
---changed -- a manual <leader>isj from an unrelated directory, a host that
---:cd'd after hosting, an event logged by a third window -- so a cwd
---mismatch degrades to "still found" instead of the old "silently never
---found, buffer never displayed, no error". Ambiguity is not guessed at: if
---two open buffers share the basename, this returns nil and the caller
---keeps polling rather than displaying the wrong file.
function M.find_synced_buf(file, sender_cwd)
  if file == nil or file == "" then
    return nil
  end
  local expected = M.expected_bufname(file, sender_cwd)
  local want = vim.fn.fnamemodify(file, ":t")
  local by_basename = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if expected and name == expected then
        return buf
      end
      if name ~= "" and vim.fn.fnamemodify(name, ":t") == want then
        table.insert(by_basename, buf)
      end
    end
  end
  return #by_basename == 1 and by_basename[1] or nil
end

return M
