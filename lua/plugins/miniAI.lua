return {
  "echasnovski/mini.ai",
  opts = function(_, opts)
    opts.custom_textobjects = {
      t = false, -- fallback to neovim for tags
    }
  end,
}
