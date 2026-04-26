# Magpie

> A local-first, keyboard-driven clipboard manager for macOS. Like the magpie that hoards every shiny thing — collect what you copy, summon with one keypress, paste with another.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black.svg)](#)
[![Status: alpha](https://img.shields.io/badge/status-alpha-orange.svg)](#)
[![Version: 0.2.0](https://img.shields.io/badge/version-0.2.0-blue.svg)](#)

## Status

🐦 **Alpha 0.2.0**. v0.1 skeleton (clipboard capture, ⌘P panel, paste-back) and v0.2 detective (search, three layouts, Detail Pane, Settings, theme system) shipped. Track progress in [`md/codex/plan/tasks/`](md/codex/plan/tasks/) (symlinked notes). DMG in `dist/Magpie-0.2.0.dmg`.

## What Magpie does

A clipboard history + snippet manager built to replace [Maccy](https://github.com/p0deje/Maccy) and Deck on macOS:

- **Local-only SQLite** — no cloud, no analytics, no telemetry, ever.
- **Keyboard is a first-class citizen** — every mouse-driven action has a shortcut.
- **Type-aware previews** — text, code, URL, image, file path, folder path each look different.
- **Three layouts** (Stripe / Stack / Grid) for different working rhythms.

The full prototype spec lives at [`prototype/剪切板工具/Magpie 原型说明.html`](prototype/) (Chinese) — open it locally for the source-of-truth design rationale.

## Roadmap

| Version | Status | Scope |
|---------|--------|-------|
| v0.1 | ✅ shipped | Clipboard listener, ⌘P panel, Stripe layout, ↵/double-click paste, 4 types: text·code·url·folder |
| v0.2 | ✅ shipped | Search (incl. `key:value` syntax), type filter, Pin, Stack & Grid layouts, Detail Pane, Settings (Theme/Vibrancy/Flavor + Shortcuts) |
| v0.3 | next | Image/File full support, Snippets drawer, History/Privacy/Touch ID, Queue Mode, theme & motion polish |
| Later | — | Regex search, URL sanitization, CLI tool |

## Building

Requires:

- macOS 14 (Sonoma) or later
- Xcode 15+
- Swift 5.9+

```bash
git clone https://github.com/sanwan99/magpie.git
cd magpie
open Magpie.xcodeproj
# Build & Run (⌘R)
```

> Build instructions stabilize during v0.1; this section will be filled in once the Xcode project lands.

## Project structure

```
magpie/
├── Magpie.xcodeproj/         # Xcode project (lands in Phase 0b)
├── Sources/                  # Swift source (App / Panel / Clipboard / Storage / Paste / Hotkey)
├── Resources/                # assets, Info.plist
├── prototype/                # original React/JSX visual prototype + spec doc (reference only)
│   └── 剪切板工具/
└── md/                       # design notes, plans, ADRs (symlinked to private notes repo)
```

## License

[MIT](LICENSE)

## Acknowledgements

- Inspired by [Maccy](https://github.com/p0deje/Maccy), [Raycast](https://www.raycast.com), and Deck.
