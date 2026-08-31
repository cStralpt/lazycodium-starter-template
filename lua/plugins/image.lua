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
    hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.avif" },
  },
}
