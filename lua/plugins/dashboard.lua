return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    -- stylua: ignore
    opts.dashboard.preset.header = [[
              o
              ⌇
              ⌇
       ▄▄▄▄▄▄▄╨▄▄▄▄▄▄       
      ▄██▓▒░▓▒░▓▒░▓██▄      
     ██▓█▄▄▄▄▄▄▄▄▄▄█▓██     
o⌒⌒──██▓░●░░░░░░░●░▓██──⌒⌒o 
      ▀██▓▓▓▓▓▓▓▓▓▓██▀      
      ▀▀████████████▀▀      
         ░,  ██  ,░         
        ░ '  ██  ' ░        

╦  ┌─┐┌─┐┬ ┬╔═╗┌─┐┌┬┐┬┬ ┬┌┬┐
║  ├─┤┌─┘└┬┘║  │ │ ││││ ││││
╩═╝┴ ┴└─┘ ┴ ╚═╝└─┘─┴┘┴└─┘┴ ┴
]]
    -- `s` on the dashboard: open the session picker instead of restoring cwd's session
    for _, item in ipairs(opts.dashboard.preset.keys) do
      if item.key == "s" then
        item.desc = "Select Session"
        item.section = nil
        item.action = function() require("persistence").select() end
      end
    end
  end,
}
