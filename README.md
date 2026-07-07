# MarkdownEditor

A lightweight, native macOS Markdown editor written in Objective-C. No Electron, no Swift, no Xcode project — just Cocoa and ~1,700 lines of code compiled straight from the terminal.

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-blue) ![Objective-C](https://img.shields.io/badge/language-Objective--C-orange) ![Size](https://img.shields.io/badge/binary-166KB-green)

## Features

- **Tabs** — open multiple files side by side (Cmd+T)
- **Syntax highlighting** — headings, bold, italic, code, links, blockquotes coloured live as you type
- **Live preview** — split-pane WebKit preview with dark mode support (Cmd+Shift+P); scroll-synced to the editor, local images and videos render, task lists become checkboxes
- **Mermaid diagrams** — ` ```mermaid ` code blocks render as diagrams in the preview, fully offline (bundled mermaid v10)
- **Code highlighting in preview** — fenced code blocks coloured by bundled highlight.js
- **Outline sidebar** — jump between headings (Cmd+Shift+O)
- **Export** — save as self-contained HTML or PDF from the File menu
- **Image drag-and-drop** — drop an image file into the editor; it's copied beside the document and linked
- **Focus mode** — wide margins, centred 680pt column, typewriter scrolling (Cmd+Shift+F)
- **Slash commands** — type `/` on a blank line for a popup menu of Markdown templates (headings, lists, code blocks, links…)
- **User templates** — .md files in the templates folder (File → Open Templates Folder) appear in the slash menu; `{{date}}`, `{{time}}`, `{{weekday}}`, `{{filename}}` fill in at insertion and `{{cursor}}` places the caret. Ships with Meeting note, Daily note, and Weekly review starters
- **Keyboard shortcuts** — Cmd+B bold, Cmd+I italic, Cmd+K link
- **Auto-list continuation** — press Return inside a list and the next bullet/number is added automatically
- **Font size control** — Cmd++ / Cmd+- / Cmd+0 to reset
- **Word & character count** — live status bar showing words, chars, line and column
- **Dark / light mode** — toggle from the View menu, preference remembered across restarts
- **Open, save, rename** — full NSDocument integration with autosave, Versions (File → Browse All Versions…), and an Open Recent menu
- **Find in Folder** — search every markdown/text file in the document's folder (Cmd+Opt+F), click a result to jump to it
- **Update notifications** — checks GitHub releases once a day and offers new versions; manual check via Markdown Editor → Check for Updates…

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

## Releasing

Installed apps poll the latest GitHub release once a day and notify the user
when a newer version appears. To publish an update:

1. Bump `CFBundleShortVersionString` (and `CFBundleVersion`) in `Info.plist`
2. Commit
3. `make release` — builds, tags `v<version>`, pushes, and creates a GitHub
   release with the zipped app attached (requires the `gh` CLI)

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
| Outline | Cmd+Shift+O |

## License

MIT
