//
//  TeleprompterWindow.swift
//  Snapzy (靓相 Shotlit)
//
//  Invisible teleprompter 隐形提词器 — 主播看得到、录屏/直播的观众看不到。
//  关键: NSWindow.sharingType = .none → 对所有屏幕捕获/直播软件隐形。
//

import AppKit

/// A floating, auto-scrolling teleprompter only the host can see.
/// 浮动、自动滚动的提词器，只有主播自己看得到。
@MainActor
final class TeleprompterWindow: NSWindow {
  private let scrollView = NSScrollView()
  private let textView = NSTextView()
  private var timer: Timer?
  private var speed: CGFloat = 0.6 // 每帧滚动像素
  private var playing = true

  /// 是否对录屏/直播隐形。UI 确认后设 true。
  var hiddenFromCapture: Bool = false {
    didSet { sharingType = hiddenFromCapture ? .none : .readOnly }
  }

  init(width: CGFloat = 680, height: CGFloat = 280) {
    super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
               styleMask: [.borderless], backing: .buffered, defer: false)
    sharingType = .readOnly // 先可见验 UI; 设 hiddenFromCapture=true → .none 隐形
    isOpaque = false
    backgroundColor = NSColor.black.withAlphaComponent(0.62)
    hasShadow = true
    level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isMovableByWindowBackground = true

    contentView?.wantsLayer = true
    contentView?.layer?.cornerRadius = 14
    contentView?.layer?.masksToBounds = true

    scrollView.frame = NSRect(x: 18, y: 14, width: width - 36, height: height - 28)
    scrollView.autoresizingMask = [.width, .height]
    scrollView.hasVerticalScroller = false
    scrollView.drawsBackground = false

    textView.frame = scrollView.bounds
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.textContainer?.widthTracksTextView = true
    textView.isEditable = true
    textView.drawsBackground = false
    textView.textColor = .white
    textView.insertionPointColor = .white
    textView.font = NSFont.systemFont(ofSize: 30, weight: .semibold)
    textView.alignment = .center
    textView.string = """
    把逐字稿粘贴到这里 Paste your script here

    提词器只有你看得到，录屏和直播的观众都看不到。

    念到这里时文字会自动往上滚，你照着念就行——保持微笑，看镜头。慢慢往上走……一直往上……
    """
    scrollView.documentView = textView
    contentView?.addSubview(scrollView)
  }

  /// Show near the top-center (close to the camera). 显示在屏幕顶部中央(靠近摄像头)。
  func show() {
    if let screen = NSScreen.main {
      let f = screen.visibleFrame
      setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - frame.height - 16))
    }
    orderFrontRegardless()
    startScrolling()
  }

  private func startScrolling() {
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
  }

  private func tick() {
    guard playing, let doc = scrollView.documentView else { return }
    let clip = scrollView.contentView
    let maxY = max(0, doc.frame.height - clip.bounds.height)
    var y = clip.bounds.origin.y + speed
    if y > maxY + 30 { y = 0 } // 滚完循环回开头
    clip.scroll(to: NSPoint(x: 0, y: y))
    scrollView.reflectScrolledClipView(clip)
  }

  override var canBecomeKey: Bool { true }

  // MARK: - 右键调节: 速度/字号/大小/暂停  right-click to tune

  override func rightMouseUp(with event: NSEvent) {
    let menu = NSMenu()

    let speedSub = NSMenu()
    for (t, v) in [("Fast 快", 1.3), ("Medium 中", 0.6), ("Slow 慢", 0.3)] {
      let i = NSMenuItem(title: t, action: #selector(setSpeed(_:)), keyEquivalent: "")
      i.target = self; i.representedObject = v; speedSub.addItem(i)
    }
    let si = NSMenuItem(title: "Speed 速度", action: nil, keyEquivalent: "")
    menu.addItem(si); menu.setSubmenu(speedSub, for: si)

    let fontSub = NSMenu()
    for (t, v) in [("Large 大", 40.0), ("Medium 中", 30.0), ("Small 小", 22.0)] {
      let i = NSMenuItem(title: t, action: #selector(setFontSize(_:)), keyEquivalent: "")
      i.target = self; i.representedObject = v; fontSub.addItem(i)
    }
    let fi = NSMenuItem(title: "Font 字号", action: nil, keyEquivalent: "")
    menu.addItem(fi); menu.setSubmenu(fontSub, for: fi)

    let sizeSub = NSMenu()
    for (t, v) in [("Large 大", 860.0), ("Medium 中", 680.0), ("Small 小", 520.0)] {
      let i = NSMenuItem(title: t, action: #selector(setBoxSize(_:)), keyEquivalent: "")
      i.target = self; i.representedObject = v; sizeSub.addItem(i)
    }
    let zi = NSMenuItem(title: "Size 大小", action: nil, keyEquivalent: "")
    menu.addItem(zi); menu.setSubmenu(sizeSub, for: zi)

    menu.addItem(.separator())
    let pi = NSMenuItem(title: playing ? "Pause 暂停" : "Play 播放",
                        action: #selector(togglePlay), keyEquivalent: "")
    pi.target = self; menu.addItem(pi)

    if let v = contentView { NSMenu.popUpContextMenu(menu, with: event, for: v) }
  }

  @objc private func setSpeed(_ s: NSMenuItem) {
    if let v = s.representedObject as? Double { speed = CGFloat(v) }
  }

  @objc private func setFontSize(_ s: NSMenuItem) {
    if let v = s.representedObject as? Double {
      textView.font = NSFont.systemFont(ofSize: CGFloat(v), weight: .semibold)
    }
  }

  @objc private func setBoxSize(_ s: NSMenuItem) {
    guard let v = s.representedObject as? Double else { return }
    let neww = CGFloat(v), newh = CGFloat(v * 0.42)
    var f = frame
    f.size = NSSize(width: neww, height: newh)
    setFrame(f, display: true)
    scrollView.frame = NSRect(x: 18, y: 14, width: neww - 36, height: newh - 28)
  }

  @objc private func togglePlay() { playing.toggle() }
}
