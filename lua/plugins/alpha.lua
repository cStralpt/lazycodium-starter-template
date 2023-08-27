return {
  {
    "goolord/alpha-nvim",
    event = "VimEnter",
    opts = function()
      local dashboard = require("alpha.themes.dashboard")
      local logo = [[ 
                                                                        𝖘𝖙𝖆𝖞𝕱𝖔𝖈𝖚𝖘
                          𝖎𝖓𝖛𝖊𝖘𝖙𝖎𝖓𝖌-𝖎𝖓-𝖙𝖎𝖒𝖊-𝖐𝖓𝖔𝖜𝖑𝖊𝖉𝖌𝖊
                                                                                          𝓬ട𝜏ɾαɬρ𝜏
             ██████╗ ███████╗ ████████╗ ██████╗   █████╗  ██╗      ██████╗  ████████╗
            ██╔════╝ ██╔════╝ ╚══██╔══╝ ██╔══██╗ ██╔══██╗ ██║      ██╔══██╗ ╚══██╔══╝ 
            ██║      ███████╗    ██║    ██████╔╝ ███████║ ██║      ██████╔╝    ██║    𝔱𝔦𝔪𝔢2𝔡𝔦𝔢
            ██║      ╚════██║    ██║    ██╔══██╗ ██╔══██║ ██║      ██╔═══╝     ██║
            ╚██████╗ ███████║    ██║    ██║  ██║ ██║  ██║ ███████╗ ██║         ██║
             ╚═════╝ ╚══════╝    ╚═╝    ╚═╝  ╚═╝ ╚═╝  ╚═╝ ╚══════╝ ╚═╝         ╚═╝
                ʅɐʅɐHʎɐʇs                             Ϩⲁⲧꞅⲓⲁⲁ𝓵ⲓ
                            ᵦₑₜₜₑᵣ𝆑ₒᵣₜₒₘₒᵣᵣₒw
        ]]
      dashboard.section.header.val = vim.split(logo, "\n")
      dashboard.section.buttons.val = {
        dashboard.button("f", " " .. " Find file", ":Telescope find_files <CR>"),
        dashboard.button("n", " " .. " New file", ":ene <BAR> startinsert <CR>"),
        dashboard.button("r", " " .. " Recent files", ":Telescope oldfiles <CR>"),
        dashboard.button("g", " " .. " Find text", ":Telescope live_grep <CR>"),
        dashboard.button("c", " " .. " Config", ":e $MYVIMRC <CR>"),
        dashboard.button("s", " " .. " Restore Session", [[:lua require("persistence").load() <cr>]]),
        dashboard.button("l", "󰒲 " .. " Lazy", ":Lazy<CR>"),
        dashboard.button("q", " " .. " Quit", ":qa<CR>"),
      }
      for _, button in ipairs(dashboard.section.buttons.val) do
        button.opts.hl = "AlphaButtons"
        button.opts.hl_shortcut = "AlphaShortcut"
      end
      dashboard.section.header.opts.hl = "AlphaHeader"
      dashboard.section.buttons.opts.hl = "AlphaButtons"
      dashboard.section.footer.opts.hl = "AlphaFooter"
      dashboard.opts.layout[1].val = 8
      return dashboard
    end,
    config = function(_, dashboard)
      -- close Lazy and re-open when the dashboard is ready
      if vim.o.filetype == "lazy" then
        vim.cmd.close()
        vim.api.nvim_create_autocmd("User", {
          pattern = "AlphaReady",
          callback = function()
            require("lazy").show()
          end,
        })
      end

      require("alpha").setup(dashboard.opts)

      vim.api.nvim_create_autocmd("User", {
        pattern = "LazyVimStarted",
        callback = function()
          local stats = require("lazy").stats()
          local ms = (math.floor(stats.startuptime * 100 + 0.5) / 100)
          dashboard.section.footer.val = "⚡ Neovim loaded " .. stats.count .. " plugins in " .. ms .. "ms, hell yeah"
          pcall(vim.cmd.AlphaRedraw)
        end,
      })
    end,
  },
  {
    "goolord/alpha-nvim",
    optional = true,
    opts = function(_, dashboard)
      local button = dashboard.button("p", " " .. " Projects", ":Telescope projects <CR>")
      button.opts.hl = "AlphaButtons"
      button.opts.hl_shortcut = "AlphaShortcut"
      table.insert(dashboard.section.buttons.val, 4, button)
    end,
  },
}
