-- Replaces bufferline's plain "1 2 3" tabpage-number indicator with our own
-- rainbow-chip version (util/rainbow_tabs.lua) -- same style as the floating
-- terminal's tmux-window indicator (util/floating_term.lua) -- via
-- bufferline's public `custom_areas` extension point, so no bufferline
-- internals are patched. Each chip is clickable (tabline click syntax) to
-- jump straight to that tabpage, same as clicking a real editor tab already
-- does.
function _G.RainbowTabpageClick(minwid)
  vim.cmd(minwid .. "tabnext")
end

return {
  "akinsho/bufferline.nvim",
  opts = {
    options = {
      -- Our custom_areas.right below replaces this.
      show_tab_indicators = false,
      custom_areas = {
        right = function()
          local total = vim.fn.tabpagenr("$")
          if total <= 1 then
            return {}
          end
          local rainbow = require("util.rainbow_tabs")
          local current = vim.fn.tabpagenr()
          local items = {}
          for i = 1, total do
            local active = i == current
            local bg, fg = rainbow.chip_colors(i, active)
            items[#items + 1] = {
              text = ("%%%d@v:lua.RainbowTabpageClick@ %d %%X"):format(i, i),
              bg = bg,
              fg = fg,
              bold = active,
            }
          end
          return items
        end,
      },
    },
  },
}
