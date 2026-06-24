//
//  TeleprompterWindow.swift
//  Snapzy (靓相 Shotlit)
//
//  游戏化隐形提词器 — 主播看得到、录屏/直播的观众看不到(sharingType=.none)。
//
//  统一游戏体验(给念稿人自己的单人沉浸, 观众隐形看不到):
//   · 地基: 毛玻璃 NSVisualEffectView + 逐行 CATextLayer 3D纵深 + 舞台追光 + 平滑滚动。
//   · 🎵 节奏: 焦点行随滚动逐字点亮(卡拉OK), 念完一行迸火花 + COMBO 连击跳动。
//   · 🌄 旅程: 背景天色随进度 白天→黄昏→星空; 底部光之路, 念完到终点放烟花🎆。
//   · 🐱 精灵: 小猫沿路陪走, 念顺蹦跳冒爱心 / 暂停打盹 / 念完庆祝。
//
//  控制条: ⏸ · ✎编辑 · 小/中/大 · 清 · ✕。 右键: 导入txt/清空/速度/字号/字色。 ⌘V 直接粘稿。
//

import AppKit
import UniformTypeIdentifiers
import Speech
import AVFoundation

// MARK: - 语音跟随引擎(本地识别, 你说到哪滚到哪)

@MainActor
final class VoiceFollower: NSObject {
  private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
  private let audioEngine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  var onTranscript: ((String) -> Void)?
  var onStatus: ((String) -> Void)?
  private(set) var running = false

  func start() {
    SFSpeechRecognizer.requestAuthorization { [weak self] auth in
      DispatchQueue.main.async {
        guard auth == .authorized else { self?.onStatus?("没拿到语音识别权限(系统设置→隐私)"); return }
        self?.beginAudio()
      }
    }
  }

  private func beginAudio() {
    guard let recognizer, recognizer.isAvailable else { onStatus?("中文识别暂不可用"); return }
    task?.cancel(); task = nil
    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true } // 本地优先, 不上传
    request = req
    let input = audioEngine.inputNode
    let fmt = input.outputFormat(forBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
      self?.request?.append(buf)
    }
    audioEngine.prepare()
    do { try audioEngine.start() } catch { onStatus?("麦克风启动失败"); return }
    running = true
    onStatus?("🎤 语音跟随中：开口念，字跟着你走")
    task = recognizer.recognitionTask(with: req) { [weak self] result, err in
      if let r = result { self?.onTranscript?(r.bestTranscription.formattedString) }
      if err != nil || (result?.isFinal ?? false) { self?.restartIfRunning() } // 停顿后自动续, 长时间跟随
    }
  }

  private func restartIfRunning() {
    guard running else { return }
    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
    request?.endAudio(); request = nil; task = nil
    beginAudio()
  }

  func stop() {
    running = false
    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
    request?.endAudio(); request = nil
    task?.cancel(); task = nil
  }
}

// MARK: - 逐行渲染视图(3D 纵深 + 追光 + 卡拉OK 逐字)

@MainActor
private final class LinesView: NSView {
  var script: String = "" { didSet { rebuild() } }
  var fontSize: CGFloat = 30 { didSet { rebuild() } }
  var fontFamily: String? = nil { didSet { rebuild() } }
  var textColor: NSColor = .white { didSet { recolor() } }
  var highlightColor: NSColor = .systemYellow

  var scrollOffset: CGFloat = 0
  var enableBlur: Bool = true
  var enableKaraoke: Bool = true
  /// 一行念完(逐字点亮走完)时回调 → 连击/火花。仅播放时上层处理。
  var onLineComplete: (() -> Void)?

  private let focusFrac: CGFloat = 0.40
  private let minScale: CGFloat = 0.60
  private let minOpacity: CGFloat = 0.16
  private let lineGap: CGFloat = 10
  private let hPad: CGFloat = 24

  private var lineLayers: [CATextLayer] = []
  private var lineCenters: [CGFloat] = []
  private var lineHeights: [CGFloat] = []
  private var lineTexts: [String] = []
  private var lineCharCounts: [Int] = []
  private var lineHi: [Int] = []
  private var lineBuckets: [Int] = []
  private var curFont: NSFont = .systemFont(ofSize: 30, weight: .semibold)
  private let curPara: NSMutableParagraphStyle = {
    let p = NSMutableParagraphStyle(); p.alignment = .center; p.lineBreakMode = .byWordWrapping; return p
  }()

  var progress: CGFloat { resetAt > 0 ? max(0, min(1, scrollOffset / resetAt)) : 0 }
  /// 焦点中心在视口里的 y(从顶), 上层放精灵/火花用。
  var focusViewportY: CGFloat { bounds.height * focusFrac }

  override var isFlipped: Bool { true }

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

  func rebuild() {
    lineLayers.forEach { $0.removeFromSuperlayer() }
    lineLayers.removeAll(); lineCenters.removeAll(); lineBuckets.removeAll()
    lineHeights.removeAll(); lineTexts.removeAll(); lineCharCounts.removeAll(); lineHi.removeAll()

    let wrapWidth = max(40, bounds.width - 2 * hPad)
    curFont = makeFont()
    let emptyGap = fontSize * 0.7
    var cursor: CGFloat = 0

    for raw in script.components(separatedBy: "\n") {
      if raw.trimmingCharacters(in: .whitespaces).isEmpty { cursor += emptyGap + lineGap; continue }
      let attrs: [NSAttributedString.Key: Any] = [.font: curFont, .paragraphStyle: curPara]
      let bounding = (raw as NSString).boundingRect(
        with: NSSize(width: wrapWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
      let h = ceil(bounding.height) + 4

      let tl = CATextLayer()
      tl.string = NSAttributedString(string: raw, attributes: [
        .font: curFont, .paragraphStyle: curPara, .foregroundColor: textColor])
      tl.isWrapped = true
      tl.alignmentMode = .center
      tl.truncationMode = .none
      tl.contentsScale = scale2x
      tl.anchorPoint = CGPoint(x: 0.5, y: 0.5)
      tl.bounds = CGRect(x: 0, y: 0, width: wrapWidth, height: h)
      tl.masksToBounds = false
      layer?.addSublayer(tl)

      lineLayers.append(tl)
      lineCenters.append(cursor + h / 2)
      lineHeights.append(h)
      lineTexts.append(raw)
      lineCharCounts.append((raw as NSString).length)
      lineHi.append(-1)
      lineBuckets.append(-1)
      cursor += h + lineGap
    }
    updateDepth()
  }

  private func applyKaraoke(_ i: Int, _ n: Int) {
    let s = lineTexts[i]
    let full = NSMutableAttributedString(string: s, attributes: [
      .font: curFont, .paragraphStyle: curPara, .foregroundColor: textColor])
    let len = (s as NSString).length
    if n > 0 { full.addAttribute(.foregroundColor, value: highlightColor, range: NSRange(location: 0, length: min(n, len))) }
    lineLayers[i].string = full
  }

  private func applyPlain(_ i: Int) {
    lineLayers[i].string = NSAttributedString(string: lineTexts[i], attributes: [
      .font: curFont, .paragraphStyle: curPara, .foregroundColor: textColor])
  }

  private func recolor() {
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for i in lineLayers.indices { applyPlain(i); lineHi[i] = -1 }
    CATransaction.commit()
  }

  var resetAt: CGFloat {
    guard let last = lineCenters.last, let first = lineCenters.first else { return 0 }
    return (last - first) + bounds.height * 0.55
  }

  /// 卡壳救急: 把焦点跳到相邻一句(dir=-1 上一句重念 / +1 下一句)。
  func stepLine(_ dir: Int) {
    guard !lineCenters.isEmpty, let first = lineCenters.first else { return }
    let focusContentY = first + scrollOffset
    var idx = 0; var best = CGFloat.greatestFiniteMagnitude
    for (i, c) in lineCenters.enumerated() {
      let d = abs(c - focusContentY); if d < best { best = d; idx = i }
    }
    let target = max(0, min(lineCenters.count - 1, idx + dir))
    scrollOffset = lineCenters[target] - first
  }

  // 语音跟随用
  var lineCount: Int { lineTexts.count }
  func textOfLine(_ i: Int) -> String { (i >= 0 && i < lineTexts.count) ? lineTexts[i] : "" }
  /// 当前焦点行序号(离焦点最近)。
  var currentLineIndex: Int {
    guard !lineCenters.isEmpty, let first = lineCenters.first else { return 0 }
    let f = first + scrollOffset
    var idx = 0; var best = CGFloat.greatestFiniteMagnitude
    for (i, c) in lineCenters.enumerated() { let d = abs(c - f); if d < best { best = d; idx = i } }
    return idx
  }
  /// 直接把第 i 行对到焦点(语音跟随驱动)。
  func focusLine(_ i: Int) {
    guard i >= 0, i < lineCenters.count, let first = lineCenters.first else { return }
    scrollOffset = lineCenters[i] - first
  }

  /// 重念这句: 把当前焦点行挪到刚进焦点的位置, 从这句开头重念。
  func restartCurrentLine() {
    guard !lineCenters.isEmpty, let first = lineCenters.first else { return }
    let focusContentY = first + scrollOffset
    var idx = 0; var best = CGFloat.greatestFiniteMagnitude
    for (i, c) in lineCenters.enumerated() {
      let d = abs(c - focusContentY); if d < best { best = d; idx = i }
    }
    let band = max(36, lineHeights[idx])
    scrollOffset = lineCenters[idx] - first - band / 2
  }

  override func layout() { super.layout(); rebuild() }

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
      t = t * t * (3 - 2 * t)

      tl.position = CGPoint(x: centerX, y: centerY)
      tl.transform = CATransform3DMakeScale(1 - (1 - minScale) * t, 1 - (1 - minScale) * t, 1)
      tl.opacity = Float(1 - (1 - minOpacity) * t)

      if enableKaraoke {
        let band = max(36, lineHeights[i])
        let readP = max(0, min(1, (focusY + band / 2 - centerY) / band))
        let count = lineCharCounts[i]
        if readP > 0.001 && readP < 0.999 && count > 0 {
          let n = max(0, min(count, Int((readP * CGFloat(count)).rounded())))
          if lineHi[i] != n { applyKaraoke(i, n); lineHi[i] = n }
        } else if lineHi[i] != -1 {
          if readP >= 0.999 && lineHi[i] >= 1 { onLineComplete?() }  // 整行念完 → 连击/火花
          applyPlain(i); lineHi[i] = -1
        }
      }

      if enableBlur {
        let bucket = Int((t * 4).rounded(.down))
        if bucket != lineBuckets[i] {
          lineBuckets[i] = bucket
          let radius = CGFloat(bucket) * 1.1
          if radius > 0.01, let f = CIFilter(name: "CIGaussianBlur") {
            f.setValue(radius, forKey: kCIInputRadiusKey); tl.filters = [f]
          } else { tl.filters = [] }
        }
      }
    }
    CATransaction.commit()
  }
}

// MARK: - 特效层(火花/烟花/爱心, 不挡鼠标拖窗)

@MainActor
private final class FXView: NSView {
  override init(frame frameRect: NSRect) { super.init(frame: frameRect); wantsLayer = true }
  required init?(coder: NSCoder) { fatalError() }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }   // 事件穿透 → 不挡拖动/点击
}

// MARK: - 提词器窗口

@MainActor
final class TeleprompterWindow: NSWindow {
  private let effectView = NSVisualEffectView()
  private let skyView = NSView()                    // 天色(随进度 白天→黄昏→星空)
  private let skyGradient = CAGradientLayer()
  private let linesView = LinesView()
  private let fxView = FXView()                     // 火花/烟花/爱心
  private let editScroll = NSScrollView()
  private let editText = NSTextView()
  private let controlBar = NSView()

  // 底部"光之路"+精灵+连击
  private let journeyBar = NSView()
  private let trackLayer = CALayer()
  private let trackFill = CALayer()
  private let spriteLayer = CATextLayer()           // 🐱 小猫精灵(沿路走)
  private let flagLayer = CATextLayer()             // 🏁 终点
  private let comboLayer = CATextLayer()            // 🔥 连击数

  private var playPauseButton: NSButton!
  private var editButton: NSButton!
  private var voiceButton: NSButton!        // 🎤 语音跟随开关
  private let voiceFollower = VoiceFollower()
  private var voiceMode = false
  private var voiceLine = 0
  private var rescuePanel: NSView!          // 卡壳救场面板(暂停时出现)
  private var rescueStack: NSStackView!
  private var retreatButton: NSButton!
  private var retreatCount = 0
  private var timer: Timer?
  private var speed: CGFloat = 0.4
  private var playing = true
  private var editing = false

  // 游戏状态
  private var combo = 0
  private var frameTick = 0
  private var finished = false
  private let spritePool = ["🐱", "🐰", "🐶", "🐥", "🦊", "🐼", "🐨", "🐯", "🦄", "🐧"]
  private func currentCat() -> String { spritePool[combo % spritePool.count] }   // 念完一句随机换形象

  private let placeholder = """
  把逐字稿粘贴进来 — 点上面 ✎ 编辑，或直接 ⌘V

  提词器只有你看得到，录屏和直播的观众都看不到。

  跟着滚动的节奏念：当前这行最大最亮，念到的字会点亮，念完一行火花一闪、连击 +1。小猫陪你走过这趟光之路，念到结尾会放烟花。
  """

  var hiddenFromCapture: Bool = false {
    didSet { sharingType = hiddenFromCapture ? .none : .readOnly }
  }

  init(width: CGFloat = 680, height: CGFloat = 320) {
    super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
               styleMask: [.borderless], backing: .buffered, defer: false)
    sharingType = .readOnly
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isMovableByWindowBackground = true

    contentView?.wantsLayer = true
    contentView?.layer?.cornerRadius = 16
    contentView?.layer?.masksToBounds = true

    // 毛玻璃(最底)
    effectView.material = .hudWindow
    effectView.blendingMode = .behindWindow
    effectView.state = .active
    effectView.wantsLayer = true
    contentView?.addSubview(effectView)

    // 天色(玻璃之上、文字之下)
    skyView.wantsLayer = true
    skyGradient.startPoint = CGPoint(x: 0.5, y: 0)
    skyGradient.endPoint = CGPoint(x: 0.5, y: 1)
    skyView.layer?.addSublayer(skyGradient)
    contentView?.addSubview(skyView)

    // 3D 文字
    linesView.script = placeholder
    linesView.onLineComplete = { [weak self] in self?.onLineComplete() }
    contentView?.addSubview(linesView)

    // 特效(文字之上)
    contentView?.addSubview(fxView)

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
    setupJourney()
    setupRescue()
    layoutContents()
    startScrolling()
  }

  // MARK: - 控制条

  private func setupControlBar() {
    func mkBtn(_ title: String, _ sel: Selector) -> NSButton {
      let b = NSButton(title: title, target: self, action: sel)
      b.isBordered = false; b.contentTintColor = .white
      b.font = NSFont.systemFont(ofSize: 13, weight: .bold)
      b.wantsLayer = true
      b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
      b.layer?.cornerRadius = 5
      return b
    }
    playPauseButton = mkBtn("⏸", #selector(togglePlay))
    editButton = mkBtn("编辑", #selector(toggleEdit))
    voiceButton = mkBtn("🎤", #selector(toggleVoice))
    let stack = NSStackView(views: [
      mkBtn("⏪", #selector(stepBack)), playPauseButton, voiceButton, editButton,
      mkBtn("小", #selector(sizeSmall)), mkBtn("中", #selector(sizeMedium)), mkBtn("大", #selector(sizeLarge)),
      mkBtn("清", #selector(clearScript)), mkBtn("✕", #selector(closePrompter)),
    ])
    stack.orientation = .horizontal; stack.spacing = 5; stack.distribution = .fillEqually
    controlBar.addSubview(stack)
    stack.frame = controlBar.bounds
    stack.autoresizingMask = [.width, .height]
    contentView?.addSubview(controlBar)
  }

  // MARK: - 底部光之路 + 精灵 + 连击

  private func setupJourney() {
    journeyBar.wantsLayer = true
    trackLayer.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
    trackLayer.cornerRadius = 2
    trackFill.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.7).cgColor
    trackFill.cornerRadius = 2
    let s = screenScale
    spriteLayer.string = "🐱"; spriteLayer.fontSize = 20
    flagLayer.string = "🏁"; flagLayer.fontSize = 15
    for l in [spriteLayer, flagLayer] {
      l.alignmentMode = .center; l.contentsScale = s
      l.anchorPoint = CGPoint(x: 0.5, y: 0.5); l.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
    }
    comboLayer.fontSize = 13; comboLayer.alignmentMode = .left; comboLayer.contentsScale = s
    comboLayer.anchorPoint = CGPoint(x: 0, y: 0.5); comboLayer.bounds = CGRect(x: 0, y: 0, width: 90, height: 20)
    comboLayer.string = ""
    journeyBar.layer?.addSublayer(trackLayer)
    journeyBar.layer?.addSublayer(trackFill)
    journeyBar.layer?.addSublayer(flagLayer)
    journeyBar.layer?.addSublayer(spriteLayer)
    journeyBar.layer?.addSublayer(comboLayer)
    contentView?.addSubview(journeyBar)
  }

  // MARK: - 卡壳救场面板(暂停时出现)

  private func setupRescue() {
    rescuePanel = NSView()
    rescuePanel.wantsLayer = true
    rescuePanel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.30).cgColor
    rescuePanel.layer?.cornerRadius = 10
    rescuePanel.isHidden = true
    func mk(_ t: String, _ s: Selector) -> NSButton {
      let b = NSButton(title: t, target: self, action: s)
      b.isBordered = false; b.contentTintColor = .white
      b.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
      b.wantsLayer = true
      b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
      b.layer?.cornerRadius = 7
      return b
    }
    retreatButton = mk("← 退1句", #selector(rescueRetreat))
    rescueStack = NSStackView(views: [
      mk("↺ 重念这句", #selector(rescueRestart)),
      retreatButton,
      mk("▶ 继续", #selector(rescueResume)),
    ])
    rescueStack.orientation = .horizontal; rescueStack.spacing = 8; rescueStack.distribution = .fillEqually
    rescuePanel.addSubview(rescueStack)
    contentView?.addSubview(rescuePanel)
  }

  private var screenScale: CGFloat { screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

  private func layoutContents() {
    guard let cv = contentView else { return }
    let w = cv.bounds.width, h = cv.bounds.height
    let barH: CGFloat = 24, barW: CGFloat = 322, journeyH: CGFloat = 30
    effectView.frame = cv.bounds
    skyView.frame = cv.bounds
    skyGradient.frame = cv.bounds
    fxView.frame = cv.bounds
    controlBar.frame = NSRect(x: w - barW - 6, y: h - barH - 6, width: barW, height: barH)

    journeyBar.frame = NSRect(x: 0, y: 2, width: w, height: journeyH)
    let comboW: CGFloat = 78, flagW: CGFloat = 22, trackY: CGFloat = 13, trackH: CGFloat = 4
    let left = 12 + comboW, right = w - 14 - flagW
    comboLayer.position = CGPoint(x: 12, y: trackY + trackH / 2)
    trackLayer.frame = CGRect(x: left, y: trackY, width: max(1, right - left), height: trackH)
    flagLayer.position = CGPoint(x: right + flagW / 2, y: trackY + trackH / 2)

    let contentRect = NSRect(x: 0, y: journeyH + 4, width: w, height: h - barH - journeyH - 14)
    linesView.frame = contentRect
    editScroll.frame = contentRect.insetBy(dx: 16, dy: 12)

    let rpW = min(w - 40, 380), rpH: CGFloat = 40
    rescuePanel.frame = NSRect(x: (w - rpW) / 2, y: journeyH + 12, width: rpW, height: rpH)
    rescueStack.frame = rescuePanel.bounds.insetBy(dx: 8, dy: 6)
    updateJourney()
  }

  func show() {
    if let screen = NSScreen.main {
      let f = screen.visibleFrame
      setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - frame.height - 16))
    }
    orderFrontRegardless()
  }

  var overlayWindowID: CGWindowID { CGWindowID(windowNumber) }

  // MARK: - 滚动 + 游戏循环

  private func startScrolling() {
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
  }

  private func tick() {
    frameTick += 1
    guard playing, !editing else { return }
    if voiceMode { return }   // 语音模式: 滚动由你说话驱动, 不自动推进
    linesView.scrollOffset += speed
    if linesView.scrollOffset > linesView.resetAt {     // 念完一遍 → 回到开头, 重置游戏
      linesView.scrollOffset = 0
      combo = 0; finished = false
      refreshCombo(pulse: false)
    }
    linesView.updateDepth()
    updateJourney()

    if !finished, linesView.progress >= 0.992 {          // 抵达终点 → 烟花庆祝
      finished = true
      spriteLayer.string = "🥳"
      fireworks()
    }
  }

  /// 进度条填充 + 精灵沿路走 + 上下轻轻颠(陪走感) + 天色随进度。
  private func updateJourney() {
    let p = linesView.progress
    let t = trackLayer.frame
    let bob = sin(CGFloat(frameTick) * 0.18) * 2.5
    CATransaction.begin(); CATransaction.setDisableActions(true)
    trackFill.frame = CGRect(x: t.minX, y: t.minY, width: max(0.1, t.width * p), height: t.height)
    spriteLayer.position = CGPoint(x: t.minX + t.width * p, y: t.midY + 4 + (playing ? bob : 0))
    skyGradient.colors = skyColors(p)
    CATransaction.commit()
  }

  /// 天色: 白天(浅蓝) → 黄昏(橙紫) → 星空(深蓝)。半透明叠在毛玻璃上, 保可读。
  private func skyColors(_ p: CGFloat) -> [CGColor] {
    func mix(_ a: NSColor, _ b: NSColor, _ k: CGFloat) -> NSColor {
      let k = max(0, min(1, k))
      return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * k,
                     green: a.greenComponent + (b.greenComponent - a.greenComponent) * k,
                     blue: a.blueComponent + (b.blueComponent - a.blueComponent) * k,
                     alpha: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * k)
    }
    // 马卡龙色系: 薄荷→蜜桃→薰衣草。天色在文字下层, 提高 alpha+明度盖住深玻璃 → 鲜亮不发灰
    let dayTop = NSColor(srgbRed: 0.66, green: 0.97, blue: 0.85, alpha: 0.72)   // 薄荷绿
    let dayBot = NSColor(srgbRed: 0.74, green: 0.93, blue: 1.0, alpha: 0.55)    // 浅天蓝
    let duskTop = NSColor(srgbRed: 1.0, green: 0.74, blue: 0.80, alpha: 0.74)   // 蜜桃粉
    let duskBot = NSColor(srgbRed: 1.0, green: 0.88, blue: 0.66, alpha: 0.58)   // 鹅黄
    let nightTop = NSColor(srgbRed: 0.74, green: 0.68, blue: 1.0, alpha: 0.76)  // 薰衣草紫
    let nightBot = NSColor(srgbRed: 0.86, green: 0.78, blue: 1.0, alpha: 0.60)  // 丁香
    let top: NSColor, bot: NSColor
    if p < 0.5 { top = mix(dayTop, duskTop, p / 0.5); bot = mix(dayBot, duskBot, p / 0.5) }
    else { top = mix(duskTop, nightTop, (p - 0.5) / 0.5); bot = mix(duskBot, nightBot, (p - 0.5) / 0.5) }
    return [top.cgColor, bot.cgColor]
  }

  // MARK: - 连击 / 火花

  /// 念完一行 → 连击 +1、火花、精灵蹦一下; 每 5 连击撒爱心。
  private func onLineComplete() {
    guard playing else { return }
    combo += 1
    refreshCombo(pulse: true)
    spark(at: focusPoint())
    if !finished { spriteLayer.string = currentCat() }   // 每念完一句换一只
    hopSprite()
    if combo % 5 == 0 { hearts(at: spritePointInFX()) }
  }

  private func refreshCombo(pulse: Bool) {
    let s = NSMutableAttributedString(string: combo >= 2 ? "🔥 连念 \(combo) 句" : "",
      attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .heavy),
                   .foregroundColor: NSColor.systemOrange])
    comboLayer.string = s
    guard pulse, combo >= 2 else { return }
    let a = CABasicAnimation(keyPath: "transform.scale")
    a.fromValue = 1.5; a.toValue = 1.0; a.duration = 0.25
    comboLayer.add(a, forKey: "pop")
  }

  /// 焦点行中心在 fxView 里的点(非翻转, 左下原点)。
  private func focusPoint() -> CGPoint {
    let yTop = linesView.focusViewportY            // 从顶
    return CGPoint(x: fxView.bounds.midX, y: linesView.frame.maxY - yTop)
  }
  private func spritePointInFX() -> CGPoint {
    CGPoint(x: spriteLayer.position.x, y: journeyBar.frame.minY + spriteLayer.position.y)
  }

  private func hopSprite() {
    let a = CABasicAnimation(keyPath: "position.y")
    let y = spriteLayer.position.y
    a.fromValue = y; a.toValue = y + 9; a.duration = 0.16
    a.autoreverses = true; a.timingFunction = CAMediaTimingFunction(name: .easeOut)
    spriteLayer.add(a, forKey: "hop")
  }

  /// 一簇短促火花。
  private func spark(at p: CGPoint) {
    let emitter = CAEmitterLayer()
    emitter.emitterPosition = p
    emitter.emitterShape = .point
    emitter.birthRate = 1
    let cell = CAEmitterCell()
    cell.birthRate = 60; cell.lifetime = 0.5; cell.velocity = 90; cell.velocityRange = 40
    cell.emissionRange = .pi * 2; cell.scale = 0.10; cell.scaleRange = 0.05
    cell.alphaSpeed = -2.0; cell.contents = dotImage(.systemYellow)
    emitter.emitterCells = [cell]
    fxView.layer?.addSublayer(emitter)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { emitter.birthRate = 0 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { emitter.removeFromSuperlayer() }
  }

  /// 爱心冒泡(连击里程碑)。
  private func hearts(at p: CGPoint) {
    let emitter = CAEmitterLayer()
    emitter.emitterPosition = p
    emitter.emitterShape = .point
    emitter.birthRate = 1
    let cell = CAEmitterCell()
    cell.birthRate = 14; cell.lifetime = 1.0; cell.velocity = 50; cell.velocityRange = 20
    cell.emissionLongitude = -.pi / 2; cell.emissionRange = .pi / 5
    cell.yAcceleration = -40; cell.scale = 0.5; cell.scaleRange = 0.2; cell.alphaSpeed = -1.0
    cell.contents = emojiImage("❤️", size: 22)
    emitter.emitterCells = [cell]
    fxView.layer?.addSublayer(emitter)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { emitter.birthRate = 0 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { emitter.removeFromSuperlayer() }
  }

  /// 念完撒烟花。
  private func fireworks() {
    let colors: [NSColor] = [.systemPink, .systemYellow, .systemTeal, .systemGreen, .systemOrange]
    for (i, c) in colors.enumerated() {
      let x = fxView.bounds.width * (0.2 + 0.15 * CGFloat(i))
      let p = CGPoint(x: x, y: fxView.bounds.height * 0.6)
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) { [weak self] in
        self?.burst(at: p, color: c)
      }
    }
  }

  private func burst(at p: CGPoint, color: NSColor) {
    let emitter = CAEmitterLayer()
    emitter.emitterPosition = p; emitter.emitterShape = .point; emitter.birthRate = 1
    let cell = CAEmitterCell()
    cell.birthRate = 200; cell.lifetime = 0.9; cell.velocity = 150; cell.velocityRange = 60
    cell.emissionRange = .pi * 2; cell.yAcceleration = 80
    cell.scale = 0.12; cell.scaleRange = 0.06; cell.alphaSpeed = -1.1; cell.contents = dotImage(color)
    emitter.emitterCells = [cell]
    fxView.layer?.addSublayer(emitter)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { emitter.birthRate = 0 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { emitter.removeFromSuperlayer() }
  }

  // 粒子贴图
  private func dotImage(_ color: NSColor) -> CGImage? {
    let d = 12
    let img = NSImage(size: NSSize(width: d, height: d))
    img.lockFocus()
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: d - 2, height: d - 2)).fill()
    img.unlockFocus()
    var r = NSRect(x: 0, y: 0, width: d, height: d)
    return img.cgImage(forProposedRect: &r, context: nil, hints: nil)
  }
  private func emojiImage(_ s: String, size: CGFloat) -> CGImage? {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    (s as NSString).draw(at: .zero, withAttributes: [.font: NSFont.systemFont(ofSize: size * 0.85)])
    img.unlockFocus()
    var r = NSRect(x: 0, y: 0, width: size, height: size)
    return img.cgImage(forProposedRect: &r, context: nil, hints: nil)
  }

  // MARK: - 控制条 actions

  @objc private func togglePlay() {
    playing.toggle()
    playPauseButton.title = playing ? "⏸" : "▶"
    if !finished { spriteLayer.string = playing ? currentCat() : "😴" }   // 暂停打盹
    rescuePanel.isHidden = playing || editing                            // 暂停=出救场面板
    if !playing { retreatCount = 0; retreatButton.title = "← 退1句" }
  }

  @objc private func toggleEdit() {
    editing.toggle()
    if editing {
      editText.string = linesView.script
      editScroll.isHidden = false; linesView.isHidden = true; fxView.isHidden = true
      rescuePanel.isHidden = true
      makeKeyAndOrderFront(nil); makeFirstResponder(editText)
    } else {
      linesView.script = editText.string
      linesView.scrollOffset = 0; combo = 0; finished = false; refreshCombo(pulse: false)
      spriteLayer.string = playing ? currentCat() : "😴"
      editScroll.isHidden = true; linesView.isHidden = false; fxView.isHidden = false
    }
    editButton.title = editing ? "完成" : "编辑"
  }

  @objc private func sizeSmall() { resize(to: 520) }
  @objc private func sizeMedium() { resize(to: 680) }
  @objc private func sizeLarge() { resize(to: 860) }

  @objc private func closePrompter() { timer?.invalidate(); orderOut(nil) }

  private func resize(to width: CGFloat) {
    let h = width * 0.47
    let top = frame.maxY, midX = frame.midX
    setFrame(NSRect(x: midX - width / 2, y: top - h, width: width, height: h), display: true)
    layoutContents()
    linesView.needsLayout = true
  }

  override var canBecomeKey: Bool { true }

  /// 快捷键: ⌘V 直接粘稿 · 空格 暂停/播放 · ↑回退一句(卡壳) · ↓前进一句。编辑态不拦。
  override func keyDown(with event: NSEvent) {
    let cmdV = event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "v"
    if cmdV, !editing, let s = NSPasteboard.general.string(forType: .string), !s.isEmpty {
      linesView.script = s
      linesView.scrollOffset = 0; combo = 0; finished = false; refreshCombo(pulse: false)
      return
    }
    if !editing {
      switch event.keyCode {
      case 49: togglePlay(); return                                            // 空格 暂停/播放
      case 126: linesView.stepLine(-1); linesView.updateDepth(); updateJourney(); return   // ↑ 回退一句
      case 125: linesView.stepLine(1); linesView.updateDepth(); updateJourney(); return    // ↓ 前进一句
      default: break
      }
    }
    super.keyDown(with: event)
  }

  // MARK: - 右键菜单

  override func rightMouseUp(with event: NSEvent) {
    let menu = NSMenu()
    let importItem = NSMenuItem(title: "Import .txt 导入逐字稿", action: #selector(importScript), keyEquivalent: "")
    importItem.target = self; menu.addItem(importItem)
    let clearItem = NSMenuItem(title: "Clear 清空", action: #selector(clearScript), keyEquivalent: "")
    clearItem.target = self; menu.addItem(clearItem)
    menu.addItem(.separator())

    let speedSub = NSMenu()
    for (t, v) in [("0.1 最慢", 0.1), ("0.2", 0.2), ("0.3", 0.3), ("0.4", 0.4), ("0.5", 0.5),
                   ("0.6", 0.6), ("0.7", 0.7), ("1.2 ⏩ 加速", 1.2), ("2.0 ⏩⏩ 快进", 2.0)] {
      let i = NSMenuItem(title: t, action: #selector(setSpeed(_:)), keyEquivalent: "")
      i.target = self; i.representedObject = v
      i.state = (abs(speed - CGFloat(v)) < 0.01) ? .on : .off
      speedSub.addItem(i)
    }
    let si = NSMenuItem(title: "Speed 速度", action: nil, keyEquivalent: "")
    menu.addItem(si); menu.setSubmenu(speedSub, for: si)

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

    let colorSub = NSMenu()
    let colors: [(String, NSColor)] = [
      ("White 白", .white), ("Yellow 黄", .systemYellow),
      ("Green 绿", .systemGreen), ("Cyan 青", .systemTeal), ("Pink 粉", .systemPink)]
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
    panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
    panel.allowedContentTypes = [.plainText, .text]
    panel.message = "选一个 .txt 逐字稿文件"
    if panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) {
      if editing { toggleEdit() }
      linesView.script = text
      linesView.scrollOffset = 0; combo = 0; finished = false; refreshCombo(pulse: false)
    }
  }

  /// 清空: 显示态下清空后直接进编辑态(光标就绪), 你直接 ⌘V 粘新稿。
  @objc private func clearScript() {
    if editing { editText.string = "" }
    else { linesView.script = ""; toggleEdit() }
  }

  /// ⏪ 卡壳救急: 回退到上一句重念。
  @objc private func stepBack() {
    linesView.stepLine(-1)
    linesView.updateDepth()
    updateJourney()
  }

  // 卡壳救场面板按钮
  @objc private func rescueRestart() { linesView.restartCurrentLine(); linesView.updateDepth(); updateJourney() }
  @objc private func rescueRetreat() {
    retreatCount += 1
    linesView.stepLine(-1); linesView.updateDepth(); updateJourney()
    retreatButton.title = "← 退\(retreatCount)句"
  }
  @objc private func rescueResume() { if !playing { togglePlay() } }

  // MARK: - 🎤 语音跟随

  @objc private func toggleVoice() {
    voiceMode.toggle()
    // emoji 不吃 contentTintColor → 用按钮背景变绿做反馈
    voiceButton.layer?.backgroundColor = (voiceMode ? NSColor.systemGreen.withAlphaComponent(0.7)
                                                     : NSColor.white.withAlphaComponent(0.16)).cgColor
    if voiceMode {
      if !playing { togglePlay() }            // 确保在播放态
      voiceLine = linesView.currentLineIndex
      showStatus("🎤 开启中…请允许麦克风/语音")
      voiceFollower.onTranscript = { [weak self] t in self?.alignAndScroll(t) }
      voiceFollower.onStatus = { [weak self] m in self?.showStatus(m) }
      voiceFollower.start()
    } else {
      voiceFollower.stop()
      showStatus("")
    }
  }

  /// 把识别到的话尾, 在当前行附近几行里模糊匹配 → 跟着往前滚。
  private func alignAndScroll(_ transcript: String) {
    guard voiceMode else { return }
    let clean = transcript.filter { !$0.isWhitespace && !$0.isPunctuation }
    showStatus(clean.isEmpty ? "👂 没听到声音…" : "👂 听到：" + String(clean.suffix(12)))  // 实时显示识别到的字(诊断)
    guard clean.count >= 2 else { return }
    let tail = String(clean.suffix(6))
    let n = linesView.lineCount
    guard n > 0 else { return }
    var found = -1
    let start = max(0, voiceLine)
    for i in start..<min(n, start + 6) {
      let lt = linesView.textOfLine(i).filter { !$0.isWhitespace && !$0.isPunctuation }
      if lt.count >= 2, looseContains(lt, tail) { found = i }
    }
    if found >= voiceLine {
      voiceLine = found
      linesView.focusLine(found)
      linesView.updateDepth()
      updateJourney()
    }
  }

  /// hay 是否包含 tail 的任意 >=2 字连续子串(容识别误差)。
  private func looseContains(_ hay: String, _ tail: String) -> Bool {
    let a = Array(tail)
    var len = a.count
    while len >= 2 {
      var i = 0
      while i + len <= a.count {
        if hay.contains(String(a[i..<i + len])) { return true }
        i += 1
      }
      len -= 1
    }
    return false
  }

  private func showStatus(_ s: String) {
    comboLayer.string = NSAttributedString(string: s, attributes: [
      .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
      .foregroundColor: NSColor.systemTeal])
  }
  @objc private func setSpeed(_ s: NSMenuItem) { if let v = s.representedObject as? Double { speed = CGFloat(v) } }
  @objc private func setFontSize(_ s: NSMenuItem) { if let v = s.representedObject as? Double { linesView.fontSize = CGFloat(v) } }
  @objc private func setTextColor(_ s: NSMenuItem) {
    if let c = s.representedObject as? NSColor { linesView.textColor = c; editText.textColor = c }
  }
}
