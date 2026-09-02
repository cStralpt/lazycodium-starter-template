-- Two things live here:
--
-- 1. `custom_areas.right` -- replaces bufferline's plain "1 2 3" tabpage-number
--    indicator with our own rainbow-chip version (util/rainbow_tabs.lua), the
--    same style as the floating terminal's tmux-window indicator
--    (util/floating_term.lua), via bufferline's public extension point so no
--    bufferline internals are patched. Each chip is clickable.
--
-- 2. `apply_highlights()` -- restyles the *buffer* tabs themselves in the same
--    pill language, with the selected buffer painted in the CURRENT TABPAGE's
--    accent. So the lit chip on the right and the selected tab on the left are
--    always the same hue, and the whole strip reads as one color per
--    workspace rather than a static theme color next to a rainbow.

function _G.RainbowTabpageClick(minwid)
  vim.cmd(minwid .. "tabnext")
end

local rainbow = require("util.rainbow_tabs")

---Bufferline names its highlight groups by CamelCasing the option key:
---`buffer_selected` -> `BufferLineBufferSelected`. We set these directly with
---nvim_set_hl at runtime rather than handing them to bufferline via
---`opts.highlights`, for two reasons: the accent has to change on every
---TabEnter (a setup-time table is frozen), and bufferline validates
---`opts.highlights` keys against its own list, so a group it doesn't know
---about is a hard error there but a harmless unused group here.
local function group(name)
  return "BufferLine" .. name:gsub("_(%l)", string.upper):gsub("^%l", string.upper)
end

-- Every per-tab element bufferline draws. Each gets the fill background of
-- whichever state it belongs to -- miss one and it renders with the default
-- theme's background, which shows up as a notch of wrong color inside an
-- otherwise solid pill (most visibly around the modified dot and diagnostics).
local ELEMENTS = {
  "buffer",
  "numbers",
  "duplicate",
  "modified",
  "close_button",
  "diagnostic",
  "info",
  "info_diagnostic",
  "warning",
  "warning_diagnostic",
  "error",
  "error_diagnostic",
  "hint",
  "hint_diagnostic",
  "pick",
  "indicator",
}

-- Severity colors pulled from the same accent palette as the chips, so
-- diagnostics on an inactive tab feel like part of the same design rather than
-- the colorscheme's unrelated red/yellow.
local SEVERITY = {
  error = rainbow.accents[7], -- red
  error_diagnostic = rainbow.accents[7],
  warning = rainbow.accents[6], -- yellow
  warning_diagnostic = rainbow.accents[6],
  info = rainbow.accents[2], -- cyan
  info_diagnostic = rainbow.accents[2],
  hint = rainbow.accents[9], -- teal
  hint_diagnostic = rainbow.accents[9],
}

---Base color, this tabpage's accent, and the three tiers of "not selected":
---empty line, hidden buffer, buffer visible in another split. Kept as flat
---grays at increasing lift -- same reasoning as chip_colors(): "colored vs.
---gray" should be the whole story, so the inactive tabs must never compete
---with the one accent-filled tab. Recomputed on each call rather than cached
---because the accent follows the current tabpage.
local function state_colors()
  local base = rainbow.base_bg()
  local accent = rainbow.current_accent()
  return base, accent, {
    -- suffix,      bg,                                    fg
    { "", rainbow.blend("#ffffff", base, 0.06), rainbow.blend("#ffffff", base, 0.40) },
    { "_visible", rainbow.blend("#ffffff", base, 0.11), rainbow.blend("#ffffff", base, 0.62) },
    { "_selected", accent, base },
  }
end

---Repaint ONE generated filetype-icon group onto our pill. Split out of the
---sweep below so a group can also be fixed the instant bufferline creates
---it -- see the wrapper in `config`.
local function paint_icon_group(name)
  local base, accent, states = state_colors()
  local suffix = name:match("Selected$") or name:match("Inactive$") or ""
  local def = vim.api.nvim_get_hl(0, { name = name })
  vim.api.nvim_set_hl(0, name, {
    bg = ({ [""] = states[1][2], Inactive = states[2][2], Selected = accent })[suffix],
    -- Inactive tabs keep the icon's real color (same call as letting
    -- diagnostics keep their severity hue on gray), but on the accent fill
    -- the icon inverts to the base background like everything else -- a
    -- saturated icon color on a saturated fill is unreadable.
    fg = suffix == "Selected" and base or (def.fg and string.format("#%06x", def.fg) or nil),
  })
end

local function apply_highlights()
  local base, accent, states = state_colors()

  for _, state in ipairs(states) do
    local suffix, bg, fg = state[1], state[2], state[3]
    local selected = suffix == "_selected"
    for _, element in ipairs(ELEMENTS) do
      -- `buffer` is the odd one out: its unsuffixed group is called
      -- `background`, not `buffer`.
      local key = (element == "buffer" and suffix == "") and "background" or element .. suffix
      -- On the accent fill, severity hues would either vanish or clash, so
      -- everything on the selected tab is drawn in the base background color
      -- -- the same inversion the active chip already uses.
      local text = selected and fg or (SEVERITY[element] or fg)
      vim.api.nvim_set_hl(0, group(key), { bg = bg, fg = text, bold = selected })
    end

    -- The slope glyph is a wedge of the SURROUNDING color cut into the tab, so
    -- fg is the neighbouring/fill background and bg is the tab's own body --
    -- not the other way round. (If the slants ever look inverted, these two
    -- are the pair to swap.)
    vim.api.nvim_set_hl(0, group("separator" .. suffix), { fg = base, bg = bg })
  end

  -- Filetype icons are the one thing we can't reach through the option keys
  -- above. bufferline's set_icon_highlight() (highlights.lua) builds
  -- `BufferLineDevIcon<Type>[Selected|Inactive]` by copying the buffer
  -- colors it computed at SETUP time, then caches the group permanently --
  -- so every icon keeps the stock dark background and renders as a black box
  -- punched through our pill. Repainting the generated groups after the fact
  -- is the only way in.
  --
  -- This sweep can only reach groups that ALREADY EXIST, and bufferline
  -- creates each one lazily, the first time a buffer of that filetype is
  -- actually drawn in the tabline -- i.e. always AFTER the last time this
  -- ran. That is the "new tab shows a boxed icon until I navigate to that
  -- file" bug: nothing was wrong with the color, the group simply didn't
  -- exist yet to be repainted, and visiting the file fired the BufEnter that
  -- re-ran this. The wrapper installed in `config` closes that window by
  -- repainting each group at the moment of creation; the sweep stays for
  -- everything already on screen when the accent changes.
  --
  -- The group name is "BufferLine" .. <the icon provider's own hl group> ..
  -- state. LazyVim ships mini.icons (whose groups are `MiniIconsBlue`,
  -- `MiniIconsYellow`, ...), NOT nvim-web-devicons -- verified: requiring
  -- "nvim-web-devicons" only succeeds because mini.icons installs a shim, and
  -- the real groups here are `BufferLineMiniIconsYellowSelected` and friends.
  -- Both prefixes are matched so this survives a swap back to devicons.
  for name in pairs(vim.api.nvim_get_hl(0, {})) do
    if name:find("^BufferLineMiniIcons") or name:find("^BufferLineDevIcon") then
      paint_icon_group(name)
    end
  end

  -- The empty stretch after the last tab, and the area the rainbow chips sit
  -- in. Deliberately exactly `Normal` bg: the chips' rounded end-caps are
  -- drawn with base_bg() behind them, so any other fill here would ring each
  -- chip in a visible halo.
  vim.api.nvim_set_hl(0, group("fill"), { bg = base })
  vim.api.nvim_set_hl(0, group("offset_separator"), { fg = base, bg = base })

  -- The close-current-TABPAGE button (ui.lua's get_tab_close_button, which
  -- bufferline only draws once more than one tabpage exists -- which is why
  -- it appears exactly when the chips do). Left unstyled it kept the theme's
  -- blue-on-dark and read as a stray colored glyph floating just left of the
  -- chip row. Flattened onto the fill at the same muted gray as an inactive
  -- chip's label, so it recedes into the row instead of competing with the
  -- one accent-colored chip.
  vim.api.nvim_set_hl(0, group("tab_close"), {
    bg = base,
    fg = rainbow.blend("#ffffff", base, 0.40),
  })
end

return {
  "akinsho/bufferline.nvim",
  opts = {
    options = {
      -- Our custom_areas.right below replaces this.
      show_tab_indicators = false,
      -- Chained tabs are exactly the case slanted separators are FOR (unlike
      -- the isolated chips in rainbow_tabs.lua, which need rounded caps): the
      -- wedge reads as one segment handing off to the next. "slope" is the
      -- softer-angled variant of "slant".
      separator_style = "slope",
      -- The selected tab is a solid accent fill, so a separate indicator bar
      -- on top of it is redundant noise.
      indicator = { style = "none" },
      always_show_bufferline = true,
      custom_areas = {
        right = function()
          local total = vim.fn.tabpagenr("$")
          if total <= 1 then
            return {}
          end
          local current = vim.fn.tabpagenr()
          local items = {}
          local fill = group("fill")
          for i = 1, total do
            -- rainbow_tabs.pill() emits the whole chip -- rounded end-caps,
            -- fill, label and click region -- as one statusline string with
            -- its own `%#Group#` escapes baked in. Using it here rather than
            -- hand-rolling a flat `link`ed rectangle is the entire point of
            -- that helper existing: these chips and the floating terminal's
            -- tmux-window indicator now come out of ONE function, so they
            -- can't drift apart again.
            --
            -- The `link` below is only for whatever bufferline draws outside
            -- those escapes, so it points at the fill (base bg) -- the same
            -- color the caps are drawn against, which is what keeps each
            -- rounded end from showing a halo.
            if i > 1 then
              items[#items + 1] = { text = " ", link = fill }
            end
            items[#items + 1] = {
              text = rainbow.pill(i, i == current, tostring(i), "v:lua.RainbowTabpageClick"),
              link = fill,
            }
          end
          -- Trailing breathing room so the last chip isn't flush against the
          -- window edge.
          items[#items + 1] = { text = " ", link = fill }
          return items
        end,
      },
    },
  },
  config = function(_, opts)
    require("bufferline").setup(opts)

    -- Paint each filetype-icon group the moment bufferline generates it,
    -- rather than waiting for the next sweep (see apply_highlights). Wrapped
    -- rather than hooked because there is no event for "bufferline created a
    -- highlight group", and its own icon_hl_cache means it sets each one
    -- exactly once, during tabline rendering -- so the only reliable moment
    -- to correct it is immediately after that single call.
    local hl = require("bufferline.highlights")
    local set_icon_highlight = hl.set_icon_highlight
    hl.set_icon_highlight = function(...)
      local name = set_icon_highlight(...)
      if name then
        paint_icon_group(name)
      end
      return name
    end

    -- Carried over from LazyVim's own bufferline config, which this `config`
    -- function replaces: without it the tabline goes stale when buffers are
    -- added or wiped outside of a redraw.
    vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete" }, {
      callback = function()
        vim.schedule(function()
          pcall(nvim_bufferline)
        end)
      end,
    })
    apply_highlights()
    vim.api.nvim_create_autocmd({ "TabEnter", "TabNewEntered", "TabClosed", "ColorScheme", "BufEnter" }, {
      -- Scheduled because bufferline reinstalls its own highlights on
      -- ColorScheme too; ours have to land after that, not race it.
      callback = function()
        vim.schedule(apply_highlights)
      end,
    })
  end,
}
