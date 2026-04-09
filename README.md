[English](README.md) | [繁體中文](README.zh-TW.md)

# IMEHelper

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-brightgreen)

A lightweight macOS utility that provides a floating input panel for typing in CJK and other IME-dependent languages, then inserting the text back into any app.

![Demo](assets/demo.gif)

## The Problem

Many apps on macOS have poor IME support:

- **Terminal emulators** (iTerm2, Wezterm, Ghostty) — CJK input is broken or awkward over SSH
- **Remote desktop clients** (RDP, VNC, Parsec) — IME composition doesn't work properly
- **Electron apps** (ChatGPT, VS Code terminal) — backspace deletes the wrong characters, preedit text disappears
- **Other apps** — some simply don't support IME at all

This affects **Chinese, Japanese, Korean, Vietnamese**, and other languages that require IME composition.

## How It Works

1. Press a global hotkey (default: `Cmd+Shift+Space`) in any app
2. A floating input panel appears — type freely with full IME support
3. Press `Enter` to insert the text back into the original app

Each window and tab gets its own independent draft, so you can switch between contexts without losing text.

> The text is injected via clipboard (Cmd+V). Your original clipboard content is automatically saved and restored after injection.

## Screenshots

| Focused | Unfocused |
|---------|-----------|
| ![Focused](assets/panel-focused.png) | ![Unfocused](assets/panel-unfocused.png) |

| Settings | Panel Manager |
|----------|---------------|
| ![Settings](assets/settings.png) | ![Panel Manager](assets/panel-manager.png) |

## Features

- **Floating input panel** with translucent glass effect
- **Per-window/tab drafts** — each context keeps its own text
- **Smart detection** — event-driven tab/window change detection
- **Custom hotkey** — configure your preferred shortcut
- **Panel management** — view, copy, and manage all active panels
- **Focus indicator** — top edge color strip + opacity change shows focus state
- **Customizable** — panel position, font size, opacity, focus strip color
- **Localized** — English and Traditional Chinese

## Affected Languages

IMEHelper helps users of any language that requires IME composition:

| Language | Common Issues |
|----------|--------------|
| Chinese | Preedit text invisible, composition broken in terminal |
| Japanese | Candidate window at wrong position, preedit disappears on modifier key |
| Korean | Double space on spacebar, text invisible during composition, shortcuts eaten by IME |
| Vietnamese | Characters lost during Telex/VNI composition, characters doubled |

## System Requirements

- macOS 14.0 (Sonoma) or later
- Accessibility permission required (for hotkey detection and cursor position)

## Installation

1. Download the latest `.dmg` from [Releases](../../releases)
2. Open the DMG and drag `IMEHelper.app` to Applications
3. Launch IMEHelper — it appears as a keyboard icon in the menu bar
4. Grant Accessibility permission when prompted (System Settings > Privacy & Security > Accessibility)

> **Note:** Since the app is not notarized, you may need to right-click > Open on first launch. This is only required once.

## Usage

| Action | How |
|--------|-----|
| Open input panel | Press `Cmd+Shift+Space` (or your custom hotkey) |
| Send text | Press `Enter` |
| Toggle panel visibility | Press hotkey again when panel is visible |
| Clear text | Press `ESC` once |
| Close panel | Press `ESC` twice (or once if empty) |
| Settings | Click menu bar icon > Settings |
| Panel manager | Click menu bar icon > Panel Manager |

## Known Limitations

- Text injection uses the clipboard (Cmd+V). Original clipboard content is saved and restored, but clipboard-sensitive apps may be affected during the brief injection window.
- The input panel requires Accessibility permission. Some enterprise-managed Macs may restrict this.
- Tab identification relies on Accessibility API attributes, which vary by app. Some apps may not be distinguishable at the tab level.

## Building from Source

1. Clone the repository
2. Open `IMEHelper.xcodeproj` in Xcode
3. Build and run (requires macOS 14.0+ SDK)

## Contributing

Issues and pull requests are welcome. For bug reports, please include your macOS version and the app where the issue occurred.

## License

[MIT License](LICENSE)

*UI language follows system settings. English and Traditional Chinese are supported.*
