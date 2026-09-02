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
| `<leader>af` | Pick an agent (grouped, with a live preview of each pane) |
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

Sends go to the **focused** agent, which is simply tmux's active pane — whichever
one you last touched. Two Neovim windows looking at the same group therefore agree
on it with nothing to sync.

### Colour

One agent is one colour everywhere. A group owns an accent — the same one its pill
carries on the workspace winbar and the statusline — and the tabs inside it are
shades of that hue, so a row tells you which group it belongs to before you've read
any text.

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
