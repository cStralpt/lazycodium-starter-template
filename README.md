# 💤 LazyVim

# LazyVim starter template and already configured with vs code(VSCode Neovim)

- ![image](https://github.com/cStralpt/lazycodium-starter-template/assets/95400822/ffe8d4c5-bf06-43c2-becd-b0a03b222b67)
- Some handy shortcuts:

  - `<C-c>` yank and move to clipboard,
  - `<C-a>` select all lines
  - multiple cursor alternative: in insert mode -> `<C-d>` -> repeat with dot key in normal mode
  - ![nvim-multi-cursor](https://github.com/cStralpt/lazycodium-starter-template/assets/95400822/935bfec5-0873-4b47-9685-40ab437e8b87)
  - For VS Code:
    - Bookmark Toggle: `<leader>smm`
    - Bookmark List for current file: `<leader>sml`
    - Bookmark List for all files: `<leader>smL`

- VS Code keybindings to pass to Neovim:
  ```
  [
    {
      "command": "vscode-neovim.send",
      "key": "backspace",
      "when": "editorTextFocus && neovim.mode == insert",
      "args": "<BS>"
    },
    {
      "command": "vscode-neovim.send",
      "key": "ctrl+/",
      "when": "editorTextFocus && neovim.mode == normal",
      "args": "<C-/>"
    },
    {
      "command": "-vscode-neovim.send",
      "key": "ctrl+d"
    },
    {
      "command": "vscode-neovim.send",
      "key": "ctrl+a",
      "when": "editorTextFocus && neovim.mode == insert",
      "args": "<C-a>"
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
      "key": "alt+j",
      "command": "vscode-neovim.send",
      "when": "editorTextFocus && neovim.mode == normal",
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
  ]
  ```
  - Required Extensions:
    - VS Code Neovim: https://marketplace.visualstudio.com/items?itemName=asvetliakov.vscode-neovim
    - Neovim UI Modifier: https://marketplace.visualstudio.com/items?itemName=JulianIaquinandi.nvim-ui-modifier
    - Bookmarks: https://marketplace.visualstudio.com/items?itemName=alefragnani.Bookmarks
  - My VS Code Settings:
    ```
      "workbench.colorTheme": "Night Coder Ember Contrast",
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
  Note: on macos you probably need to add command(cmd) keybindings in order this config to work flawlessly.
