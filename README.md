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

## 🖥️ Floating terminal (tmux)

A near-fullscreen float backed by a persistent tmux session, so splits, tabs and
running processes survive hiding it. Requires `tmux`.

| Keybinding | What it does |
| --- | --- |
| `<C-/>` | Toggle the floating terminal |
| `<leader>ts` / `<leader>tv` | Split pane horizontally / vertically |
| `<leader>tn` | New tab (terminal group) |
| `<leader>t]` / `<leader>t[` | Next / previous tab |
| `<leader>tx` | Close pane |
| `<C-h/j/k/l>` | Move between panes |
| `<C-g>` | Scrollback in a normal buffer — see below |

### Scrollback

`tmux attach` runs on the alternate screen, so the terminal buffer is one screen
tall and normal mode can't scroll it. `<C-g>` instead loads the pane's full
history (50k lines, colors preserved) into an ordinary buffer.

| Keybinding | What it does |
| --- | --- |
| `<C-g>` | Open the scrollback buffer |
| `j` `k` `<C-u>` `<C-d>` `/` `v` `y` `<C-c>` | Ordinary normal mode — every mapping you already have |
| `q` `<Esc>` `<C-g>` `i` `a` | Back to the live terminal |

Mouse wheel also works directly in the terminal via tmux copy-mode, where `v`
selects and `y` or `<C-c>` copies to the system clipboard.

## 🤖 Claude Code in Neovim

Run **many Claudes at once**, shared across every Neovim window on the machine.
<img width="1809" height="1143" alt="image" src="https://github.com/user-attachments/assets/41b4d39f-bba0-4443-b8b0-32ae05e0687a" />

Requires `tmux`.

### Workspace

Mirrors the `<leader>t*` terminal bindings one for one.

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

`<leader>ao` / `<leader>aV` / `<leader>an` work from the editor too. From the
**editor** the new agent uses the current file's project root; from **inside a
pane** it inherits that pane's directory.

### Focus without opening anything

These three never open the float.

| Keybinding | What it does |
| --- | --- |
| `<leader>aj` / `<leader>ak` | Focus the next / previous agent, wrapping |
| `N<leader>af` | Focus agent N directly — no picker, no float (`3<leader>af`) |
| *click a statusline pill* | Focus that agent |

### Sending context

Every send takes an optional **count** — `2<leader>as` delivers to agent 2 without
moving focus. The number is printed on the statusline pill.

| Keybinding | What it does |
| --- | --- |
| `<leader>as` | (visual) Send the selected code |
| `<leader>al` | Mention the current line |
| `<leader>mm` | Toggle a send-mark on this line (visual: every line in the selection) |
| `<leader>mc` | Clear all send-marks in this buffer |
| `<leader>aM` | Send all marked lines, grouped into contiguous `file:start-end` blocks |
| `<leader>ai` | Switch the active agent's model in its live session |

### Agent status

Colour says **which** agent; the glyph on the pill says what it's doing.

| Glyph | Meaning |
| --- | --- |
| `!` | Blocked on you — permission prompt, MCP elicitation, or asking for input |
| `✓` | Finished its turn; you haven't read the output yet |
| `…` | Running tools |
| *(none)* | Idle, or not reporting |
| `◇` | Plan mode — it won't edit anything |
| `⚡` | Permissions bypassed — it will never stop to ask, so it can never show `!` |

> **Porting this to your machine:** every `command` in `claude/hooks.settings.json`
> is an **absolute path** and has to be rewritten for your own home directory, and
> `agent-status.sh` has to stay executable (`chmod +x`) — Claude runs hooks without
> a shell, so `~` and `$HOME` are not expanded.

### MCP review session (`<leader>aI…`)

Separate on purpose: `coder/claudecode.nvim` holds only **one** live MCP connection
per Neovim process, so this stays a single shared session for inline diffs.

| Keybinding | What it does |
| --- | --- |
| `<leader>aIc` | Toggle the MCP review session |
| `<leader>aIf` / `aIr` / `aIC` / `aIm` | Focus / resume / continue / pick a model |
| `<leader>aIb` / `aIl` / `aIM` | Add buffer / current line / marked lines as context |
| `<leader>aIa` / `aId` | Accept / reject a diff |

## 🪟 Multi-Window Session Mirroring (dual-monitor)

Edit the same file from two `nvim` windows at once. Each window keeps its own
cursor; content and terminals stay live-synced. Localhost only. Requires `tmux`.

| Keybinding | What it does |
| --- | --- |
| `<leader>iss` | Start (or extend) a mirrored session — opens a second window automatically |
| `<leader>isj` | Join a session by port, if the auto-mirror didn't reach a window |
| `<leader>isS` | Stop mirroring for this window |

## 🖥️ Terminal integration (foot, zero padding)

Editor windows open with **no padding**, set per-instance so ordinary shells keep
theirs. The flags live in one place, `~/.local/bin/nvim-foot`:

```sh
#!/bin/sh
exec foot -o "main.pad=0x0 center" nvim "$@"
```

| Entry point | Where it lives |
| --- | --- |
| `Super+C` | `$editor` in `~/.config/caelestia/hypr-vars.conf` (absolute path) |
| `<leader>iss` mirror | `lua/plugins/instant.lua` (same flags, plus `-D`) |
| `nvim` / `nv` | `~/.config/fish/functions/` |

The `nvim` / `nv` wrappers open a new zero-padding window, with a guard that falls
through to the real binary when not on a TTY or when `$NVIM` is set — that's what
keeps `git commit` and `git rebase -i` working.

## 🚀 Setting this up on your own machine

Only `nvim` and `tmux` are required. Everything else — compositor keybind, terminal,
shell — adapts to your setup. **Run this on a frontier model** ([Claude Opus 5](https://claude.com/product/claude-code)
or equivalent); smaller models tend to guess a plausible-looking flag and leave a
half-working setup.

<details>
<summary>Setup prompt for Claude Code (click to expand)</summary>

```text
I've just cloned this Neovim config to ~/.config/nvim and I want it fully working on
my machine. Please set it up, adapting anything that was hardcoded to the original
author's environment. Work through it in this order and tell me what you changed.

IMPORTANT: this config was written on Arch + Hyprland + the foot terminal + fish, but
none of that is a requirement and I do NOT want to be switched to any of it. Use the
terminal, shell, and compositor I ALREADY have. Wherever the config names foot, treat
that as "the author's terminal" and substitute mine. Never install a new terminal
emulator or change my default shell -- if a feature genuinely cannot work with what I
have, say so plainly and skip it rather than migrating me.

1. Survey my environment first, and report it back before changing anything:
   - OS/distro and package manager
   - Login shell AND my interactive shell (they may differ)
   - Wayland or X11, and which compositor/DE
   - Which terminal emulators are installed, and ASK ME which one I want used
     for editor windows if there is more than one
   - Whether nvim, tmux, jq, git, ripgrep and a C compiler are present

2. Install the missing hard dependencies with my package manager, asking me first.
   Only tmux (terminal mirroring) and jq (the Claude status hooks) are actually
   required. Do not install a terminal emulator.

3. Fix the Claude Code hooks in claude/hooks.settings.json. Every "command" is an
   ABSOLUTE path to the original author's home directory. Claude runs hooks without
   a shell, so ~ and $HOME are NOT expanded and a relative path resolves against an
   unpredictable cwd. Rewrite each one for my home directory and make sure
   claude/agent-status.sh is executable. Verify by running the script by hand with
   a fake $TMUX_PANE and showing me the file it writes.

4. Set up editor windows for MY chosen terminal. This whole step is optional polish
   -- if my terminal can't do part of it, skip that part and tell me, don't work
   around it by installing something else.
   - Create a launcher script at ~/.local/bin/nvim-<myterminal> that opens nvim in
     one new window of my terminal and passes "$@" through. The author's foot
     version is exec foot -o "main.pad=0x0 center" nvim "$@".
   - Zero padding is a nice-to-have, not the point. If my terminal has a
     per-instance config-override flag, use it so ONLY editor windows lose their
     padding; never edit my global terminal config to achieve it. Check my
     terminal's own --help/man page for the real flag rather than guessing -- as a
     starting point, kitty uses -o window_padding_width=0, alacritty uses
     -o window.padding.x=0 -o window.padding.y=0, ghostty uses --window-padding-x=0,
     and wezterm uses --config window_padding=.... Profile-based terminals like
     konsole and gnome-terminal have no per-instance flag at all: in that case just
     skip the padding and say so.
   - Add `nvim` and `nv` wrappers for MY interactive shell (not fish, unless fish
     is what I actually use). They should open a new window via that launcher.
     Keep a guard that falls through to the REAL nvim binary when stdin or stdout
     is not a TTY, when $NVIM is set, or when the terminal isn't installed -- the
     not-a-TTY case is what keeps `git commit` working, since a detached window
     exits instantly and git then aborts on the unmodified message.
   - If I use a tiling WM/compositor, offer a keybind (the author's is Super+C)
     using an absolute path to the launcher, since a WM's PATH usually lacks
     ~/.local/bin. Show me the line and let me confirm before editing any WM config.
     If I'm on a normal desktop environment, skip this and tell me.

5. Reorder the <leader>iss terminal fallback list in lua/plugins/instant.lua so MY
   terminal is FIRST -- it currently leads with foot. If my terminal isn't on the
   list at all, add it with the correct working-directory flag, verified from its
   own docs. That flag is load-bearing: the mirror resolves the synced buffer name
   against its own cwd, so without it the mirror opens in the wrong directory and
   times out after 30s instead of syncing.

6. Verify, and show me the actual output rather than asserting it works:
   - `nvim --headless "+checkhealth" +qa` for errors
   - the terminal-selection logic picks MY terminal, not foot
   - the `nvim` wrapper opens a new window interactively, and still falls through
     to the real binary when not on a TTY (test both branches -- and keep stdout a
     TTY while testing the first one, or it falsely takes the not-a-TTY path)
   - a real <leader>iss opens a second window that syncs
   - a Claude agent shows a status glyph in the statusline

Don't change my keybindings, colorscheme, or plugin list beyond what's needed to make
these features work. If something can't work on my setup, say so directly instead of
leaving a broken half-configuration.
```

</details>
