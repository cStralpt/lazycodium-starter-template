-- Shared per-index "rainbow chip" highlight colors, used by both the
-- bufferline tabpage-number indicator (plugins/bufferline.lua) and the
-- floating terminal's tmux-window indicator (util/floating_term.lua), so the
-- two look like one consistent style rather than two different hacks.
local M = {}

-- Accents at tokyonight-moon's own pastel intensity -- specifically the level
-- lualine paints its mode section with, since that's the loudest color
-- already on screen and these chips shouldn't outshout it. Five of the nine
-- ARE lualine's mode colors verbatim (blue = normal, green = insert,
-- magenta = visual, red = replace, yellow = command); the rest come from the
-- same palette to fill out the cycle. Supersedes an earlier deliberately-neon
-- set (#ff2f92, #00e5ff, ...) that read as louder than everything around it.
--
-- Still hardcoded rather than read from `require("tokyonight.colors")` so this
-- keeps working even if tokyonight isn't the active/loaded colorscheme, and
-- the warm orange/tan range (moon's `orange`, #ff966c) is still skipped
-- entirely per the original explicit request.
M.accents = {
  "#fca7ea", -- pink        (moon `purple`)
  "#86e1fc", -- cyan
  "#c3e88d", -- green       (lualine insert)
  "#c099ff", -- magenta     (lualine visual)
  "#82aaff", -- blue        (lualine normal)
  "#ffc777", -- yellow      (lualine command)
  "#ff757f", -- red         (lualine replace)
  "#65bcff", -- azure       (moon `blue1`)
  "#4fd6be", -- teal
}

local function hex_to_rgb(hex)
  hex = hex:gsub("#", "")
  return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

---Linear-blend `hex` toward `base` by `factor` (1 = pure hex, 0 = pure base)
----- used to mute the inactive chips instead of giving them the exact same
---saturated color as the active one.
function M.blend(hex, base, factor)
  local r1, g1, b1 = hex_to_rgb(hex)
  local r2, g2, b2 = hex_to_rgb(base)
  return string.format(
    "#%02x%02x%02x",
    r1 * factor + r2 * (1 - factor),
    g1 * factor + g2 * (1 - factor),
    b1 * factor + b2 * (1 - factor)
  )
end

---The current 'Normal' background, as a hex string -- used as both the
---blend target for muted/inactive chips and the text color drawn on top of
---an active (fully saturated, pastel) chip so it stays readable.
function M.base_bg()
  local bg = vim.api.nvim_get_hl(0, { name = "Normal" }).bg
  return string.format("#%06x", bg or 0x1e2030)
end

---@param index integer 1-based position (tabpage number / tmux window index)
---@return string hex color for that index, cycling through M.accents
function M.color(index)
  return M.accents[((index - 1) % #M.accents) + 1]
end

---The accent for the tabpage you're currently on. Used by the bufferline
---restyle (plugins/bufferline.lua) so the selected *buffer* tab is painted in
---the same hue as the currently-lit tabpage chip on the right -- the whole
---line then reads as one color per workspace, instead of two unrelated
---rainbow systems fighting for attention in the same 1-row strip.
function M.current_accent()
  return M.color(vim.fn.tabpagenr())
end

-- Rounded end-caps, NOT lualine's slanted `section_separators` glyphs
-- (U+E0B0/U+E0B2): those only read cleanly when segments are chained
-- together with matching adjacent colors (as in lualine's own statusline).
-- Applied to an isolated standalone chip like these, with a gap and outer
-- background on both sides, the slant reads as a pointy flag/ribbon instead
-- of a badge -- confirmed ugly in practice. Rounded caps read as a clean
-- standalone pill regardless of what's next to them.
M.LEFT_CAP = "\u{e0b6}" --
M.RIGHT_CAP = "\u{e0b4}" --

---Highlight groups for one chip at `index`, created and cached on first use
---(shared across every caller/colorscheme, since the color formula is the
---same everywhere) -- `content` for the fill+label, `cap` for the two
---rounded end-caps (same color pair either way, just fg/bg swapped).
local hl_cache = {}
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    hl_cache = {}
  end,
})
---The single source of truth for chip fill/text colors, shared by every
---caller (floating_term.lua's pill() below AND plugins/bufferline.lua's
---custom_areas, which needs raw bg/fg rather than a baked highlight group)
---so the "gray unless active" rule can't drift out of sync between them
---again like it did the last time this logic was duplicated inline.
---@param index integer color-cycle key
---@param active boolean
---@return string fill, string text
function M.chip_colors(index, active)
  local base = M.base_bg()
  local accent = M.color(index)
  if active then
    -- SOLID: the accent as a full fill, with the text knocked out in the
    -- background color and bolded (see chip_hls). Filled-vs-outlined is a
    -- shape difference, readable at a glance even between two chips whose
    -- hues are neighbors -- which matters because every chip is now colored.
    return accent, base
  end
  -- OUTLINED: the chip's own hue, but as text on a dark tint of itself
  -- rather than a fill. Every chip stays colorful and identifiable by hue,
  -- while only one is ever solid.
  --
  -- This deliberately REVERSES the module's original rule ("only the active
  -- chip is colored, all others flat gray, so colored-vs-gray is the whole
  -- story"). That version made the color carry the active signal, which meant
  -- a chip's hue told you nothing stable about WHICH tab it was. Now hue is a
  -- fixed per-tab identity and fill weight carries "you are here" -- two
  -- independent signals instead of one overloaded one.
  return M.blend(accent, base, 0.20), accent
end

---Exported (not local) so plugins/bufferline.lua can use these group NAMES
---directly via `item.link` instead of handing bufferline raw bg/fg colors.
---That distinction matters: bufferline.nvim's own custom_area.lua forces
---`default = true` on any highlight IT creates from bg/fg ("we need to be
---able to constantly override these" -- but nvim_set_hl's `default` flag
---means the OPPOSITE: only apply if undefined, i.e. "first write wins,
---ignore everything after" for that exact group name). Since bufferline
---names that group purely by array position ("...CustomAreaText7"), the
---FIRST color a given tabpage-index ever rendered with (active or not)
---freezes permanently -- confirmed live: a tab stayed highlighted as
---"active" no matter how many other tabs were switched to afterward.
---Routing through `item.link` to one of OUR OWN groups instead (managed via
---a plain, non-default nvim_set_hl call below) sidesteps bufferline's
---static-bake path entirely, so colors keep updating every redraw like a
---normal highlight group should.
function M.chip_hls(index, active)
  local key = index .. (active and "A" or "I")
  local cached = hl_cache[key]
  if cached then
    return cached
  end
  local base = M.base_bg()
  local fill, text = M.chip_colors(index, active)
  local content = ("RainbowChip%s"):format(key)
  local cap = content .. "Cap"
  vim.api.nvim_set_hl(0, content, { bg = fill, fg = text, bold = active })
  vim.api.nvim_set_hl(0, cap, { fg = fill, bg = base })
  local ret = { content = content, cap = cap }
  hl_cache[key] = ret
  return ret
end

---Build one clickable rounded pill for a 'tabline'/'winbar'/'statusline'
---click region: `%{index}@{click_fn}@<rounded pill>%X`.
---@param index integer color-cycle key AND the click item's minwid (e.g. tabpage number or tmux window index)
---@param active boolean whether this is the current tab/window (full-saturation vs. muted)
---@param label string text shown inside the pill (usually tostring(index))
---@param click_fn string fully-qualified click callback, e.g. "v:lua.FloatingTermTabClick"
---@return string
function M.pill(index, active, label, click_fn)
  local hl = M.chip_hls(index, active)
  return ("%%%d@%s@%%#%s#%s%%#%s# %s %%#%s#%s%%X"):format(
    index,
    click_fn,
    hl.cap,
    M.LEFT_CAP,
    hl.content,
    label,
    hl.cap,
    M.RIGHT_CAP
  )
end

return M
