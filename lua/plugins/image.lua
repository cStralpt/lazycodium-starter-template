-- Inline image rendering, in the terminal only. `foot` (your terminal)
-- supports the Sixel graphics protocol, not Kitty's -- and this only works
-- in a real terminal at all, since sixel/kitty are escape codes a terminal
-- emulator interprets; Neovide is a GUI client that never sees them, so the
-- plugin is disabled there instead of silently doing nothing/erroring.
return {
  "3rd/image.nvim",
  cond = not vim.g.neovide,
  build = false, -- shell out to the `magick` CLI directly; no luarocks needed
  -- No lazy-load trigger on purpose: hijack_file_patterns below needs the
  -- plugin loaded BEFORE an image file's buffer is created, and a plain
  -- .png/.jpg has no filetype for an `ft=` trigger to match.
  opts = {
    backend = "sixel",
    processor = "magick_cli",
    integrations = {
      markdown = {
        enabled = true,
        download_remote_images = true,
        only_render_image_at_cursor = false,
        filetypes = { "markdown" },
      },
    },
    max_height_window_percentage = 50,
    -- Some remote images (e.g. GitHub user-attachment links) 403/404 a bare
    -- curl outside a browser session. Fail quietly instead of throwing a
    -- disruptive error popup -- local images still render fine either way.
    ignore_download_error = true,
    -- Opening an image file directly renders it instead of showing raw bytes.
    hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif", "*.svg" },
    -- Sixel has no z-order: it paints pixels straight onto the terminal, on
    -- top of whatever's already drawn there, so a floating window (a
    -- notification, LSP hover, ...) that overlaps an image gets painted over
    -- instead of staying on top of it. window_overlap_clear_enabled makes
    -- image.nvim mask out the overlapped region instead of drawing through
    -- it. It's ignored for `snacks_notif` by upstream default (presumably to
    -- skip recompute cost for a filetype they didn't expect to collide with
    -- images) -- drop that exclusion since Big File / other snacks
    -- notifications are exactly the case that was corrupting images here.
    window_overlap_clear_enabled = true,
    window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "scrollview", "scrollview_sign" },
  },
  config = function(_, opts)
    require("image").setup(opts)
    -- Exported SVGs are usually minified onto one giant line, which trips
    -- snacks.nvim's bigfile heuristic (avg line length > 1000) even when the
    -- file itself is tiny -- a spurious "Big File" notification on top of a
    -- correctly-sized image. An `extension` match always wins over snacks'
    -- `pattern` match regardless of load order, so this keeps .svg out of
    -- the bigfile path entirely.
    vim.filetype.add({ extension = { svg = "svg" } })

    -- Masking (above) stops an overlapping window from corrupting the
    -- image, but nothing in image.nvim proactively redraws the region once
    -- that window closes and the mask goes away -- its own WinClosed
    -- handler only ever clears, never re-renders. Do that redraw ourselves.
    -- Deliberately NOT clearing first: Image:render() already clears
    -- internally when it decides not to draw (e.g. still masked), and
    -- pre-clearing here raced with image.nvim's own WinClosed handler and
    -- left images permanently blank. The 50ms delay lets that handler (a
    -- vim.schedule callback, so it runs on the next tick) settle first, so
    -- our render() is the last word.
    vim.api.nvim_create_autocmd("WinClosed", {
      group = vim.api.nvim_create_augroup("image_rerender_on_win_close", { clear = true }),
      callback = function()
        vim.defer_fn(function()
          for _, img in ipairs(require("image").get_images()) do
            img:render()
          end
        end, 50)
      end,
    })
  end,
}
