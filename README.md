# MarkdownEditor

A lightweight, native macOS Markdown editor written in Objective-C. No Electron, no Swift, no Xcode project — just Cocoa and ~1,700 lines of code compiled straight from the terminal.

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-blue) ![Objective-C](https://img.shields.io/badge/language-Objective--C-orange) ![Size](https://img.shields.io/badge/binary-166KB-green)

## Features

- **Tabs** — open multiple files side by side (Cmd+T)
- **Syntax highlighting** — headings, bold, italic, code, links, blockquotes coloured live as you type
- **Live preview** — split-pane WebKit preview with dark mode support (Cmd+Shift+P)
- **Focus mode** — wide margins, centred 680pt column for distraction-free writing (Cmd+Shift+F)
- **Slash commands** — type `/` on a blank line for a popup menu of Markdown templates (headings, lists, code blocks, links…)
- **Keyboard shortcuts** — Cmd+B bold, Cmd+I italic, Cmd+K link
- **Auto-list continuation** — press Return inside a list and the next bullet/number is added automatically
- **Font size control** — Cmd++ / Cmd+- / Cmd+0 to reset
- **Word & character count** — live status bar showing words, chars, line and column
- **Dark / light mode** — toggle from the View menu, preference remembered across restarts
- **Open, save, rename** — full NSDocument integration including dirty-state tracking and native save dialogs

## Requirements

- macOS 12 Monterey or later
- Xcode Command Line Tools (`xcode-select --install`)

No third-party dependencies.

## Build & run

```bash
git clone https://github.com/maz0/MarkdownEditor.git
cd MarkdownEditor
make run
```

That's it. The `make run` command compiles everything and opens the app in one step.

Other targets:

```bash
make build   # compile only, produces MarkdownEditor.app
make clean   # delete the built app
```

## Project structure

```
MarkdownEditor/
├── src/
│   ├── main.m                  # entry point
│   ├── AppDelegate.{h,m}       # menu bar, app lifecycle
│   ├── MDDocument.{h,m}        # editor window, all features
│   ├── MDSyntaxHighlighter.{h,m} # live syntax colouring
│   ├── MDPreview.{h,m}         # Markdown → HTML converter
│   └── SlashMenu.{h,m}         # slash command popup
├── Info.plist                  # bundle metadata
├── MarkdownEditor.icns         # app icon
└── Makefile
```

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| New tab | Cmd+T |
| Open file | Cmd+O |
| Save | Cmd+S |
| Save As | Cmd+Shift+S |
| Rename | Cmd+Shift+R |
| Bold | Cmd+B |
| Italic | Cmd+I |
| Link | Cmd+K |
| Increase font | Cmd++ |
| Decrease font | Cmd+- |
| Reset font | Cmd+0 |
| Focus mode | Cmd+Shift+F |
| Preview | Cmd+Shift+P |

## License

MIT
