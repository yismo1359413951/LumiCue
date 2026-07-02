<div align="center">
  <img src="./assets/lumi-logo.png" width="128" height="128" alt="LumiCue 图标" />

  <h1>LumiCue · 灵光提示</h1>
  <p><strong>隐形悬浮提词器 — 一块只有你看得到的毛玻璃小窗。</strong></p>

  <p>
    <a href="#english">🇬🇧 English below</a>
  </p>

  <p>
    ⚠️ <strong>仅支持 macOS。</strong>
  </p>
</div>

---

## 关于

LumiCue 是一个小小的提词器。你录视频、做直播，眼前有稿子要念——但你不想让观众看到。LumiCue 就是一块半透明的毛玻璃窗，浮在你的屏幕上方。你看着它念，观众什么都看不见。

关掉窗口就退出，没有菜单栏，没有状态图标——干干净净一块玻璃，帮你盯着镜头把稿念顺。

---

## ✅ 最新更新：v1.24.1

- **全屏演示也能浮在上面**——PowerPoint / 演示文稿全屏播放时，LumiCue 会尽量保持在幻灯片上方，不再一全屏就找不到提词窗。
- **胶囊态进度条也能拖动**——窗口收起成窄条之后，底部迷你进度条现在也可以点击和拖动，和大框里的进度条一样能直接跳到稿子任意位置。

---

## ✨ 为什么叫这个名字

**Lumi** 来自 luminous——微微发着光。**Cue** 是你的提词、你的下一句。

中文名叫「灵光提示」——念稿卡壳时，那句词刚好亮在眼前，像脑子里灵光一闪。

---

## 📸 产品预览

<img src="./poster.png" width="600" alt="LumiCue 海报" />

---

## 💜 它长什么样

- **毛玻璃**半透明底层——背后内容透得过来，文字却清清楚楚
- **彩虹流光描边**——靛蓝→紫→粉红，缓缓沿着边框流转
- **发光的进度条**，前端一颗脉冲小彗星往前跑
- **天色随念稿进度变化**——白天→黄昏→黑夜，陪你走完一段稿子
- **12 种柔和字色**——念久了眼睛不累

---

## 🧩 它能做什么

### 📺 天生隐形
窗口不会被录屏、直播、截图拍到。你的观众**永远**看不到它。只有你看得到。

现在也更适合全屏演示：PPT 全屏播放时，LumiCue 仍然可以浮在幻灯片上方，只给你自己看。

### 🫧 两种形态：念稿态 & 胶囊态
- **念稿态（大框）**：可拖拽调大小，居中滚动文字 + 全部控制 + 进度轨 + 救场面板
- **胶囊态（窄条）**：一条很窄的横条，小字 2–3 行 + 迷你控制 + 可拖动迷你进度条——拖到镜头画面角落，几乎不占地方

### 🎚️ 右下角拖拽调大小
按住窗口右下角直接拖——窗口自由缩放，字号自动跟着适配。跟调一个普通窗口一样顺手。

### 🎨 字体颜色格式随便换
- 12 种系统字体随意切
- 12 种文字颜色，点一下换一个，即时生效
- 字号独立微调（A− / A+），不跟窗口大小绑定

### 📜 滚动条随手拖
拖底部的进度条就能跳到稿子里的任意位置。念稿态和胶囊态都能拖，不用为了找位置再把窗口展开。

### ↩️ 念错了随时退
暂停一下，救场面板自动弹出：
- **↺ 重念这句**——当前句从头来
- **← 退 N 句**——退 1 句、2 句…… 累加计数，想退多远退多远
- **▶ 继续**——接着往下念

### 📝 粘贴即念
- `⌘V` 直接把稿子粘进来，当场显示
- 右键菜单导入 `.txt` 文件
- 自动清掉所有看不见的空格（零宽空格、全角空格、NBSP……全删干净），标点和换行保留

### 🎤 语音跟随（实验功能）
内置离线语音识别——数据不出你的电脑。你开口念，字幕跟着往下走。

### 🌐 中英一键切换
控制条一个按钮切换所有按钮语言。按钮显示的是**对面的语言**——中文界面显示"EN"，英文界面显示"中"。

---

## ⌨️ 快捷键

| 操作 | 按键 |
| ---- | ---- |
| 暂停 / 播放 | `空格` |
| 回退一句 | `↑` |
| 前进一句 | `↓` |
| 粘贴稿本 | `⌘V` |

---

## 🔧 构建

> 需要 **macOS 13.0** 或更高版本。

```bash
git clone <仓库地址>
cd LumiCue
open lumicue/LumiCue.xcodeproj
```

1. 选择 **LumiCue** scheme
2. 编译（⌘B）并运行（⌘R）
3. 提词器窗口立即弹出——就这样

### 打包 DMG

```bash
cd lumicue
./scripts/package-dmg.sh
```

生成的安装包会放在 `lumicue/build/` 目录下，例如 `LumiCue-v1.0.0.dmg`。

如果没有 Apple Developer 签名证书，这个 DMG 适合自己测试或小范围分发；公开下载版本建议再做签名和公证。

### 发布下载版

推送版本标签后，GitHub Actions 会自动生成 DMG 并上传到 Releases：

```bash
git tag v1.0.0
git push origin v1.0.0
```

---

## 👻 已知问题：字幕重影

滚动时，文字可能有轻微的重影/双像——高速滚动或低刷新率外接显示器上更明显。

大概率是 `CATextLayer` 合成和毛玻璃 `NSVisualEffectView` 底层在渲染管线里的交互问题。

**欢迎 PR！** 一些值得尝试的方向：
- 降低毛玻璃底层更新频率
- 文字渲染切到 `NSTextField` 或带 `drawsAsynchronously` 的 `CALayer`
- 帧同步的 `CATransaction` flush
- `CVDisplayLink` 对齐刷新的滚动

---

## 📄 许可证

BSD 3-Clause License。详见 [LICENSE](LICENSE)。

---

<a id="english"></a>

# English

<div align="center">
  <img src="./assets/lumi-logo.png" width="128" height="128" alt="LumiCue logo" />

  <h1>LumiCue · 灵光提示</h1>
  <p><strong>An invisible teleprompter — a floating glass window that only you can see.</strong></p>

  <p>
    <a href="#中文">🇨🇳 中文在上方</a>
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
open lumicue/LumiCue.xcodeproj
```

1. Select the **LumiCue** scheme
2. Build (⌘B) and Run (⌘R)
3. The teleprompter window opens — that's it

### Package DMG

```bash
cd lumicue
./scripts/package-dmg.sh
```

The installer is written to `lumicue/build/`, for example `LumiCue-v1.0.0.dmg`.

Without an Apple Developer signing certificate, this DMG is best for local testing or small private distribution. Public releases should be signed and notarized.

### Publish A Downloadable Build

Push a version tag and GitHub Actions will build the DMG and attach it to Releases:

```bash
git tag v1.0.0
git push origin v1.0.0
```

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

## 📄 License

BSD 3-Clause License. See [LICENSE](LICENSE).
