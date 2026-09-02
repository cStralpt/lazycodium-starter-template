-- A statusline for working alongside agents, which mostly meant deleting.
--
-- The starting point was LazyVim's default plus a colorized breadcrumb, and
-- the thing that killed it was reading one bar next to the bufferline above
-- it: the tab said `public-relayer/SKILL.md ⚠114` and the statusline said
-- `mobile-app/…/public-relayer/SKILL.md ⚠ 114`. Filetype icon, filename,
-- modified state, diagnostic counts -- plugins/bufferline.lua already draws
-- every one of them, per tab, in the same pill language. The statusline was
-- restating the strip two inches lower, and the repo name landed a third time
-- on the agent pill at the far right.
--
-- So `lualine_c` is empty. What's left is the set of things nothing else on
-- screen says:
--
--   a  mode          e  (nothing)
--   b  branch        x  buffer churn, then the agent board
--   c  (nothing)     y  (nothing)
--                    z  (nothing)
--
-- Known trade-off, accepted deliberately: bufferline truncates long tab labels
-- (`useAgentConnectio…`) and there is now nowhere showing the full name. `:f`
-- still answers it, and the untruncated path was not worth a permanent segment.
--
-- What was dropped, and why, in case any of it is missed:
--
--   root_dir, filetype icon, pretty_path, diagnostics
--     On the bufferline tab already. root_dir additionally repeats on the
--     agent pill, since an agent is named for its cwd.
--   trouble's symbol breadcrumb (LazyVim appends it when vim.g.trouble_lualine)
--     In a markdown spec it expanded to the whole heading chain -- "Sui dApp
--     bridge — engineering spec > 0. Goal & non-goals > Non-goals (this
--     milestone)" -- and changed width on every cursor move. It answers "where
--     am I in this file", which is a question you have while writing code by
--     hand; while reading back an agent's work the cursor is wherever the hunk
--     is. Restore from `require("trouble").statusline({ mode = "symbols", … })`
--     in lazyvim/plugins/ui.lua.
--   progress, location
--     The cursor position is, literally, where the cursor is.
--   lualine_z's clock
--     tmux's own status bar prints the time at the bottom of the same pane.
--   profiler status, noice pending-keys, lazy.nvim update count
--     Transient, or actionable about once a week.

local rainbow = require("util.rainbow_tabs")
local agents = require("util.claude_agents")

-- NORMAL mode's block color, replacing the blue (#82aaff) tokyonight's lualine
-- theme ships. Pink is the only accent at this pastel level that no mode has
-- already claimed: tokyonight defines all six mode slots, and teal -- the
-- obvious "better than blue" pick -- is already TERMINAL (#4fd6be), so using
-- it would have made normal and terminal indistinguishable.
--
--   insert #c3e88d · visual #c099ff · replace #ff757f
--   command #ffc777 · terminal #4fd6be · normal #fca7ea (this)
local MODE_NORMAL = rainbow.accents[1]

return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    -- Start the registry here, not only from claude-code.lua's config: that
    -- plugin is lazy-loaded on <leader>a, so the agent board would stay blank
    -- until the first agent keypress -- including for a Claude already running
    -- in the <C-/> workspace. setup() is idempotent, so both callers are fine.
    agents.setup()

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

    opts.sections.lualine_c = {}

    -- The right side answers the two questions an agent session actually
    -- raises, in the order you ask them.
    --
    -- First: how much of what's on screen isn't mine yet. That's the gitsigns
    -- diff for this buffer -- unlike `progress` or `location` it is information
    -- the window doesn't already show, and it renders nothing outside a repo.
    --
    -- Then: is anything waiting on me. That's the agent board, which carries a
    -- status glyph per agent reported by Claude's own hooks (see
    -- util/claude_agent_status.lua). It renders "" with no agents, so a plain
    -- editing session gets a clean, empty right side rather than a swap of one
    -- set of noise for another.
    opts.sections.lualine_x = {
      {
        "diff",
        symbols = {
          added = icons.git.added,
          modified = icons.git.modified,
          removed = icons.git.removed,
        },
        source = function()
          local gitsigns = vim.b.gitsigns_status_dict
          if gitsigns then
            return {
              added = gitsigns.added,
              modified = gitsigns.changed,
              removed = gitsigns.removed,
            }
          end
        end,
      },
      { agents.lualine, padding = { left = 1, right = 1 } },
    }

    opts.sections.lualine_y = {}
    opts.sections.lualine_z = {}

    return opts
  end,
}
