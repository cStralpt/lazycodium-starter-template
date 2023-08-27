return {
  "folke/flash.nvim",
  ---@type Flash.Config
  opts = {
    rainbow = {
      enabled = true,
      -- number between 1 and 9
      shade = 5,
    },
    highlight = {
      --- backdrop option enabled will lag in vscode
      backdrop = true,
      groups = {
        match = "FlashMatch",
        current = "FlashCurrent",
        backdrop = "FlashBackdrop",
        label = "FlashCurrent",
      },
    },
  },
}
