//
//  TeleprompterWindow.swift
//  Snapzy (靓相 Shotlit)
//
//  游戏化隐形提词器 — 主播看得到、录屏/直播的观众看不到。
//  隐形: NSWindow.sharingType = .none → 对所有屏幕捕获/直播软件隐形。
//
//  第 1 批 地基:
//   1. 毛玻璃背景 NSVisualEffectView — 后面内容被模糊, 文字浮其上清楚(治"透明叠字乱/纯黑挡视野")。
//   2. 逐行渲染 LinesView — 每行一个 CATextLayer, 放弃单一 NSTextView 整体滚动。
//   3. 3D 纵深 + 舞台追光 — 按"距焦点行的距离"算 scale/透明度(+轻虚化): 当前行最大最亮, 上下近大远小渐暗。
//   4. 平滑滚动 — 30fps 逐像素推进, 实时刷新各行纵深/追光过渡。
//
//  控制条: ⏸ 播放/暂停 · ✎ 编辑(粘贴/导入稿子) · 小/中/大 · 清 · ✕。
//  右键: 导入 .txt / 清空 / 速度 / 字号 / 字色。
//

import AppKit
import UniformTypeIdentifiers

// MARK: - 逐行渲染视图(3D 纵深 + 舞台追光)

/// 把脚本按行拆成 CATextLayer 竖直堆叠, 按距焦点行的距离做近大远小 + 渐暗 + 轻虚化。
@MainActor
private final class LinesView: NSView {
  // 显示参数(外部可改 → 触发重建或刷新)
  var script: String = "" { didSet { rebuild() } }
  var fontSize: CGFloat = 30 { didSet { rebuild() } }
  var fontFamily: String? = nil { didSet { rebuild() } }
  var textColor: NSColor = .white { didSet { recolor() } }

  /// 当前滚动位置(像素, 0 = 第一行在焦点)。外部 timer 推进。
  var scrollOffset: CGFloat = 0

  // 纵深/追光调参
  private let focusFrac: CGFloat = 0.40      // 焦点带在视口高度的位置(从顶 40%, 靠上更贴近镜头视线)
  private let minScale: CGFloat = 0.60       // 最远行缩到 0.60(只缩小不放大 → 文字永远清晰不糊)
  private let minOpacity: CGFloat = 0.16     // 最远行透明度
  private let lineGap: CGFloat = 10          // 行间距
  private let hPad: CGFloat = 24             // 左右留白
  var enableBlur: Bool = true               // 远行轻虚化(bucket 化, 只在档位变化时更新, 省性能)

  private var lineLayers: [CATextLayer] = []
  private var lineCenters: [CGFloat] = []    // 每行在"内容坐标"里的中心 y(从内容顶, 向下增)
  private var lineBuckets: [Int] = []        // 每行当前虚化档位(避免每帧重设 filter)
  private var contentHeight: CGFloat = 0

  override var isFlipped: Bool { true }       // 顶部为原点, y 向下增 → 文字自上而下、向上滚

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = true
  }
  required init?(coder: NSCoder) { fatalError() }

  private var scale2x: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

  private func makeFont() -> NSFont {
    if let fam = fontFamily, let f = NSFont(name: fam, size: fontSize) { return f }
    return NSFont.systemFont(ofSize: fontSize, weight: .semibold)
  }

  /// 重建所有行 layer(脚本/字号/字体/宽度变化时)。
  func rebuild() {
    lineLayers.forEach { $0.removeFromSuperlayer() }
    lineLayers.removeAll(); lineCenters.removeAll(); lineBuckets.removeAll()

    let wrapWidth = max(40, bounds.width - 2 * hPad)
    let font = makeFont()
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineBreakMode = .byWordWrapping

    let lines = script.components(separatedBy: "\n")
    var cursor: CGFloat = 0
    let emptyGap = fontSize * 0.7

    for raw in lines {
      let text = raw
      if text.trimmingCharacters(in: .whitespaces).isEmpty {
        cursor += emptyGap + lineGap   // 空行 = 段落间隙
        continue
      }
      let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: para]
      let bounding = (text as NSString).boundingRect(
        with: NSSize(width: wrapWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
      let h = ceil(bounding.height) + 4

      let tl = CATextLayer()
      tl.string = NSAttributedString(string: text, attributes: [
        .font: font, .paragraphStyle: para, .foregroundColor: textColor,
      ])
      tl.isWrapped = true
      tl.alignmentMode = .center
      tl.truncationMode = .none
      tl.contentsScale = scale2x       // 只缩小不放大, 当前行按此清晰度渲染
      tl.anchorPoint = CGPoint(x: 0.5, y: 0.5)
      tl.bounds = CGRect(x: 0, y: 0, width: wrapWidth, height: h)
      tl.masksToBounds = false
      layer?.addSublayer(tl)

      lineLayers.append(tl)
      lineCenters.append(cursor + h / 2)
      lineBuckets.append(-1)
      cursor += h + lineGap
    }
    contentHeight = cursor
    updateDepth()
  }

  /// 只改颜色, 不重建几何。
  private func recolor() {
    let font = makeFont()
    let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byWordWrapping
    let lines = script.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for (i, tl) in lineLayers.enumerated() where i < lines.count {
      tl.string = NSAttributedString(string: lines[i], attributes: [
        .font: font, .paragraphStyle: para, .foregroundColor: textColor,
      ])
    }
    CATransaction.commit()
  }

  /// 滚到尽头后回绕的阈值。
  var resetAt: CGFloat {
    guard let last = lineCenters.last, let first = lineCenters.first else { return 0 }
    return (last - first) + bounds.height * 0.55
  }

  override func layout() {
    super.layout()
    rebuild()   // 宽度变 → 换行变 → 重建
  }

  /// 每帧: 按距焦点的距离刷新 position/scale/opacity(+轻虚化)。
  func updateDepth() {
    guard !lineLayers.isEmpty, let first = lineCenters.first else { return }
    let H = bounds.height
    let focusY = H * focusFrac
    let centerX = bounds.width / 2
    let falloff = max(80, H * 0.55)

    CATransaction.begin(); CATransaction.setDisableActions(true)
    for (i, tl) in lineLayers.enumerated() {
      let centerY = focusY + (lineCenters[i] - first) - scrollOffset
      let d = abs(centerY - focusY)
      var t = min(1, d / falloff)
      t = t * t * (3 - 2 * t)                       // smoothstep, 焦点附近更突出

      let scale = 1 - (1 - minScale) * t
      let opacity = 1 - (1 - minOpacity) * t

      tl.position = CGPoint(x: centerX, y: centerY)
      tl.transform = CATransform3DMakeScale(scale, scale, 1)
      tl.opacity = Float(opacity)

      if enableBlur {
        let bucket = Int((t * 4).rounded(.down))    // 0...4, 只在档位变化时重设 filter
        if bucket != lineBuckets[i] {
          lineBuckets[i] = bucket
          let radius = CGFloat(bucket) * 1.1
          if radius > 0.01, let f = CIFilter(name: "CIGaussianBlur") {
            f.setValue(radius, forKey: kCIInputRadiusKey)
            tl.filters = [f]
          } else {
            tl.filters = []
          }
        }
      }
    }
    CATransaction.commit()
  }
}

// MARK: - 提词器窗口

@MainActor
final class TeleprompterWindow: NSWindow {
  private let effectView = NSVisualEffectView()    // 毛玻璃背景
  private let linesView = LinesView()              // 3D 逐行显示
  private let editScroll = NSScrollView()          // 编辑态: 粘贴/输入稿子
  private let editText = NSTextView()
  private let controlBar = NSView()
  private var playPauseButton: NSButton!
  private var editButton: NSButton!
  private var timer: Timer?
  private var speed: CGFloat = 0.6
  private var playing = true
  private var editing = false

  private let placeholder = """
  把逐字稿粘贴进来 — 点上面 ✎ 进入编辑

  提词器只有你看得到，录屏和直播的观众都看不到。

  当前念的这一行最大最亮，上下行往里缩、变暗，像舞台追光。照着念就行，保持微笑，看镜头。
  """

  /// 是否对录屏/直播隐形。
  var hiddenFromCapture: Bool = false {
    didSet { sharingType = hiddenFromCapture ? .none : .readOnly }
  }

  init(width: CGFloat = 680, height: CGFloat = 320) {
    super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
               styleMask: [.borderless], backing: .buffered, defer: false)
    sharingType = .readOnly
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true                                // 毛玻璃岛有淡阴影更精致
    level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isMovableByWindowBackground = true              // 拖背景挪到任意位置(自由浮动岛)

    contentView?.wantsLayer = true
    contentView?.layer?.cornerRadius = 16
    contentView?.layer?.masksToBounds = true

    // 毛玻璃: 后面窗口/桌面被模糊化, 不透出清晰内容叠字
    effectView.material = .hudWindow
    effectView.blendingMode = .behindWindow
    effectView.state = .active
    effectView.wantsLayer = true
    contentView?.addSubview(effectView)

    // 3D 逐行显示
    linesView.script = placeholder
    contentView?.addSubview(linesView)

    // 编辑态(默认隐藏)
    editScroll.hasVerticalScroller = true
    editScroll.drawsBackground = false
    editScroll.isHidden = true
    editText.minSize = NSSize(width: 0, height: 0)
    editText.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    editText.isVerticallyResizable = true
    editText.isHorizontallyResizable = false
    editText.textContainer?.widthTracksTextView = true
    editText.isRichText = false
    editText.drawsBackground = false
    editText.textColor = .white
    editText.insertionPointColor = .white
    editText.font = NSFont.systemFont(ofSize: 18, weight: .regular)
    editScroll.documentView = editText
    contentView?.addSubview(editScroll)

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
    editButton = mkBtn("✎", #selector(toggleEdit))
    let stack = NSStackView(views: [
      playPauseButton,
      editButton,
      mkBtn("小", #selector(sizeSmall)),
      mkBtn("中", #selector(sizeMedium)),
      mkBtn("大", #selector(sizeLarge)),
      mkBtn("清", #selector(clearScript)),
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
    let barH: CGFloat = 24, barW: CGFloat = 238
    effectView.frame = cv.bounds
    controlBar.frame = NSRect(x: w - barW - 6, y: h - barH - 6, width: barW, height: barH)
    let contentRect = NSRect(x: 0, y: 0, width: w, height: h - barH - 10)
    linesView.frame = contentRect
    editScroll.frame = contentRect.insetBy(dx: 16, dy: 12)
  }

  /// 显示在顶部中央(靠近摄像头), 之后可自由拖动。
  func show() {
    if let screen = NSScreen.main {
      let f = screen.visibleFrame
      setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - frame.height - 16))
    }
    orderFrontRegardless()
  }

  var overlayWindowID: CGWindowID { CGWindowID(windowNumber) }

  // MARK: - 滚动

  private func startScrolling() {
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
  }

  private func tick() {
    guard playing, !editing else { return }
    linesView.scrollOffset += speed
    if linesView.scrollOffset > linesView.resetAt { linesView.scrollOffset = 0 }
    linesView.updateDepth()
  }

  // MARK: - 控制条 actions

  @objc private func togglePlay() {
    playing.toggle()
    playPauseButton.title = playing ? "⏸" : "▶"
  }

  /// 进/出编辑态: 编辑时显示可粘贴的文本框, 退出即重建 3D 显示。
  @objc private func toggleEdit() {
    editing.toggle()
    if editing {
      editText.string = linesView.script
      editScroll.isHidden = false
      linesView.isHidden = true
      makeKeyAndOrderFront(nil)
      makeFirstResponder(editText)
    } else {
      let s = editText.string
      linesView.script = s.isEmpty ? "" : s
      linesView.scrollOffset = 0
      editScroll.isHidden = true
      linesView.isHidden = false
    }
    editButton.title = editing ? "✓" : "✎"
  }

  @objc private func sizeSmall() { resize(to: 520) }
  @objc private func sizeMedium() { resize(to: 680) }
  @objc private func sizeLarge() { resize(to: 860) }

  @objc private func closePrompter() {
    timer?.invalidate()
    orderOut(nil)
  }

  /// 调框大小: 保持顶部 + 重新布局(行会按新宽度重排)。
  private func resize(to width: CGFloat) {
    let h = width * 0.47
    let top = frame.maxY, midX = frame.midX
    setFrame(NSRect(x: midX - width / 2, y: top - h, width: width, height: h), display: true)
    layoutContents()
    linesView.needsLayout = true
  }

  override var canBecomeKey: Bool { true }

  // MARK: - 右键菜单

  override func rightMouseUp(with event: NSEvent) {
    let menu = NSMenu()

    let importItem = NSMenuItem(title: "Import .txt 导入逐字稿", action: #selector(importScript), keyEquivalent: "")
    importItem.target = self; menu.addItem(importItem)
    let clearItem = NSMenuItem(title: "Clear 清空", action: #selector(clearScript), keyEquivalent: "")
    clearItem.target = self; menu.addItem(clearItem)
    menu.addItem(.separator())

    // 速度
    let speedSub = NSMenu()
    for (t, v) in [("0.3 慢", 0.3), ("0.6", 0.6), ("1.0", 1.0), ("1.5", 1.5), ("2.0 快", 2.0)] {
      let i = NSMenuItem(title: t, action: #selector(setSpeed(_:)), keyEquivalent: "")
      i.target = self; i.representedObject = v
      i.state = (abs(speed - CGFloat(v)) < 0.01) ? .on : .off
      speedSub.addItem(i)
    }
    let si = NSMenuItem(title: "Speed 速度", action: nil, keyEquivalent: "")
    menu.addItem(si); menu.setSubmenu(speedSub, for: si)

    // 字号
    let fontSub = NSMenu()
    let cur = linesView.fontSize
    for v in [16.0, 18.0, 20.0, 24.0, 28.0, 32.0, 40.0, 48.0, 56.0] {
      let i = NSMenuItem(title: "\(Int(v)) pt", action: #selector(setFontSize(_:)), keyEquivalent: "")
      i.target = self; i.representedObject = v
      i.state = (abs(cur - CGFloat(v)) < 0.5) ? .on : .off
      fontSub.addItem(i)
    }
    let fi = NSMenuItem(title: "Font 字号", action: nil, keyEquivalent: "")
    menu.addItem(fi); menu.setSubmenu(fontSub, for: fi)

    // 字色
    let colorSub = NSMenu()
    let colors: [(String, NSColor)] = [
      ("White 白", .white), ("Yellow 黄", .systemYellow),
      ("Green 绿", .systemGreen), ("Cyan 青", .systemTeal), ("Pink 粉", .systemPink),
    ]
    for (t, c) in colors {
      let i = NSMenuItem(title: t, action: #selector(setTextColor(_:)), keyEquivalent: "")
      i.target = self; i.representedObject = c; colorSub.addItem(i)
    }
    let ci = NSMenuItem(title: "Color 字色", action: nil, keyEquivalent: "")
    menu.addItem(ci); menu.setSubmenu(colorSub, for: ci)

    if let v = contentView { NSMenu.popUpContextMenu(menu, with: event, for: v) }
  }

  @objc private func importScript() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [.plainText, .text]
    panel.message = "选一个 .txt 逐字稿文件"
    if panel.runModal() == .OK, let url = panel.url,
       let text = try? String(contentsOf: url, encoding: .utf8) {
      if editing { toggleEdit() }   // 导入后退出编辑态直接显示
      linesView.script = text
      linesView.scrollOffset = 0
    }
  }

  @objc private func clearScript() {
    if editing { editText.string = "" } else { linesView.script = "" }
  }

  @objc private func setSpeed(_ s: NSMenuItem) {
    if let v = s.representedObject as? Double { speed = CGFloat(v) }
  }

  @objc private func setFontSize(_ s: NSMenuItem) {
    if let v = s.representedObject as? Double { linesView.fontSize = CGFloat(v) }
  }

  @objc private func setTextColor(_ s: NSMenuItem) {
    if let c = s.representedObject as? NSColor {
      linesView.textColor = c
      editText.textColor = c
    }
  }
}
