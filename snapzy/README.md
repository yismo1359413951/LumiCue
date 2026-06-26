<div align="center">
  <img src="./poster.png" width="400" alt="LumiCue poster" />

  <h1>🎤 LumiCue</h1>
  <p><strong>A lightweight floating teleprompter built exclusively for macOS — invisible to your audience, visible only to you.</strong></p>

  <p>
    <a href="./README.md">🇺🇸 English</a> •
    <a href="./README.zh-CN.md">🇨🇳 简体中文</a>
  </p>

  <p>
    <a href="#features">Features</a> •
    <a href="#install">Install</a> •
    <a href="#shortcuts">Shortcuts</a> •
    <a href="#known-issues">Known Issues</a> •
    <a href="#contributing">Contributing</a> •
    <a href="#license">License</a> •
    <a href="#acknowledgments">Acknowledgments</a>
  </p>
</div>

## What is LumiCue?

LumiCue is a **floating teleprompter widget** for macOS. It sits on top of your screen while you present, record, or livestream — but thanks to `sharingType = .none`, **your audience never sees it**. Only you do.

Born from [Snapzy](https://github.com/duongductrong/Snapzy) (an open-source CleanShot X alternative), LumiCue strips away all screenshot/recording features and becomes a single-purpose tool: **help you read your script effortlessly while looking natural on camera.**

## Poster

![LumiCue Poster](./poster.png)

## Features

### 📺 Invisible Teleprompter
- The window is **completely invisible to screen recordings, livestreams, and screenshots** (`sharingType = .none`)
- You see it — your audience doesn't. Look straight at the camera and read naturally.

### 🫧 Two Modes: Full & Collapsed
- **Full mode**: Large resizable window with centered scrolling text, control bar, progress track, and rescue panel
- **Pill mode (collapsed)**: A slim floating strip (2–3 lines of small text + mini controls) — drag it anywhere, keep it out of the way

### 🎨 Beautiful & Playful UI
- **Glassmorphism** frosted background with dynamic sky gradient (day → dusk → night as you progress)
- **Animated rainbow border** (indigo → violet → pink gradient flow)
- **Glowing progress bar** with a pulsing comet head
- **12 text colors** from the Tailwind palette: White, Amber, Orange, Coral, Pink, Lavender, Indigo, Sky Blue, Cyan, Mint, Lime Green, Cream

### 📝 Smart Script Input
- **⌘V paste directly** — no buttons needed; paste your script and it appears instantly
- **Import .txt files** via right-click menu
- **Inline editor** with automatic whitespace cleanup (removes all spacing characters while preserving punctuation and line breaks)
- Handles NBSP, zero-width spaces, fullwidth spaces, and other invisible Unicode characters

### 🎵 Playback Controls
- **Adjustable speed**: 0.1× to 2× (slow crawl to fast scroll)
- **Font customization**: 12 built-in families + 6 preset sizes (S/M/L) + manual scale (A-/A+)
- **Pause/Resume** with spacebar
- **Seek bar**: drag the progress track to jump anywhere in your script
- **Step back**: ↑ key or ⏪ button to go back one line

### 🆘 Rescue Panel (when paused)
- **↺ Restart current line** — re-read from the beginning
- **← Back N lines** — go back 1, 2, 3… lines (keeps counting)
- **▶ Resume** — continue scrolling

### 🎤 Voice Following (Experimental)
- Built-in on-device speech recognition (Chinese, local processing, no data upload)
- The teleprompter follows your voice in real time — speak and the text scrolls with you

### 🌐 Bilingual UI
- **Chinese / English toggle** — switch all button labels with one click (default: Chinese)
- Toggle button shows the *opposite* language: "EN" on Chinese UI, "中" on English UI

### ⌨️ Keyboard Shortcuts
- `Space` — Play / Pause
- `↑` — Step back one line
- `↓` — Step forward one line
- `⌘V` — Paste script from clipboard

### 🖥️ macOS Native
- Built with SwiftUI + AppKit + Core Animation
- Dark Aqua appearance with frosted glass
- Movable by dragging anywhere on the window background
- Resizable via bottom-right drag handle
- Full Screen auxiliary window support

## Install

> Requires **macOS 13.0** or later.

### Build from Source

```bash
git clone https://github.com/yismo1359413951/LumiCue.git
cd LumiCue
open Snapzy.xcodeproj
```

1. Select the **Snapzy** scheme
2. Build (⌘B) and Run (⌘R)
3. The teleprompter window opens immediately — no menu bar icon, no status bar

> **Note**: The Xcode project keeps the internal bundle identifier `Snapzy` to preserve data compatibility. The app displays as **LumiCue** in all user-facing UI.

## Shortcuts

| Action | Shortcut |
| ------ | -------- |
| Play / Pause | `Space` |
| Step back one line | `↑` |
| Step forward one line | `↓` |
| Paste script | `⌘V` |

## Known Issues

### 👻 Text Ghosting / Double Image

When the teleprompter is scrolling, some users may notice a **faint double-image or ghosting effect** on the text — especially at higher speeds or on external displays with lower refresh rates.

This is likely related to how `CATextLayer` compositing interacts with the `NSVisualEffectView` backdrop in the current rendering pipeline. The text layers may leave a subtle trail during rapid position updates.

**If you have ideas on how to fix this — PRs are very welcome!** Some directions worth exploring:
- Reducing the `NSVisualEffectView` backdrop update frequency
- Switching text rendering to `NSTextField` or `CALayer` with `drawsAsynchronously`
- Adding frame-synchronized `CATransaction` flushing
- Experimenting with `CVDisplayLink` for vsync-aligned scrolling

## Contributing

Contributions are welcome! Especially around the text ghosting issue and voice-following improvements.

1. Fork the repo
2. Create a feature branch
3. Make your changes
4. Open a PR with a clear description

## License

BSD 3-Clause License. See [LICENSE](LICENSE).

## Acknowledgments

LumiCue is built on [Snapzy](https://github.com/duongductrong/Snapzy) by [duongductrong](https://github.com/duongductrong) — an incredible open-source screenshot and screen recording app for macOS. We stripped it down to its teleprompter soul and gave it a new identity. Thank you to all Snapzy contributors!
