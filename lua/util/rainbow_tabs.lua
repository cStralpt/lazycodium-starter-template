-- Shared per-index "rainbow chip" highlight colors, used by both the
-- bufferline tabpage-number indicator (plugins/bufferline.lua) and the
-- floating terminal's tmux-window indicator (util/floating_term.lua), so the
-- two look like one consistent style rather than two different hacks.
local M = {}

-- Punchy, saturated neon accents -- deliberately more vivid than
-- tokyonight-moon's own (fairly muted/pastel) palette, and with the warm
-- orange/tan range skipped entirely per explicit request. Hardcoded rather
-- than read from `require("tokyonight.colors")` so this keeps working even
-- if tokyonight isn't the active/loaded colorscheme.
M.accents = {
  "#ff2f92", -- hot pink
  "#00e5ff", -- electric cyan
  "#39ff6a", -- neon green
  "#7c4dff", -- violet
  "#2979ff", -- electric blue
  "#ffea00", -- electric yellow
  "#ff3860", -- crimson
  "#b967ff", -- purple
  "#00ffc6", -- neon mint
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
  if active then
    -- Only the active chip carries its rainbow color -- this is the ONE
    -- signal for "which tab am I on", so it has to be unambiguous rather
    -- than "brighter than its neighbors" (which reads as noise once every
    -- chip is a different hue at a different brightness).
    return M.color(index), base
  end
  -- Flat neutral gray, same for every inactive chip regardless of index --
  -- deliberately NOT a dimmed version of that chip's own hue, so "colored"
  -- vs. "gray" is the whole story instead of "compare shades".
  return M.blend("#ffffff", base, 0.12), M.blend("#ffffff", base, 0.55)
end

local function chip_hls(index, active)
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
  local hl = chip_hls(index, active)
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
