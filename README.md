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

Two separate mechanisms, on purpose — see `lua/plugins/claude-code.lua`:

1. **Per-tab Claude** (`<leader>ac` / `at` / `aw` / `al` / `aM` / `as`) — a real, independent `claude` process **per tab**, no shared state, no MCP.
2. **MCP review session** (`<leader>aI...`) — the one `coder/claudecode.nvim`-integrated session (inline diff accept/reject), shared across the whole Neovim instance. That plugin can only ever hold one live MCP connection per process, so this is deliberately singleton — not a bug, an architectural limit.

### Convenient bits worth knowing

| Keybinding | What it does |
| --- | --- |
| `<leader>ac` | Per-tab Claude, genuinely isolated. Open a repo per tab, `<leader>ac` in each — they don't collide, don't share history, and toggling one never touches another. |
| `<leader>ac` / `<leader>at` | Always converge. `ac` spins up `claude` directly; `at` spins up a plain shell (`fish`, styled, real `cd` + tab-completion) so you can navigate first and run `claude` yourself. Whichever one you used, the *other* key toggles that exact same session afterward — no duplicate sessions, no guessing which key "owns" it. |
| `<leader>aw` | Float ↔ split, conversation intact. Toggles the current tab's Claude between a right split and a centered float without killing the job — same scrollback, same context, just different chrome. The float is forced opaque (`winblend = 0`) regardless of the global transparency setting, so text stays readable. |
| `<leader>aM` / `<leader>al` / `<leader>as` | Mark it, then mention it — no copy/paste. Drop vim marks (`ma`, `mb`, ...) on lines you have feedback on while reading code, then `<leader>aM` sends every marked line as an `@file:line` reference straight into that tab's Claude in one shot. `<leader>al` does the same for just the current line. `<leader>as` (visual) sends the selected code block with its file:line range. All three type directly into the terminal job (`chansend`) — works whether that tab is running `claude` or you're mid-`at`-shell, no MCP required. |
| `<C-h/j/k/l>`, `<Esc>`, `<C-g>` | Jump in and out without breaking flow. `<C-h/j/k/l>` move between the Claude window and your code from *either* side, even mid-terminal-insert. Landing in the Claude window auto-enters insert (ready to type immediately). Plain `<Esc>` still interrupts Claude instantly — no delay-inducing `<Esc><Esc>` mapping in the way. `<C-g>` drops to terminal-normal mode if `<C-\><C-n>` doesn't reach your terminal/keyboard layout. |
| `<C-/>` | A *styled* embedded terminal. Runs `fish` (not bash) inside a real Neovim split, so it looks like your actual terminal instead of a bare shell — while staying toggleable/hideable like any Neovim window. |
| `<leader>aIc/aIf/aIr/aIC/aIm`, `aIb/aIl/aIM`, `aIa/aId` | Review session, when you want it. `aIc/aIf/aIr/aIC/aIm` manage the shared MCP session; `aIb/aIl/aIM` add context to it; `aIa/aId` accept/reject its inline diffs. Reach for this specifically when you want Claude reading your live buffer state and proposing diffs you review in Neovim itself — everyday chat lives in the per-tab sessions above. |
