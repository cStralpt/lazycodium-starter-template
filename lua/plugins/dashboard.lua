local logo = [[
                                        𝖘𝖙𝖆𝖞𝕱𝖔𝖈𝖚𝖘
          𝖎𝖓𝖛𝖊𝖘𝖙𝖎𝖓𝖌-𝖎𝖓-𝖙𝖎𝖒𝖊 & 𝖐𝖓𝖔𝖜𝖑𝖊𝖉𝖌𝖊
  ██████╗ ███████╗ ████████╗ ██████╗   █████╗  ██╗      ██████╗  ████████╗
 ██╔════╝ ██╔════╝ ╚══██╔══╝ ██╔══██╗ ██╔══██╗ ██║      ██╔══██╗ ╚══██╔══╝
 ██║      ███████╗    ██║    ██████╔╝ ███████║ ██║      ██████╔╝    ██║   
 ██║      ╚════██║    ██║    ██╔══██╗ ██╔══██║ ██║      ██╔═══╝     ██║   
 ╚██████╗ ███████║    ██║    ██║  ██║ ██║  ██║ ███████╗ ██║         ██║   
  ╚═════╝ ╚══════╝    ╚═╝    ╚═╝  ╚═╝ ╚═╝  ╚═╝ ╚══════╝ ╚═╝         ╚═╝   
                                                      no-𝔱𝔦𝔪𝔢2𝔡𝔦𝔢
  ]]
logo = string.rep("\n", 8) .. logo .. "\n"
local Util = require("lazyvim.util")
return {
	"nvimdev/dashboard-nvim",
	opts = {
		theme = "hyper",
		config = {
			week_header = {
				enable = true,
			},
			footer = vim.split(logo, "\n"),
			shortcut = {
				{ desc = "󰊳 Lazy", group = "@property", action = "Lazy", key = "l" },
				{
					icon = " ",
					icon_hl = "@variable",
					desc = "Files",
					group = "Label",
					action = "Telescope find_files",
					key = "f",
				},
				{
					desc = " Projects",
					group = "DiagnosticHint",
					action = "Telescope projects",
					key = "p",
				},
				{
					desc = " Config",
					group = "Number",
					action = Util.telescope.config_files(),
					key = "c",
				},
				{
					action = 'lua require("persistence").load()',
					group = "Label",
					desc = " Restore Session",
					icon = "",
					icon_hl = "@variable",
					key = "s",
				},
				{
					action = "LazyExtras",
					desc = " Extras",
					icon = " ",
					group = "Number",
					icon_hl = "@property",
					key = "x",
				},
				{
					action = "Telescope live_grep",
					icon_hl = "Label",
					group = "@variable",
					desc = " Find text",
					icon = " ",
					key = "g",
				},
			},
		},
	},
}
