<div align="center">
  <img src="./poster.png" width="400" alt="LumiCue poster" />

  <h1>🎤 LumiCue · 靓相 Shotlit</h1>
  <p><strong>Your invisible floating teleprompter — a little window that only you can see, no one else.</strong></p>

  <p>
    <a href="./README.zh-CN.md">🇨🇳 简体中文</a>
  </p>

  <p>
    ⚠️ <strong>macOS only.</strong> This is a beginner's fork of <a href="https://github.com/duongductrong/Snapzy">Snapzy</a> (BSD 3-Clause), stripped down into a single-purpose teleprompter.
  </p>
</div>

---

## 🇬🇧 A note first

I'm a beginner at vibe coding. This little tool is my homework — pieced together by asking AI, reading open-source code, and learning as I went.

The story is simple: I needed a teleprompter that wouldn't show up in my recordings. I found Snapzy, an incredible open-source CleanShot X alternative with a built-in teleprompter. But it came with a full menu bar, screenshot tools, recording, annotation… all of which I didn't need. So I asked myself: what if I stripped *everything* away, kept only the teleprompter, and wrapped it in a little glass bubble that's invisible to everyone but me?

That's LumiCue. It opens straight into a floating teleprompter window, and when you close it, the app quits. No menu bar, no status icon, no extra features — just a calm, pretty window that scrolls your script while you speak.

It's far from perfect, and the code surely has rough edges. Corrections and PRs are very welcome — I'm still learning.

---

## ✨ Why "LumiCue" (靓相)

"Lumi" from *luminous* — light, glow, something softly bright. "Cue" as in your next line, your prompt, your silent helper. The Chinese name 靓相 (liàng xiàng) means "beautiful presence" — a nod to the teleprompter being right there with you, invisible to your audience but making you look natural and prepared.

It's not meant to be a serious tool. It's meant to be a little companion on your screen — something you can count on, that stays out of your way and makes you better on camera.

---

## 🖼️ Poster

![LumiCue Poster](./poster.png)

---

## 💜 What it looks like

- **Glassmorphism** frosted background — semi-transparent, your work shows through
- **Animated rainbow border** — indigo → violet → pink, slowly flowing
- **A glowing progress bar** with a pulsing comet head
- **Dynamic sky** that shifts from day to dusk to night as you scroll through your script
- **12 text colors** from the Tailwind palette — soft, readable, easy on the eyes

---

## 🧩 What it can do

### 📺 Invisible by design
The window uses `sharingType = .none`. Your screen recordings, livestreams, and screenshots will never capture it. Only you see it.

### 🫧 Two shapes: Full & Pill
- **Full mode**: A resizable window with centered scrolling text, all controls, progress track, and a rescue panel
- **Pill mode**: A slim floating strip (2–3 lines at a smaller size + mini controls) — drag it to the corner, keep it out of frame

### 📝 Paste and go
- `⌘V` your script — it appears instantly, no buttons needed
- Import `.txt` files from the right-click menu
- Built-in editor that strips all invisible spaces automatically (zero-width, fullwidth, NBSP… everything), keeps your punctuation and line breaks

### 🎵 Playback
- Speed from 0.1× (slow crawl) to 2× (fast scroll)
- 12 system fonts + 3 preset window sizes (S/M/L) + manual font scaling (A-/A+)
- Spacebar to pause and resume
- Drag the progress bar to jump anywhere in your script
- `↑` to step back one line when you get stuck

### 🆘 Rescue panel
Pops up automatically when you pause, in both modes:
- **↺ Restart** the current line from the beginning
- **← Back N lines** — go back 1, 2, 3… and counting
- **▶ Resume** scrolling

### 🎤 Voice following (experimental)
Built-in on-device speech recognition in Chinese — no data leaves your machine. The teleprompter follows your voice in real time. It's rough around the edges, but it works.

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
git clone <this-repo-url>
cd LumiCue
open Snapzy.xcodeproj
```

1. Select the **Snapzy** scheme
2. Build (⌘B) and Run (⌘R)
3. The teleprompter window opens — that's it

> The Xcode project keeps the internal bundle `Snapzy` for data compatibility. All user-facing UI says **LumiCue**.

---

## 👻 Known issue: text ghosting

When scrolling, you may notice a faint double-image or ghosting on the text — more visible at high speeds or on lower-refresh external displays.

This is likely `CATextLayer` compositing interacting badly with the frosted-glass `NSVisualEffectView` backdrop. The text layers seem to leave a subtle trail during rapid position updates.

**PRs are very welcome!** Some directions to explore:
- Lower the backdrop update frequency
- Switch to `NSTextField` or `CALayer` with `drawsAsynchronously`
- Frame-synchronized `CATransaction` flushing
- `CVDisplayLink`-aligned scrolling

---

## 🙏 Credits

LumiCue is forked from **[Snapzy](https://github.com/duongductrong/Snapzy)** by [duongductrong](https://github.com/duongductrong) — a brilliant open-source screenshot & screen recording app for macOS. I took its teleprompter, stripped everything else away, and wrapped it in a new look. All original Snapzy copyright and attribution are retained.

Thank you to everyone who contributed to Snapzy — without you, a beginner like me would never have had anything to start from.

---

## 📄 License

BSD 3-Clause License, inherited from upstream Snapzy. See [LICENSE](LICENSE).
