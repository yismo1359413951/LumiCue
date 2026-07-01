<div align="center">
  <img src="./assets/lumi-logo.png" width="128" height="128" alt="LumiCue logo" />

  <h1>LumiCue · 灵光提示</h1>
  <p><strong>An invisible teleprompter — a floating glass window that only you can see.</strong></p>

  <p>
    <a href="./README.md">🇨🇳 简体中文</a>
  </p>

  <p>
    ⚠️ <strong>macOS only.</strong>
  </p>
</div>

---

## About

LumiCue is a tiny teleprompter for when you're on camera. You're recording a video or livestreaming — you have a script, but you don't want the audience to see it. LumiCue floats as a semi-transparent glass bubble above your screen. You read from it. They never know.

Close the window, the app quits. No menu bar clutter. No status icon. Just a quiet, polished little window that scrolls your words while you look at the lens.

---

## ✅ Latest update: v1.24.1

- **Presentation-safe floating window** — LumiCue now stays above full-screen PowerPoint / presentation spaces, so your cue window does not disappear behind your slides.
- **Draggable pill progress** — when the window is collapsed into Pill mode, the mini progress bar can now be clicked and dragged too. It jumps through the script just like the full-size progress bar.

---

## ✨ Why the name

**Lumi** from *luminous* — a soft glow above your screen. **Cue** as in your next line, your silent helper.

The Chinese name 灵光提示 (líng guāng tí shì) means "a spark of a cue" — the right word lighting up the moment you need it.

---

## 📸 Preview

<img src="./poster.png" width="600" alt="LumiCue poster" />

---

## 💜 What it looks like

- **Glassmorphism** — a frosted, semi-transparent backdrop; your desktop or video preview shows through, but the text stays crisp
- **Animated rainbow border** — indigo → violet → pink, gently flowing around the edges
- **A glowing progress bar** with a pulsing comet head that races ahead as you speak
- **Dynamic sky** — the background shifts from day → dusk → night as you progress through your script
- **12 soft text colors** — readable, easy on the eyes, never harsh

---

## 🧩 What it can do

### 📺 Invisible by design
The window is never captured in screen recordings, livestreams, or screenshots. Your audience sees nothing. Only you do.

It is also tuned for full-screen presentations: keep your slides full-screen, and LumiCue can stay floating above them for your eyes only.

### 🫧 Two shapes: Full & Pill
- **Full mode** — a resizable window with centered scrolling text, full controls, a progress track, and a rescue panel
- **Pill mode** — a slim floating strip (2–3 lines, smaller text + mini controls + draggable mini progress). Drag it to a corner, keep it out of your frame

### 🎚️ Drag to resize
Grab the bottom-right corner of the window and drag — the window scales freely, and the text size adapts with it.

### 🎨 Font style & color at your fingertips
- 12 system fonts to switch between
- 12 text colors — tap to cycle, each change applies instantly
- Font size fine-tuning (A− / A+) independent of window size

### 📜 Scroll by hand
Drag the progress bar to jump to any spot in your script. This works in both Full mode and Pill mode, so you do not need to expand the window just to scrub through your script.

### ↩️ Rewind on the spot
Pause anytime — a rescue panel pops up:
- **↺ Restart** the current line from the top
- **← Back N lines** — 1, 2, 3… keeps counting
- **▶ Resume** scrolling right where you need to be

### 📝 Paste and go
- `⌘V` your script — it shows up instantly
- Import `.txt` files from the right-click menu
- Auto-strips invisible spaces (zero-width, fullwidth, NBSP…) — keeps punctuation and line breaks intact

### 🎤 Voice following (experimental)
Built-in on-device speech recognition — your words stay on your machine. Speak, and the text follows along.

### 🌐 CN / EN toggle
One button switches all control labels between Chinese and English. The button shows the *other* language — "EN" on the Chinese UI, "中" on the English one.

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

> Why does Xcode still say **Snapzy**? LumiCue started as a focused fork of Snapzy, and the internal Xcode project / scheme still keeps that name for now. The `snapzy/` folder is the actual app source, not a leftover file. Do not delete it unless you are intentionally renaming the whole project.

---

## 👻 Known issue: text ghosting

When scrolling, you may notice a faint double-image or ghosting on the text — more visible at high speeds or on lower-refresh external displays.

Likely `CATextLayer` compositing interacting with the frosted-glass `NSVisualEffectView` backdrop.

**PRs welcome!** Some directions to explore:
- Lower the backdrop update frequency
- Switch to `NSTextField` or `CALayer` with `drawsAsynchronously`
- Frame-synchronized `CATransaction` flushing
- `CVDisplayLink`-aligned scrolling

---

## 🙏 Credits

LumiCue is a focused teleprompter fork of **[Snapzy](https://github.com/duongductrong/Snapzy)** by [duongductrong](https://github.com/duongductrong). Original copyright and BSD 3-Clause notices are retained.

---

## 📄 License

BSD 3-Clause License. See [LICENSE](LICENSE).
