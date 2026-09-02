-- Colorizes LazyVim's default `lualine_c` (the left breadcrumb: root dir >
-- filetype icon > path > LSP symbol) so each segment reads as its own thing
-- instead of one undifferentiated gray run. Colors come from the same
-- tokyonight-moon pastels as the tabline chips (util/rainbow_tabs.lua), five
-- of which are lualine's own mode-section colors -- so the breadcrumb matches
-- the intensity of the mode block at the far left rather than inventing a
-- second palette.
local rainbow = require("util.rainbow_tabs")

-- Named groups rather than inline colors because that's the only interface
-- LazyVim.lualine.pretty_path() offers: it takes highlight group NAMES
-- (directory_hl/filename_hl/modified_hl) and pulls fg + bold/italic off them
-- via extract_highlight_colors. Background is ignored on that path, which is
-- fine -- this is colored text on the statusline's own background, not pills.
local HLS = {
  -- Blue = lualine's NORMAL mode color, tying the project root to the
  -- calmest/most permanent thing on the line.
  LualineRootDir = { fg = rainbow.accents[5] },
  -- The directory prefix is context, not the subject -- same muted gray as an
  -- inactive tab label, so the filename after it is what the eye lands on.
  LualineDir = { fg = nil, muted = true },
  -- Magenta = lualine's VISUAL color. The filename is the single most
  -- important item in this section, so it gets the boldest treatment.
  LualineFile = { fg = rainbow.accents[4], bold = true },
  -- Yellow = lualine's COMMAND color, reused as "unsaved". Warm and
  -- attention-getting without being an error red.
  LualineModified = { fg = rainbow.accents[6], bold = true },
  -- Green for the LSP symbol, deliberately the furthest hue from the
  -- filename's magenta so the two halves of the breadcrumb don't blur
  -- together.
  LualineSymbol = { fg = rainbow.accents[3] },
}

-- NORMAL mode's block color, replacing the blue (#82aaff) tokyonight's lualine
-- theme ships. Pink is the only accent at this pastel level that no mode has
-- already claimed: tokyonight defines all six mode slots, and teal -- the
-- obvious "better than blue" pick -- is already TERMINAL (#4fd6be), so using
-- it would have made normal and terminal indistinguishable. Also keeps clear
-- of the blue still used by the root-dir segment further along the same line.
--
--   insert #c3e88d · visual #c099ff · replace #ff757f
--   command #ffc777 · terminal #4fd6be · normal #fca7ea (this)
local MODE_NORMAL = rainbow.accents[1]

local function define_hls()
  local base = rainbow.base_bg()
  for name, def in pairs(HLS) do
    vim.api.nvim_set_hl(0, name, {
      fg = def.muted and rainbow.blend("#ffffff", base, 0.45) or def.fg,
      bold = def.bold,
    })
  end
end

return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    define_hls()
    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = function()
        vim.schedule(define_hls)
      end,
    })

    -- Recolor NORMAL mode. Resolved from the active colorscheme's own lualine
    -- theme (falling back to "auto", which derives one from the current
    -- highlights) and deep-copied before mutating -- the theme table is the
    -- module's shared state, so editing it in place would leak into anything
    -- else that requires it.
    local ok, theme = pcall(require, "lualine.themes." .. (vim.g.colors_name or ""))
    if not ok then
      theme = require("lualine.themes.auto")
    end
    theme = vim.deepcopy(theme)
    theme.normal.a.bg = MODE_NORMAL
    opts.options = opts.options or {}
    opts.options.theme = theme

    local icons = LazyVim.config.icons

    -- Rebuilt wholesale rather than patched by index. LazyVim appends the
    -- trouble symbols component conditionally, so positions shift depending
    -- on whether trouble is installed -- indexing into the list would be a
    -- silent mis-color the day that changes.
    opts.sections.lualine_c = {
      LazyVim.lualine.root_dir({
        color = function()
          return { fg = rainbow.accents[5] }
        end,
      }),
      {
        "diagnostics",
        symbols = {
          error = icons.diagnostics.Error,
          warn = icons.diagnostics.Warn,
          info = icons.diagnostics.Info,
          hint = icons.diagnostics.Hint,
        },
      },
      -- Left as-is: `icon_only` already renders in the filetype's own
      -- mini.icons color, so it's the one segment that was never gray.
      { "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
      {
        LazyVim.lualine.pretty_path({
          directory_hl = "LualineDir",
          filename_hl = "LualineFile",
          modified_hl = "LualineModified",
        }),
      },
    }

    -- Re-add trouble's symbol breadcrumb with our own group. LazyVim hardcodes
    -- `{symbol.name:Normal}` and `hl_group = "lualine_c_normal"`, which is
    -- exactly why that tail rendered in plain statusline gray; the `:Group`
    -- suffix inside trouble's format string is what actually paints the
    -- symbol name.
    if vim.g.trouble_lualine and LazyVim.has("trouble.nvim") then
      local symbols = require("trouble").statusline({
        mode = "symbols",
        groups = {},
        title = false,
        filter = { range = true },
        format = "{kind_icon}{symbol.name:LualineSymbol}",
        hl_group = "lualine_c_normal",
      })
      table.insert(opts.sections.lualine_c, {
        symbols and symbols.get,
        cond = function()
          return vim.b.trouble_lualine ~= false and symbols.has()
        end,
      })
    end

    return opts
  end,
}
