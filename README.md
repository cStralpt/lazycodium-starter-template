# 💤 LazyVim
# LazyVim starter template and already configured with vs code(VSCode Neovim)
 - ![image](https://github.com/cStralpt/lazycodium-starter-template/assets/95400822/ffe8d4c5-bf06-43c2-becd-b0a03b222b67)
 - Some handy shortcuts: `<C-c>` yank and move to clipboard, `<C-a>` select all lines
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
       "command": "vscode-neovim.send",
       "key": "ctrl+l",
       "when": "editorTextFocus && neovim.mode == insert",
       "args": "<C-l>"
     }
   ]
   ```

