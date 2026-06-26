<div align="center">
  <img src="./assets/lumi-logo.png" width="128" height="128" alt="LumiCue logo" />

  <h1>LumiCue · 灵光提示</h1>
  <p><strong>Your invisible floating teleprompter — a little window that only you can see, no one else.</strong></p>

  <p>
    <a href="./README.zh-CN.md">🇨🇳 简体中文</a>
  </p>

  <p>
    ⚠️ <strong>macOS only.</strong> This is a beginner's fork of <a href="https://github.com/duongductrong/Snapzy">Snapzy</a> (BSD 3-Clause), stripped down into a single-purpose teleprompter.
  </p>
</div>

---

## About

LumiCue is a tiny macOS teleprompter born out of a simple need: I record videos and I need a script scrolling in front of me — but I don't want the audience to see it. I found Snapzy, an incredible open-source CleanShot X alternative, which had a teleprompter inside. But it also came with a menu bar, screenshot tools, screen recording, annotation… I stripped everything away and kept only the teleprompter.

It opens straight into a floating window. Close it, the app quits. No menu bar, no status icon — just a glassmorphism bubble that scrolls your script while you look at the camera.

The Chinese name 灵光提示 (líng guāng tí shì) means "a flash of inspiration" or "spark of a cue" — that moment when the right word lights up just as you need it.

---

## ✨ Why the name

**Lumi** from *luminous* — a soft glow above your screen. **Cue** as in your next line, your silent helper.

Not a serious tool. A little companion on your screen — something you can count on, that stays out of your way and makes you better on camera.

---

## 📸 Preview

<img src="./poster.png" width="600" alt="LumiCue poster" />

---

## 💜 What it looks like

- **Glassmorphism** frosted background — semi-transparent, your work shows through
- **Animated rainbow border** — indigo → violet → pink, slowly flowing
- **A glowing progress bar** with a pulsing comet head
- **Dynamic sky** that shifts from day to dusk to night as you scroll through your script
- **12 Tailwind text colors** — soft, readable, easy on the eyes

---

## 🧩 What it can do

### 📺 Invisible by design
The window uses `sharingType = .none`. Your screen recordings, livestreams, and screenshots will **never** capture it. Only you see it.

### 🫧 Two shapes: Full & Pill
- **Full mode**: A resizable window with centered scrolling text, all controls, progress track, and a rescue panel
- **Pill mode**: A slim floating strip (2–3 lines at a smaller size + mini controls) — drag it to the corner, keep it out of frame

### 📝 Paste and go
- `⌘V` your script — it appears instantly
- Import `.txt` files from the right-click menu
- Built-in editor that strips all invisible spaces automatically (zero-width, fullwidth, NBSP… everything), keeps punctuation and line breaks

### 🎵 Playback
- Speed 0.1× to 2×
- 12 system fonts + 3 preset window sizes (S/M/L) + manual font scaling (A-/A+)
- Spacebar to pause/resume
- Drag the progress bar to jump anywhere in your script
- `↑` to step back one line

### 🆘 Rescue panel
Pops up when you pause (both modes):
- **↺ Restart** the current line from the beginning
- **← Back N lines** — go back 1, 2, 3… and counting
- **▶ Resume** scrolling

### 🎤 Voice following (experimental)
Built-in on-device speech recognition in Chinese — no data leaves your machine. Speak, and the text follows.

### 🌐 CN / EN toggle
One button switches all labels between Chinese and English. The button shows the *other* language — "EN" on the Chinese UI, "中" on the English one.

---

## ⌨️ Shortcuts

| Action | Key |
| ------ | --- |
| Play / Pause | `Space` |
| Step back one line | `↑` |
| Step forward one line | `↓` |
| Paste script | `⌘V` |

---

## 🔧 Build

> Requires **macOS 13.0** or later.

```bash
git clone <repo-url>
cd LumiCue
open Snapzy.xcodeproj
```

1. Select the **Snapzy** scheme
2. Build (⌘B) and Run (⌘R)
3. The teleprompter window opens — that's it

> The Xcode project keeps the internal bundle `Snapzy` for data compatibility. User-facing UI says **LumiCue**.

---

## 👻 Known issue: text ghosting

When scrolling, you may notice a faint double-image or ghosting on the text — more visible at high speeds or on lower-refresh external displays.

Likely `CATextLayer` compositing interacting badly with the frosted-glass `NSVisualEffectView` backdrop.

**PRs are very welcome!** Some directions to explore:
- Lower the backdrop update frequency
- Switch to `NSTextField` or `CALayer` with `drawsAsynchronously`
- Frame-synchronized `CATransaction` flushing
- `CVDisplayLink`-aligned scrolling

---

## 🙏 Credits

LumiCue is forked from **[Snapzy](https://github.com/duongductrong/Snapzy)** by [duongductrong](https://github.com/duongductrong) — a brilliant open-source screenshot & screen recording app for macOS. All original copyright and attribution are retained.

---

## 📄 License

BSD 3-Clause License, inherited from upstream Snapzy. See [LICENSE](LICENSE).
