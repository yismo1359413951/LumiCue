//
//  TeleprompterWindow.swift
//  Snapzy (靓相 Shotlit)
//
//  Invisible teleprompter 隐形提词器 — 主播看得到、录屏/直播的观众看不到。
//  关键: NSWindow.sharingType = .none → 对所有屏幕捕获/直播软件隐形。
//  右上角控制条: 暂停/播放 + 小/中/大 + 关闭✕(像浏览器, 比右键直观)。
//

import AppKit

@MainActor
final class TeleprompterWindow: NSWindow {
  private let scrollView = NSScrollView()
  private let textView = NSTextView()
  private let controlBar = NSView()
  private var playPauseButton: NSButton!
  private var timer: Timer?
  private var speed: CGFloat = 0.6
  private var playing = true

  /// 是否对录屏/直播隐形。
  var hiddenFromCapture: Bool = false {
    didSet { sharingType = hiddenFromCapture ? .none : .readOnly }
  }

  init(width: CGFloat = 680, height: CGFloat = 280) {
    super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
               styleMask: [.borderless], backing: .buffered, defer: false)
    sharingType = .readOnly
    isOpaque = false
    backgroundColor = NSColor.black.withAlphaComponent(0.62)
    hasShadow = true
    level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isMovableByWindowBackground = true

    contentView?.wantsLayer = true
    contentView?.layer?.cornerRadius = 14
    contentView?.layer?.masksToBounds = true

    // 文本滚动区
    scrollView.hasVerticalScroller = false
    scrollView.drawsBackground = false
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
    textView.textContainerInset = NSSize(width: 10, height: 40) // 上下留白, 文字不贴边被切
    textView.string = """
    把逐字稿粘贴到这里 Paste your script here

    提词器只有你看得到，录屏和直播的观众都看不到。

    念到这里时文字会自动往上滚，你照着念就行——保持微笑，看镜头。慢慢往上走……一直往上……
    """
    scrollView.documentView = textView
    contentView?.addSubview(scrollView)

    setupControlBar()
    layoutContents()
    startScrolling()
  }

  // MARK: - 右上角控制条

  private func setupControlBar() {
    func mkBtn(_ title: String, _ sel: Selector) -> NSButton {
      let b = NSButton(title: title, target: self, action: sel)
      b.isBordered = false
      b.contentTintColor = .white
      b.font = NSFont.systemFont(ofSize: 13, weight: .bold)
      b.wantsLayer = true
      b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
      b.layer?.cornerRadius = 5
      return b
    }
    playPauseButton = mkBtn("⏸", #selector(togglePlay))
    let stack = NSStackView(views: [
      playPauseButton,
      mkBtn("小", #selector(sizeSmall)),
      mkBtn("中", #selector(sizeMedium)),
      mkBtn("大", #selector(sizeLarge)),
      mkBtn("✕", #selector(closePrompter)),
    ])
    stack.orientation = .horizontal
    stack.spacing = 5
    stack.distribution = .fillEqually
    controlBar.addSubview(stack)
    stack.frame = controlBar.bounds
    stack.autoresizingMask = [.width, .height]
    contentView?.addSubview(controlBar)
  }

  private func layoutContents() {
    guard let cv = contentView else { return }
    let w = cv.bounds.width, h = cv.bounds.height
    let barH: CGFloat = 24, barW: CGFloat = 170
    controlBar.frame = NSRect(x: w - barW - 4, y: h - barH - 4, width: barW, height: barH) // 贴最右上角
    scrollView.frame = NSRect(x: 14, y: 12, width: w - 28, height: h - barH - 16)
    textView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: textView.frame.height)
    textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width,
                                                   height: CGFloat.greatestFiniteMagnitude)
  }

  /// Show near top-center (close to camera). 显示在顶部中央(靠近摄像头)。
  func show() {
    if let screen = NSScreen.main {
      let f = screen.visibleFrame
      setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - frame.height - 16))
    }
    orderFrontRegardless()
  }

  var overlayWindowID: CGWindowID { CGWindowID(windowNumber) }

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
    if y > maxY + 30 { y = 0 }
    clip.scroll(to: NSPoint(x: 0, y: y))
    scrollView.reflectScrolledClipView(clip)
  }

  // MARK: - 控制条 actions

  @objc private func togglePlay() {
    playing.toggle()
    playPauseButton.title = playing ? "⏸" : "▶"
  }

  @objc private func sizeSmall() { resize(to: 520) }
  @objc private func sizeMedium() { resize(to: 680) }
  @objc private func sizeLarge() { resize(to: 860) }

  @objc private func closePrompter() {
    timer?.invalidate()
    orderOut(nil) // 关闭(隐藏)提词器
  }

  /// 调框大小: 保持顶部中央 + 重新布局(修文字被切)。
  private func resize(to width: CGFloat) {
    let h = width * 0.42
    let top = frame.maxY, midX = frame.midX
    setFrame(NSRect(x: midX - width / 2, y: top - h, width: width, height: h), display: true)
    layoutContents()
  }

  override var canBecomeKey: Bool { true }

  // 右键补充: 速度/字号
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
}
