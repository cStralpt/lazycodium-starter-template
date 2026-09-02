# 💤 LazyVim

# LazyVim starter template and already configured with vs code(VSCode Neovim)

<img width="1812" height="1143" alt="image" src="https://github.com/user-attachments/assets/399f2be2-f5f4-411a-99bc-fed02f63ba3a" />


- Some handy shortcuts:

  | Keybinding | Description |
  | --- | --- |
  | `<C-c>` | Yank and move to clipboard |
  | `<C-a>` | Select all lines |
  | `<C-d>` (insert mode, repeat with `.` in normal mode) | Multiple cursor alternative |

  ![nvim-multi-cursor](https://github.com/cStralpt/lazycodium-starter-template/assets/95400822/935bfec5-0873-4b47-9685-40ab437e8b87)

  - For VS Code:

    | Keybinding | Description |
    | --- | --- |
    | `<leader>smm` | Bookmark Toggle |
    | `<leader>sml` | Bookmark List for current file |
    | `<leader>smL` | Bookmark List for all files |

  - AI Keybindings (VS Code):

    | Keybinding | Description |
    | --- | --- |
    | `<leader>cix` | Open ChatGPT Codex sidebar |
    | `<leader>cic` | Open Cursor bar |
    | `<leader>cia` | Start new Augment Chat |
    | `<leader>cik` | Start new Kiro session |

- Add this Keybindings:

  <details>
  <summary>VS Code keybindings.json (click to expand)</summary>

  ```json
    [
      {
        "command": "-vscode-neovim.send",
        "key": "ctrl+d"
      },
      {
        "key": "ctrl+c",
        "command": "vscode-neovim.send",
        "when": "editorTextFocus && neovim.mode == visual",
        "args": "<C-c>"
      },
      {
        "key": "alt+k",
        "command": "vscode-neovim.send",
        "when": "editorTextFocus && neovim.mode == normal",
        "args": "<A-k>"
      },
      {
        "key": "alt+k",
        "command": "vscode-neovim.send",
        "when": "editorTextFocus && neovim.mode == visual",
        "args": "<A-k>"
      },
      {
        "key": "alt+j",
        "command": "vscode-neovim.send",
        "when": "editorTextFocus && neovim.mode == normal",
        "args": "<A-j>"
      },
      {
        "key": "alt+j",
        "command": "vscode-neovim.send",
        "when": "editorTextFocus && neovim.mode == visual",
        "args": "<A-j>"
      },
      {
        "key": "alt+k",
        "command": "vscode-neovim.send",
        "when": "editorTextFocus && neovim.mode == insert",
        "args": "<A-k>"
      },
      {
        "key": "alt+j",
        "command": "vscode-neovim.send",
        "when": "editorTextFocus && neovim.mode == insert",
        "args": "<A-j>"
      },
      {
        "key": "alt+p",
        "command": "vscode-neovim.send",
        "when": "editorTextFocus && neovim.mode == insert",
        "args": "<A-p>"
      },
      {
        "key": "ctrl+/",
        "command": "vscode-neovim.send",
        "when": "terminalFocus",
        "args": "<C-/>"
      },
      {
        "key": "ctrl+h",
        "command": "workbench.action.terminal.focusPreviousPane",
        "when": "terminalFocus",
      },
      {
        "key": "ctrl+l",
        "command": "workbench.action.terminal.focusNextPane",
        "when": "terminalFocus",
      },
      {
        "key": "ctrl+shift+h",
        "command": "workbench.action.terminal.focusPrevious",
        "when": "terminalFocus",
      },
      {
        "key": "ctrl+shift+l",
        "command": "workbench.action.terminal.focusNext",
        "when": "terminalFocus",
      },
      {
        "key": "ctrl+shift+t",
        "command": "workbench.action.terminal.newInActiveWorkspace",
        "when": "terminalFocus",
      },
    ]
  ```

  </details>

  - Required Extensions:
    - VS Code Neovim: https://marketplace.visualstudio.com/items?itemName=asvetliakov.vscode-neovim
    - Neovim UI Modifier: https://marketplace.visualstudio.com/items?itemName=JulianIaquinandi.nvim-ui-modifier
    - Bookmarks: https://marketplace.visualstudio.com/items?itemName=alefragnani.Bookmarks
  - My VS Code Settings:

    <details>
    <summary>VS Code settings.json (click to expand)</summary>

    ```json
      "extensions.experimental.affinity": {
          "asvetliakov.vscode-neovim": 1
      },
      "editor.fontFamily": "FantasqueSansM Nerd Font,'Droid Sans Mono', 'monospace', monospace",
      "editor.smoothScrolling": true,
      "editor.stickyScroll.enabled": true,
      "workbench.sideBar.location": "right",
      "editor.minimap.enabled": false,
      "editor.formatOnSave": true,
      "workbench.activityBar.location": "hidden",
      "nvim-ui.nvimColorCustomizationKeys": [
          "tab.activeBorder",
          "editorCursor.foreground",
          "panel.border",
          "panelTitle.activeBorder",
          "panelTitle.activeForeground",
          "statusBar.background",
          "activityBar.background"
      ],
      "nvim-ui.nvimColorNormal": "#A25772",
      "nvim-ui.nvimColorInsert": "#FF6464",
      "nvim-ui.nvimColorVisual": "#525CEB",
      "nvim-ui.nvimColorReplace": "#2B2A4C",
      "editor.cursorBlinking": "expand",
      "vscode-neovim.neovimViewportHeightExtend": 1000,
      "vscode-neovim.ctrlKeysForInsertMode": [
          "a",
          "c",
          "d",
          "h",
          "j",
          "o",
          "r",
          "t",
          "u",
          "w",
          "l"
      ]
    }
    ```

    </details>

  Note: on macos you probably need to add command(cmd) keybindings in order this config to work flawlessly.

## 🤖 Claude Code in Neovim

Run **many Claudes at once**, arranged like tmux panes, shared across every Neovim
window on the machine.

An agent is a **pane**, a group ("claude tab") is a **tmux window**, and all of it
lives in one shared `claude-ws` session. Because a tmux pane id is unique
server-wide, an agent started in one terminal window is a send target from every
other one — and tmux does the tiling, so several Claudes are visible side by side
without fighting your editor for space.

The workspace survives quitting one Neovim and is torn down once the **last** one
using it exits (reference-counted, and stale entries from a crashed instance are
reaped by pid so they can't pin it alive forever).

Requires `tmux`.

### Workspace

Mirrors the `<leader>t*` terminal bindings one for one — same vocabulary, nothing
new to learn.

| Keybinding | What it does |
| --- | --- |
| `<leader>ac` | Toggle the Claude workspace |
| `<leader>an` | New group ("claude tab") |
| `<leader>ao` | Another agent, below |
| `<leader>aV` | Another agent, beside |
| `<leader>a]` / `<leader>a[` | Next / previous group |
| `<leader>ax` | Close this agent |
| `<leader>az` | Show only this agent — hides the others in its group, press again to restore |
| `<leader>af` | Pick an agent (grouped, labelled, with a live preview of each pane) |
| `<leader>am` | Move this agent — pick which tab to land beside, or a new group of its own |
| `<C-h/j/k/l>` | Move between panes |

`<leader>ao` / `<leader>aV` / `<leader>an` work from the editor too: they create the
workspace if it doesn't exist, add the agent, and open the float — no `<leader>ac`
first. Where the new agent is rooted depends on where you pressed the key: from the
**editor** it uses the current file's project root; from **inside a pane** it
inherits that pane's directory, so a group stays in its own repo.

### Sending context

Every send takes an optional **count** — `2<leader>as` delivers to agent 2 without
moving focus, so you can nudge another agent mid-thought and stay where you are.
The number is printed on the statusline pill, so it's read, not memorised.

| Keybinding | What it does |
| --- | --- |
| `<leader>as` | (visual) Send the selected code |
| `<leader>al` | Mention the current line |
| `<leader>mm` | Toggle a send-mark on this line (visual: every line in the selection) |
| `<leader>mc` | Clear all send-marks in this buffer |
| `<leader>aM` | Send all marked lines, grouped into contiguous `file:start-end` blocks; marks clear only once the send succeeds |
| `<leader>ai` | Switch the active agent's model — same picker as `<leader>aIm`, but sends `/model <value>` into its live session instead of opening a new terminal |

Sends go to the **focused** agent, which is simply tmux's active pane — whichever
one you last touched. Two Neovim windows looking at the same group therefore agree
on it with nothing to sync.

`<leader>ai` reuses `claudecode.nvim`'s own model list (`claudecode.config.defaults.models`)
so the two pickers never drift apart, but it can't reuse `ClaudeCodeSelectModel` itself —
that command only knows how to spawn a fresh `ClaudeCode --model <x>` terminal, it has no
way to retarget a session that's already running. Sending `/model <value>` as text into the
agent's own pane is the only way to change a live agent's model, which is also why this is
auto-submitted (Enter included) rather than left in the prompt like every other send — there's
no text here to review, just a command to run.

### Colour

One agent is one colour everywhere. A group owns an accent — the same one its pill
carries on the workspace winbar and the statusline — and the tabs inside it are
shades of that hue, so a row tells you which group it belongs to before you've read
any text.

### Statusline

Mostly empty, on purpose. The bufferline tab above it already draws the filetype
icon, filename, modified dot and diagnostic counts for the current buffer, so a
`root › icon › path › diagnostics` breadcrumb underneath was the same information
twice — three times for the repo name, which lands on the agent pill as well.

What's left is only what nothing else on screen says:

```
 NORMAL │  main                                    +12 ~3   1 ✓
   mode    branch                                   churn    agents
```

`+12 ~3` is the gitsigns diff for the current buffer — how much of what you're
looking at isn't yours yet. Both right-hand segments render empty when they have
nothing to report, so a plain editing session gets a clean bar.

Trade-off: bufferline truncates long tab labels and the full name now lives
nowhere — `:f` still prints it. Everything removed is listed with its reasoning at
the top of `lua/plugins/lualine.lua`, including how to put each piece back.

### Agent status

One agent is one colour everywhere — but colour says **which** agent, never what it
is doing. Status is a separate channel: a glyph on the pill, so the two can be read
independently rather than decoded from one blob of colour.

| Glyph | Meaning |
| --- | --- |
| `!` | Blocked on you — permission prompt, MCP elicitation, or asking for input |
| `✓` | Finished its turn; you haven't read the output yet |
| `…` | Running tools |
| *(none)* | Idle, or not reporting |
| `◇` | Plan mode — it won't edit anything |
| `⚡` | Permissions bypassed — it will never stop to ask, so it can never show `!` |

A number alone can't separate two agents working in the same repo, so an agent that
**wants something from you** also carries what it was asked and how long it's been
sat there. One that's merely busy doesn't — three agents at full detail would be
~75 columns and would re-clutter the bar. Width is spent where attention is due, so
the pill's own size is a signal before you read any text:

```
 1 api …                            busy; nothing to say yet
 2 api ⚡ ✓ add tests for … 14m      unread 14 minutes, and it never asks
 3 mobile-app ◇ ! wire up the 1S… 1h  plan mode, blocked on you for an hour
```

The age is time in the *current* state, not since the last report — `PostToolUse`
fires continuously while Claude works, so resetting the clock on each one would pin
every agent at `0s` and hide exactly the one that's been stuck.

**Too many agents to fit.** A statusline can't scroll — it's one string rendered into
a fixed row, with no viewport to offset and no wheel events reaching it. So the board
*windows*: it measures its pills against the columns actually available and renders
only the slice that fits, with clickable arrows for the rest.

```
‹2   3 api …    4 api ⚡ ✓ fix auth 6m    5 web …   2›
```

Click an arrow to page one agent that way. The window also **follows focus**, so the
agent `<leader>as` targets is never the one you can't see.

How many fit is **measured, not assumed** — a wider monitor shows more agents and
hides fewer, and space is only reserved for a neighbour that's actually rendering.
Outside a repo there's no branch segment to pay for; with a clean buffer there's no
churn readout; either way the board just gets the columns. With nine agents open:

| Width | 80 | 120 | 160 | 220 |
| --- | --- | --- | --- | --- |
| Shown, no repo | 3 | 5 | 7 | 9 |
| Shown, long branch + `+12 ~3` | 1 | 3 | 5 | 9 |

The only estimate left is the mode block, sized to the longest mode name rather than
the current one — a board that's occasionally two columns shy beats one that reflows
every time you press `i`.

The board draws from a cache refreshed asynchronously (`list_panes_async`), not from
a live `tmux` query. Enumerating panes forks two subprocesses — right for a send,
where a stale list means a message typed into the wrong agent, and wrong on a redraw
path Neovim walks on every keystroke. That cost ~4ms of blocking fork per render and
was what made clicking an arrow feel laggy; the click was instant, the repaint wasn't.

The arrow colour carries the reason you'd look: it takes the accent of the nearest
hidden agent, but turns **red** if any hidden agent is `!` or `✓`. An agent blocked on
you must never go invisible just because it scrolled off — that's the one way this
could be worse than the overflowing bar it replaces.

**Picker rows** (`<leader>af`) get a label from the same source, chosen by state:
while an agent is working or blocked it shows what you asked it (`› add tests`);
once it's done it shows what it answered (`‹ Added verifyWebhook() plus 4 tests`).
The question changes with the state — "what is this one for" while it runs, "is this
worth switching to" once it's finished — and the marker says which you're reading.
An agent that reports nothing falls back to the scraped pane line, as before.

This is **reported, not guessed**. Earlier versions had no status at all, for a good
reason: Neovim can't see inside a Claude process, and inferring "working" from the
rendered pane was guesswork that went blind under bypass-permissions. Claude's own
[hooks](https://code.claude.com/docs/en/hooks) fire on the real events instead, so
`…` means it actually ran a tool and `!` means it actually raised a prompt.

**How the wiring works.** Hooks inherit Claude's environment, which includes
`$TMUX_PANE` — the very pane id this workspace already uses as an agent's identity.
So each Claude can name itself with no session-id mapping and no handshake:

```
claude/agent-status.sh        hook -> $XDG_RUNTIME_DIR/nvim-claude-agents/<pane>
claude/hooks.settings.json    which event means which state
util/claude_agent_status.lua  fs_event on that directory -> repaint
```

The record is `key=value` lines — the richest format a POSIX shell can write without
a JSON dependency on every hook call:

```
status=done          since=1788387707
mode=bypassPermissions    task=add tests for the relayer webhook path
```

Only `UserPromptSubmit` pays for a `jq` parse, because the prompt text and the
permission mode are the two things no argument can carry; every other event passes
its state as an argument and carries the rest forward.

One file per pane, because N Claude processes have no way to coordinate a shared
one; tmpfs, because these are claims about processes alive *right now* and shouldn't
survive a reboot. A pane whose Claude was `SIGKILL`ed leaves an orphan file, which is
never read (lookups are keyed by panes tmux still lists) and is swept at startup.

**Scope.** The hooks are attached with `claude --settings`, so they apply to the
Claudes *this workspace* starts and nothing else — `~/.claude/settings.json` is
untouched and a Claude you run by hand anywhere else is unaffected (it reports
nothing, and shows no glyph). To make it global instead, merge the `hooks` block
from `claude/hooks.settings.json` into `~/.claude/settings.json` and drop the
`--settings` flag from `cmd` in `util/claude_agents.lua`.

> **Note:** `!` relies on Claude actually raising a permission prompt. Under
> `--dangerously-skip-permissions` it never does, so that glyph stays quiet — `✓`
> and `…` are the signals that still carry in bypass mode.

### MCP review session (`<leader>aI…`)

Separate on purpose: `coder/claudecode.nvim` can hold only **one** live MCP
connection per Neovim process, so this stays a single shared session for inline
diff accept/reject.

| Keybinding | What it does |
| --- | --- |
| `<leader>aIc` | Toggle the MCP review session |
| `<leader>aIf` / `aIr` / `aIC` / `aIm` | Focus / resume / continue / pick a model |
| `<leader>aIb` / `aIl` / `aIM` | Add buffer / current line / marked lines as context |
| `<leader>aIa` / `aId` | Accept / reject a diff |

## 🪟 Multi-Window Session Mirroring (dual-monitor)

Edit the same file from two `nvim` windows at once — great for a second monitor. Each window keeps its own cursor, so you're never forced to look at the same spot, but content and terminals stay live-synced. Localhost only.

(Claude agents are shared across windows on their own — see above — and don't need a mirrored session.)

Requires `tmux` (`sudo pacman -S tmux` or `paru -S tmux`) for terminal mirroring.

| Keybinding | What it does |
| --- | --- |
| `<leader>iss` | Start (or extend) a mirrored session — opens a second window automatically |
| `<leader>isj` | Join a session by port, if the auto-mirror didn't reach a window |
| `<leader>isS` | Stop mirroring for this window |
