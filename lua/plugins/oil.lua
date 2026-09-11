return {
  {
    "stevearc/oil.nvim",
    opts = {
      float = {
        -- The directory browser (`-` inside a workspace float,
        -- util/dir_browser.lua) is an oil float whose window carries
        -- w:dir_browser: its title names who is choosing and the directory on
        -- screen (the keys are in its footer). oil re-reads this on every
        -- directory the window shows. Every other oil float keeps oil's own
        -- title, the ~-abbreviated path, reproduced below because setting this
        -- hook replaces oil's default rather than wrapping it.
        get_win_title = function(winid)
          local buf = vim.api.nvim_win_get_buf(winid)
          local dir = require("oil").get_current_dir(buf)
          local path = dir and vim.fn.fnamemodify(dir, ":~") or vim.api.nvim_buf_get_name(buf)
          local browser = vim.w[winid].dir_browser
          if browser then
            return (" %s \u{2192} %s "):format(browser.label, path)
          end
          return path
        end,
        -- An oil float opened from INSIDE another float must stack above it.
        -- oil hardcodes zindex 45 and the workspace floats sit at 50 (their
        -- scrollback at 51), so the browser opened behind the workspace --
        -- focused, taking your keys, and invisible. Runs before nvim_open_win,
        -- while the window `-` was pressed in is still current.
        override = function(conf)
          local here = vim.api.nvim_win_get_config(0)
          if here.relative ~= "" and here.zindex then
            conf.zindex = math.max(conf.zindex or 0, here.zindex + 2)
          end
          return conf
        end,
      },
    },
  },
}
