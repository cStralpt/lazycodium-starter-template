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

Run **many Claudes at once**, shared across every Neovim window on the machine.
<img width="1809" height="1143" alt="image" src="https://github.com/user-attachments/assets/41b4d39f-bba0-4443-b8b0-32ae05e0687a" />

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

`hooks.settings.json` maps Claude's events onto the five states the pill can show.
`parse` is the `jq` step, and only two events pay for it:

| Claude event | Args | Resulting state |
| --- | --- | --- |
| `SessionStart` | `idle` | *(no glyph)* |
| `UserPromptSubmit` | `working parse` | `…` — plus the task text and permission mode |
| `PostToolUse` | `working` | `…` |
| `Notification` (`permission_prompt\|elicitation_dialog\|agent_needs_input`) | `waiting` | `!` |
| `Notification` (`idle_prompt`) | `idle` | *(no glyph)* |
| `Stop` | `done parse` | `✓` — plus the answer summary |
| `SessionEnd` | `gone` | pill disappears |


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

> **Porting this to your machine:** `claude/hooks.settings.json` stores the hook
> command as an **absolute path** (`/home/cstralpt/.config/nvim/claude/agent-status.sh`)
> — Claude runs hooks without a shell, so `~` and `$HOME` are not expanded and a
> relative path would resolve against whatever cwd Claude happened to start in.
> Every `command` in that file has to be rewritten for your own home directory, and
> `agent-status.sh` has to stay executable (`chmod +x`), or the hooks fail silently
> and every agent shows no glyph at all.

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

Both `<leader>iss` and the desktop keybind below open that second window through a
terminal emulator, so which one gets used is a shared concern — see next section.

## 🖥️ Terminal integration (foot, zero padding)

This config is written against [foot](https://codeberg.org/dnkl/foot) on Wayland, and
opens editor windows with **no padding**, so the buffer meets the window edge instead
of floating inside a 25px frame.

Padding is set per-instance rather than in `foot.ini`, so only editor windows are
affected and your ordinary shells keep their normal padding:

```sh
foot -o "main.pad=0x0 center" nvim
```

The `center` keyword matters. A terminal grid is a whole number of cells, so unless
the window height happens to be an exact multiple of the cell height there are
leftover pixels, and foot's default is to dump **all** of them on the right and
bottom edges — a visible strip of wallpaper under the statusline. `center` splits the
remainder evenly instead. It cannot be driven to zero (negative padding isn't a
thing — `pad` is unsigned); an even 8px top and bottom simply reads as intentional
where 16px only at the bottom reads as a misaligned window.

Those flags live in **one** place, `~/.local/bin/nvim-foot`, so the keybind and the
shell wrappers can't drift apart when you retune the padding:

```sh
#!/bin/sh
exec foot -o "main.pad=0x0 center" nvim "$@"
```

Three things point at it:

| Entry point | Where it lives | Notes |
| --- | --- | --- |
| `Super+C` | `$editor` in `~/.config/caelestia/hypr-vars.conf` | Absolute path — Hyprland's `PATH` doesn't necessarily include `~/.local/bin` |
| `<leader>iss` mirror | `lua/plugins/instant.lua` | Same flags, plus `-D` for the working directory |
| `nvim` / `nv` | `~/.config/fish/functions/` | Detached window; falls through to the real binary when not interactive |

### The `nvim` and `nv` wrappers

`nvim` opens a new zero-padding foot window rather than taking over the terminal you
typed it in, so the editor always gets the window it was tuned for. `nv` is the same
thing under a shorter name (`--wraps nvim`, so nvim's own completions still work).

It is deliberately **not** an unconditional override:

```fish
if set -q NVIM; or not isatty stdin; or not isatty stdout
    command nvim $argv
    return $status
end
setsid -f nvim-foot $argv >/dev/null 2>&1
```

That guard is load-bearing, not defensive padding. Without it, anything invoking
`nvim` as `$EDITOR` — `git commit`, `git rebase -i`, `crontab -e` — would get a
*detached* window and an instant exit, so git would see an unmodified message and
abort the commit. Pipes (`… | nvim -`) and nested nvim terminals (`$NVIM` set) fall
through to the real binary for the same reason. There's a matching fallback for a
machine with no foot installed, so the command degrades to plain nvim instead of
silently doing nothing.

Arguments pass through verbatim, so `nvim .`, `nvim file`, and `nvim +42 file` all
behave normally; foot inherits the current directory, so `.` resolves where you ran it.

These are **fish** functions — if your interactive shell is bash or zsh they don't
apply; see the setup prompt below.

> **Why a new window and not the current one?** Padding is fixed when a window is
> created: foot has no control sequence for `pad` (`foot-ctlseqs(7)` has nothing for
> it) and no config-reload signal (`SIGUSR1`/`SIGUSR2` only switch colour themes), and
> the padding is space drawn *outside* the grid the application ever sees. So an
> already-running terminal cannot be made zero-padding after the fact by any means —
> a fresh window is the only way to get one. The alternative is putting
> `pad=0x0 center` in `foot.ini` globally, which also strips padding from every
> ordinary shell.

### Terminal fallback

`<leader>iss` prefers foot (with the padding above) but isn't foot-only: it walks a
list and takes the first terminal actually installed, so the mirror still opens on a
machine without foot.

| Order | Terminal | Working-directory flag |
| --- | --- | --- |
| 1 | `foot` | `-D <cwd>` |
| 2 | `ghostty` | `--working-directory=<cwd> -e` |
| 3 | `kitty` | `--directory <cwd>` |
| 4 | `alacritty` | `--working-directory <cwd> -e` |
| 5 | `wezterm` | `start --cwd <cwd>` |
| 6 | `konsole` | `--workdir <cwd> -e` |
| 7 | `gnome-terminal` | `--working-directory=<cwd> --` |
| 8 | `xfce4-terminal` | `--working-directory=<cwd> -x` |
| 9 | `x-terminal-emulator` | *(none — Debian's generic alternative)* |
| 10 | `xterm` | *(none)* |

Each entry carries its own directory flag because that directory is **load-bearing,
not cosmetic**: the generated join script never `:cd`s, so the mirror resolves the
synced buffer name against whatever cwd it starts in (`util/instant_bufname.lua`). A
mirror that lands in `$HOME` instead of the project silently fails to find the file
and times out after 30 seconds. Passing the job a cwd is not sufficient on its own —
foot resets it during child-shell startup — which is why the last two entries, which
have no such flag, are a genuine last resort rather than equals of the ones above.

If none of the ten is installed, the session is still hosted and says so: join it
from another nvim with `<leader>isj`.

## 🚀 Setting this up on your own machine

Much of the above is wired to **one specific setup** — Arch + Hyprland + foot + fish,
with absolute paths baked into the Claude hooks. **None of that is required.** foot is
simply what the author uses; any terminal works, and the setup prompt below is written
to adapt to whichever one you already like rather than to talk you into a new one.

Only two things are genuinely required: `nvim` itself, and `tmux` if you want terminal
mirroring. Everything else — the compositor keybind, the zero-padding windows, even
which shell you use — bends to your setup.

**Run this on a frontier model — [Claude Opus 5](https://claude.com/product/claude-code)
or equivalent.** It's a multi-step job across your shell, compositor, package manager,
and a Neovim config it has to read before changing: rewriting absolute paths in the
hook config, picking the right per-instance flag for *your* terminal, and getting the
in-place-vs-spawn branch right. Smaller models tend to guess a plausible-looking flag
and leave you with a half-working setup that fails quietly.

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
