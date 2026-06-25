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
import QuartzCore
import UniformTypeIdentifiers
import Speech
import AVFoundation

private enum TeleprompterScriptSanitizer {
  private static let extraWhitespaceScalars: Set<UInt32> = [
    0x0085,
    0x00A0,
    0x1680,
    0x180E,
    0x200B,
    0x2028,
    0x2029,
    0x202F,
    0x205F,
    0x2060,
    0x3000,
    0xFEFF,
  ]

  nonisolated static func normalize(_ script: String) -> String {
    script.components(separatedBy: .newlines)
      .map(compactLine(_:))
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  nonisolated static func compactLine(_ line: String) -> String {
    String(line.unicodeScalars.filter { !isRemovableWhitespace($0) })
  }

  /// 删所有空白符但保留换行(编辑框增量输入/粘贴用: 一个字挨一个字, 段落换行留着, 标点保留)。
  nonisolated static func compactKeepingNewlines(_ s: String) -> String {
    String(s.unicodeScalars.filter { $0.value == 0x000A || !isRemovableWhitespace($0) })
  }

  nonisolated static func shouldRunEditPasteProbe() -> Bool {
    ProcessInfo.processInfo.environment["SNAPZY_TELEPROMPTER_PROBE_EDIT_PASTE"] == "1"
  }

  nonisolated static func isDebugLoggingEnabled() -> Bool {
    ProcessInfo.processInfo.environment["SNAPZY_TELEPROMPTER_LOG_RENDER"] == "1"
  }

  nonisolated static func shouldAutopasteClipboardOnLaunch() -> Bool {
    ProcessInfo.processInfo.environment["SNAPZY_TELEPROMPTER_AUTOPASTE_CLIPBOARD"] == "1"
  }

  nonisolated static func logValue(_ label: String, value: String) {
    guard isDebugLoggingEnabled() else { return }
    NSLog("[Teleprompter] %@: \"%@\" | scalars: %@", label, escaped(value), scalarList(value))
  }

  nonisolated static func logRenderedLines(_ lines: [String]) {
    guard isDebugLoggingEnabled() else { return }
    NSLog("[Teleprompter] rendered line count: %ld", lines.count)
    for (index, line) in lines.enumerated() {
      NSLog("[Teleprompter] rendered[%ld]: \"%@\" | scalars: %@",
            index, escaped(line), scalarList(line))
    }
  }

  private nonisolated static func isRemovableWhitespace(_ scalar: UnicodeScalar) -> Bool {
    let value = scalar.value
    if CharacterSet.whitespacesAndNewlines.contains(scalar) { return true }
    if (0x2000...0x200A).contains(value) { return true }
    return extraWhitespaceScalars.contains(value)
  }

  private nonisolated static func escaped(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "\\r")
      .replacingOccurrences(of: "\t", with: "\\t")
  }

  private nonisolated static func scalarList(_ value: String) -> String {
    value.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
  }
}

enum TeleprompterDisplayTextComposer {
  static func displayLines(
    from script: String,
    wrapWidth: CGFloat,
    font: NSFont,
    paragraphStyle: NSParagraphStyle
  ) -> [String] {
    guard wrapWidth > 1 else { return [] }
    return script.components(separatedBy: "\n").flatMap { rawLine in
      let compact = TeleprompterScriptSanitizer.compactLine(rawLine)
      guard !compact.isEmpty else { return [String]() }
      return wrapLine(compact, wrapWidth: wrapWidth, font: font, paragraphStyle: paragraphStyle)
    }
  }

  static func attributedLine(
    for line: String,
    font: NSFont,
    paragraphStyle: NSParagraphStyle,
    color: NSColor
  ) -> NSAttributedString {
    let baseAttrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .paragraphStyle: paragraphStyle,
      .foregroundColor: color,
    ]
    let chars = Array(line)
    let attributed = NSMutableAttributedString(string: line, attributes: baseAttrs)
    var utf16Location = 0

    for index in chars.indices {
      let char = chars[index]
      let next = chars.index(after: index) < chars.endIndex ? chars[chars.index(after: index)] : nil
      let range = NSRange(location: utf16Location, length: String(char).utf16.count)
      let kern = kern(after: char, next: next, fontSize: font.pointSize)
      if kern != 0 { attributed.addAttribute(.kern, value: kern, range: range) }
      utf16Location += range.length
    }

    return attributed
  }

  private static func wrapLine(
    _ line: String,
    wrapWidth: CGFloat,
    font: NSFont,
    paragraphStyle: NSParagraphStyle
  ) -> [String] {
    let characters = Array(line)
    guard !characters.isEmpty else { return [] }

    var lines: [String] = []
    var current = ""

    for character in characters {
      let next = current + String(character)
      if current.isEmpty || measuredWidth(of: next, font: font, paragraphStyle: paragraphStyle) <= wrapWidth {
        current = next
      } else {
        lines.append(current)
        current = String(character)
      }
    }

    if !current.isEmpty { lines.append(current) }
    return lines
  }

  private static func measuredWidth(
    of line: String,
    font: NSFont,
    paragraphStyle: NSParagraphStyle
  ) -> CGFloat {
    let attributed = attributedLine(for: line, font: font, paragraphStyle: paragraphStyle, color: .white)
    let rect = attributed.boundingRect(
      with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    )
    return ceil(rect.width)
  }

  private static func kern(after char: Character, next: Character?, fontSize: CGFloat) -> CGFloat {
    guard let next else { return 0 }

    let charIsCJK = isCJK(char)
    let nextIsCJK = isCJK(next)
    let charIsASCII = isASCIIish(char)
    let nextIsASCII = isASCIIish(next)

    if charIsCJK && nextIsCJK {
      return -max(1.8, fontSize * 0.12)
    }
    if (charIsCJK && nextIsASCII) || (charIsASCII && nextIsCJK) {
      return -max(2.4, fontSize * 0.18)
    }
    if charIsASCII && nextIsASCII {
      return -max(0.8, fontSize * 0.06)
    }
    if isTightPunctuation(char) || isTightPunctuation(next) {
      return -max(1.6, fontSize * 0.10)
    }
    return 0
  }

  private static func isASCIIish(_ char: Character) -> Bool {
    char.unicodeScalars.allSatisfy { $0.value < 0x80 }
  }

  private static func isCJK(_ char: Character) -> Bool {
    char.unicodeScalars.contains { scalar in
      switch scalar.value {
      case 0x2E80...0x2EFF, 0x2F00...0x2FDF, 0x3040...0x30FF,
           0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
           0xFF00...0xFFEF:
        return true
      default:
        return false
      }
    }
  }

  private static func isTightPunctuation(_ char: Character) -> Bool {
    "，。！？；：、“”‘’（）《》【】,.!?;:()[]{}<>\"'".contains(char)
  }
}

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
  var focusGlow: Bool = true        // 焦点行呼吸光晕(高级光束)
  /// 一行念完(逐字点亮走完)时回调 → 连击/火花。仅播放时上层处理。
  var onLineComplete: (() -> Void)?

  private let focusFrac: CGFloat = 0.40
  private let minScale: CGFloat = 0.82      // 上下行别缩太小, 保持可读
  private let minOpacity: CGFloat = 0.52    // 上下行别压太暗(读过的不秒消/没读的提前可见)
  private let lineGap: CGFloat = 5
  private let hPad: CGFloat = 24

  private var lineLayers: [CATextLayer] = []
  private var lineCenters: [CGFloat] = []
  private var lineHeights: [CGFloat] = []
  private var lineTexts: [String] = []
  private var lineCharCounts: [Int] = []
  private var lineHi: [Int] = []
  private var lineBuckets: [Int] = []
  private var lastLoggedRenderedSignature = ""
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
    var cursor: CGFloat = 0

    // 根上修：我们自己逐字测量和分行，不再让 CATextLayer 自动包行。
    for raw in TeleprompterDisplayTextComposer.displayLines(
      from: script,
      wrapWidth: wrapWidth,
      font: curFont,
      paragraphStyle: curPara
    ) {
      let attributed = TeleprompterDisplayTextComposer.attributedLine(
        for: raw,
        font: curFont,
        paragraphStyle: curPara,
        color: textColor
      )
      let bounding = attributed.boundingRect(
        with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
      )
      let h = ceil(bounding.height) + 4
      let w = min(wrapWidth, max(8, ceil(bounding.width) + 6))

      let tl = CATextLayer()
      tl.string = attributed
      tl.isWrapped = false
      tl.alignmentMode = .center
      tl.truncationMode = .none
      tl.contentsScale = scale2x
      tl.anchorPoint = CGPoint(x: 0.5, y: 0.5)
      tl.bounds = CGRect(x: 0, y: 0, width: w, height: h)
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
    maybeLogRenderedLines()
    updateDepth()
  }

  private func maybeLogRenderedLines() {
    let signature = lineTexts.joined(separator: "\u{241E}")
    guard signature != lastLoggedRenderedSignature else { return }
    lastLoggedRenderedSignature = signature
    TeleprompterScriptSanitizer.logRenderedLines(lineTexts)
  }

  private func applyKaraoke(_ i: Int, _ n: Int) {
    let s = lineTexts[i]
    let full = NSMutableAttributedString(attributedString: TeleprompterDisplayTextComposer.attributedLine(
      for: s,
      font: curFont,
      paragraphStyle: curPara,
      color: textColor
    ))
    let len = (s as NSString).length
    if n > 0 { full.addAttribute(.foregroundColor, value: highlightColor, range: NSRange(location: 0, length: min(n, len))) }
    lineLayers[i].string = full
  }

  private func applyPlain(_ i: Int) {
    let line = lineTexts[i]
    lineLayers[i].string = TeleprompterDisplayTextComposer.attributedLine(
      for: line,
      font: curFont,
      paragraphStyle: curPara,
      color: textColor
    )
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
    let falloff = max(160, H * 1.0)     // 衰减更缓 = 上下行渐变柔和, 文字一直在视线里

    var focusIdx = 0; var focusBest = CGFloat.greatestFiniteMagnitude
    CATransaction.begin(); CATransaction.setDisableActions(true)
    for (i, tl) in lineLayers.enumerated() {
      let centerY = focusY + (lineCenters[i] - first) - scrollOffset
      let d = abs(centerY - focusY)
      if d < focusBest { focusBest = d; focusIdx = i }
      var t = min(1, d / falloff)
      t = t * t * (3 - 2 * t)

      tl.position = CGPoint(x: centerX, y: centerY)
      tl.transform = CATransform3DMakeScale(1 - (1 - minScale) * t, 1 - (1 - minScale) * t, 1)
      tl.opacity = Float(1 - (1 - minOpacity) * t)
      tl.shadowOpacity = 0   // 先清, 焦点行下面单独加呼吸光晕

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
    // 高级光束: 焦点行呼吸发光(青色光晕, 随时间柔和明灭, 不抢字)
    if focusGlow, focusIdx < lineLayers.count {
      let layer = lineLayers[focusIdx]
      let pulse = 0.5 + 0.5 * sin(CACurrentMediaTime() * 2.4)
      layer.shadowColor = NSColor(srgbRed: 0.72, green: 0.45, blue: 1, alpha: 1).cgColor   // 紫色呼吸光晕
      layer.shadowRadius = 14 + 14 * pulse      // 更强光晕(她说看不出区别)
      layer.shadowOpacity = Float(0.9 + 0.1 * pulse)
      layer.shadowOffset = .zero
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

// MARK: - 右下角拖拽手柄(自由改提词器大小)

@MainActor
private final class ResizeHandleView: NSView {
  override init(frame frameRect: NSRect) { super.init(frame: frameRect); wantsLayer = true }
  required init?(coder: NSCoder) { fatalError() }
  override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
  override func mouseDown(with e: NSEvent) { (window as? TeleprompterWindow)?.beginHandleResize() }
  override func mouseDragged(with e: NSEvent) { (window as? TeleprompterWindow)?.updateHandleResize() }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.white.withAlphaComponent(0.55).setStroke()
    let p = NSBezierPath(); p.lineWidth = 1.5
    let w = bounds.width, h = bounds.height
    for off in [CGFloat(0), 5, 10] {   // 三道斜纹 = 抓手感
      p.move(to: CGPoint(x: w - 2 - off, y: 2)); p.line(to: CGPoint(x: w - 2, y: 2 + off))
    }
    p.stroke()
  }
}

/// 控制条按钮: 悬浮窗非活动时也能一点就响应(不被系统吃掉第一次点击)。
@MainActor
private final class BarButton: NSButton {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 编辑框: "无格式粘贴"总闸 — 不管打字/粘贴(任何格式)/拖拽/输入法, 文字一进来就删空格、
/// 保留换行和标点。一道闸堵死所有入口, 不再逐条 override 各种粘贴。
@MainActor
private final class PlainTextView: NSTextView, NSTextViewDelegate {

  /// 总闸: 所有文本变更(键入/粘贴/拖拽/输入法确认)都经过这里。含空格就拦下, 插清洗版。
  func textView(_ view: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
    guard let text, !text.isEmpty else { return true }
    let cleaned = TeleprompterScriptSanitizer.compactKeepingNewlines(text)
    guard cleaned != text else { return true }   // 本就没空白, 放行
    TeleprompterScriptSanitizer.logValue("editText shouldChange raw", value: text)
    TeleprompterScriptSanitizer.logValue("editText shouldChange cleaned", value: cleaned)
    view.insertText(cleaned, replacementRange: range)   // 插清洗版(光标自动正确)
    return false                                         // 拦掉原始带空格版
  }

  // ⌘V 直接路径(双保险, 不依赖 delegate; 富文本/纯文本两种 selector 都收口到这)。
  override func paste(_ sender: Any?) {
    guard let s = NSPasteboard.general.string(forType: .string) else { super.paste(sender); return }
    let n = TeleprompterScriptSanitizer.compactKeepingNewlines(s)
    TeleprompterScriptSanitizer.logValue("PlainTextView.paste input", value: s)
    TeleprompterScriptSanitizer.logValue("PlainTextView.paste normalized", value: n)
    insertText(n, replacementRange: selectedRange())
  }
  override func pasteAsPlainText(_ sender: Any?) { paste(sender) }
  override func pasteAsRichText(_ sender: Any?) { paste(sender) }
}

// MARK: - 提词器窗口

@MainActor
final class TeleprompterWindow: NSWindow {
  private let resizeHandle = ResizeHandleView()    // 右下角拖拽改大小
  private var resizeStartFrame = NSRect.zero
  private var resizeStartMouse = NSPoint.zero
  private let effectView = NSVisualEffectView()
  private let borderView = FXView()                 // 彩色流光描边(最上层, 鼠标穿透)
  private let borderGradient = CAGradientLayer()
  private let borderMask = CAShapeLayer()
  private let skyView = NSView()                    // 天色(随进度 白天→黄昏→星空)
  private let skyGradient = CAGradientLayer()
  private let linesView = LinesView()
  private let fxView = FXView()                     // 火花/烟花/爱心
  private let editScroll = NSScrollView()
  private let editText = PlainTextView()
  private let controlBar = NSView()

  // 底部"光之路"+精灵+连击
  private let journeyBar = NSView()
  private let trackLayer = CALayer()
  private let trackFill = CAGradientLayer()         // 发光进度填充(青→紫)
  private let headDot = CALayer()                   // 发光彗星头(进度亮点 + 脉冲)
  private let speedLabel = CATextLayer()            // 常驻可见速度数值(0.1/0.2…)
  private let comboLayer = CATextLayer()            // 仅语音跟随状态文字用

  private var playPauseButton: NSButton!
  private var editButton: NSButton!

  // 灵动岛: 收起/展开 胶囊
  private var collapsed = false
  private var expandedFrame = NSRect.zero
  private let pillView = NSView()
  private let pillBar = NSView()            // 收起态右上角控制条
  private var pillPlay: NSButton!
  private var pillExpand: NSButton!
  private let pillTrack = CALayer()
  private let pillFill = CAGradientLayer()
  private var animTimer: Timer?
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
  private var fontScale: CGFloat = 1.0   // 字号手动倍数(叠加在随框自适应上)
  private var playing = true
  private var editing = false
  private var didRunLaunchClipboardProbe = false

  // 游戏状态
  private var combo = 0
  private var frameTick = 0
  private var finished = false
  private let spritePool = ["👾", "🍄", "⭐️", "🐉", "🤖", "🕹️", "🎮", "👻"]   // 全球公认经典游戏形象
  private func currentCat() -> String { spritePool[combo % spritePool.count] }   // 念完一句随机换形象

  private let placeholder = """
  把逐字稿粘贴进来：点上面「编辑」，或直接 ⌘V
  只有你看得到，录屏和直播的观众都看不到
  当前这行最大最亮，跟着滚动念就行
  """

  /// 字色可选项 — Tailwind(开源设计系统)柔和配色, 深色背景念稿清晰且耐看, 不刺眼。
  /// 控制条「字色」钮和右键菜单共用一份, 每项带色块预览。
  static let textColorChoices: [(String, NSColor)] = [
    ("白",     NSColor.white),
    ("琥珀",   NSColor(srgbRed: 0.988, green: 0.827, blue: 0.302, alpha: 1)),
    ("橙",     NSColor(srgbRed: 0.992, green: 0.729, blue: 0.455, alpha: 1)),
    ("珊瑚",   NSColor(srgbRed: 0.988, green: 0.647, blue: 0.647, alpha: 1)),
    ("粉",     NSColor(srgbRed: 0.976, green: 0.659, blue: 0.831, alpha: 1)),
    ("薰衣草", NSColor(srgbRed: 0.769, green: 0.710, blue: 0.992, alpha: 1)),
    ("靛蓝",   NSColor(srgbRed: 0.647, green: 0.706, blue: 0.988, alpha: 1)),
    ("天蓝",   NSColor(srgbRed: 0.576, green: 0.773, blue: 0.992, alpha: 1)),
    ("青",     NSColor(srgbRed: 0.404, green: 0.910, blue: 0.976, alpha: 1)),
    ("薄荷",   NSColor(srgbRed: 0.431, green: 0.906, blue: 0.718, alpha: 1)),
    ("柠绿",   NSColor(srgbRed: 0.745, green: 0.949, blue: 0.392, alpha: 1)),
    ("米白",   NSColor(srgbRed: 0.996, green: 0.976, blue: 0.765, alpha: 1)),
  ]

  /// 给菜单项画一个圆角色块预览图。
  static func colorSwatch(_ c: NSColor, size: CGFloat = 16) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    c.setFill()
    NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: size - 2, height: size - 2), xRadius: 4, yRadius: 4).fill()
    NSColor.white.withAlphaComponent(0.35).setStroke()
    let p = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: size - 2, height: size - 2), xRadius: 4, yRadius: 4)
    p.lineWidth = 0.5; p.stroke()
    img.unlockFocus()
    return img
  }

  var hiddenFromCapture: Bool = false {
    didSet { sharingType = hiddenFromCapture ? .none : .readOnly }
  }

  init(width: CGFloat = 680, height: CGFloat = 320) {
    super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
               styleMask: [.borderless], backing: .buffered, defer: false)
    sharingType = .readOnly
    appearance = NSAppearance(named: .darkAqua)   // 深色外观: 按钮 .title 白字且能实时更新(⏸↔▶)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isMovableByWindowBackground = true

    contentView?.wantsLayer = true
    contentView?.layer?.cornerRadius = 26          // 灵动岛: 大圆角药丸
    contentView?.layer?.masksToBounds = true       // 彩色流光描边由 borderView 叠在最上层

    // 毛玻璃(最底) — 半透明, 背后内容隐约透出, 不挡死视野
    effectView.material = .underWindowBackground
    effectView.blendingMode = .behindWindow
    effectView.state = .active
    effectView.wantsLayer = true
    effectView.alphaValue = 0.55                    // 半透明: 录屏其他内容能透出来
    contentView?.addSubview(effectView)

    // 半透明深色叠层(灵动岛黑玻璃感, 但够透能看到背后)
    let darkLayer = NSView(); darkLayer.wantsLayer = true
    darkLayer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.30).cgColor
    darkLayer.autoresizingMask = [.width, .height]
    darkLayer.frame = contentView?.bounds ?? .zero
    contentView?.addSubview(darkLayer)

    // 天色(玻璃之上、文字之下)
    skyView.wantsLayer = true
    skyGradient.startPoint = CGPoint(x: 0.5, y: 0)
    skyGradient.endPoint = CGPoint(x: 0.5, y: 1)
    // 紫色主调: 一层淡紫氛围(顶部偏紫, 半透明不挡字)
    skyGradient.colors = [NSColor(srgbRed: 0.32, green: 0.16, blue: 0.52, alpha: 0.22).cgColor,
                          NSColor(srgbRed: 0.10, green: 0.06, blue: 0.20, alpha: 0.10).cgColor]
    skyView.layer?.addSublayer(skyGradient)
    contentView?.addSubview(skyView)

    // 3D 文字 — 只焦点行亮, 其余暗(关掉逐字黄高亮, 焦点行稳定清楚不晃)
    linesView.enableKaraoke = false
    linesView.enableBlur = false        // 不虚化, 上下行保持清楚可读(念稿时一直看得见)
    linesView.script = normalize(placeholder)   // 占位去空格(与编辑框一致)
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
    editText.allowsUndo = true
    editText.delegate = editText        // 总闸: 任何文本变更即时去空格(无格式粘贴)
    editText.drawsBackground = false
    editText.textColor = .white
    editText.insertionPointColor = .white
    editText.font = NSFont.systemFont(ofSize: 18, weight: .regular)
    editScroll.documentView = editText
    contentView?.addSubview(editScroll)

    setupControlBar()
    setupJourney()
    setupRescue()
    contentView?.addSubview(resizeHandle)   // 右下角拖拽手柄
    setupPill()                              // 灵动岛收起态胶囊(默认隐藏)
    setupColoredBorder()                     // 彩色流光描边(最上层叠加, 不挡点击)
    layoutContents()
    startScrolling()
  }

  // MARK: - 自由拖拽改大小

  // 框内控件: 速度 / 字体(不再藏右键)
  @objc private func speedDown() { speed = max(0.1, ((speed * 10).rounded() - 1) / 10); updateSpeedLabel() }
  @objc private func speedUp() { speed = min(2.0, ((speed * 10).rounded() + 1) / 10); updateSpeedLabel() }
  @objc private func fontDown() { fontScale = max(0.5, fontScale - 0.12); layoutContents() }
  @objc private func fontUp() { fontScale = min(2.2, fontScale + 0.12); layoutContents() }
  @objc private func pickFont() {
    let menu = NSMenu()
    let cur = linesView.fontFamily
    let sysItem = NSMenuItem(title: "系统默认", action: #selector(setFontFamily(_:)), keyEquivalent: "")
    sysItem.target = self; sysItem.representedObject = ""; sysItem.state = (cur == nil) ? .on : .off
    menu.addItem(sysItem); menu.addItem(.separator())
    for fam in NSFontManager.shared.availableFontFamilies {
      let i = NSMenuItem(title: fam, action: #selector(setFontFamily(_:)), keyEquivalent: "")
      i.target = self; i.representedObject = fam; i.state = (cur == fam) ? .on : .off
      menu.addItem(i)
    }
    if let v = contentView { menu.popUp(positioning: nil, at: NSPoint(x: v.bounds.midX, y: v.bounds.midY), in: v) }
  }
  @objc private func setFontFamily(_ s: NSMenuItem) {
    let fam = s.representedObject as? String
    linesView.fontFamily = (fam?.isEmpty ?? true) ? nil : fam
  }
  @objc private func pickColor() {
    let menu = NSMenu()
    let colors = Self.textColorChoices
    let cur = linesView.textColor
    for (t, c) in colors {
      let i = NSMenuItem(title: t, action: #selector(setTextColor(_:)), keyEquivalent: "")
      i.target = self; i.representedObject = c
      i.state = (c == cur) ? .on : .off
      i.image = Self.colorSwatch(c)
      menu.addItem(i)
    }
    if let v = contentView { menu.popUp(positioning: nil, at: NSPoint(x: v.bounds.midX, y: v.bounds.midY), in: v) }
  }

  func beginHandleResize() { resizeStartFrame = frame; resizeStartMouse = NSEvent.mouseLocation }
  func updateHandleResize() {
    let m = NSEvent.mouseLocation
    let w = max(360, resizeStartFrame.width + (m.x - resizeStartMouse.x))
    let h = max(180, resizeStartFrame.height - (m.y - resizeStartMouse.y))   // 顶部不动, 向下长
    setFrame(NSRect(x: resizeStartFrame.minX, y: resizeStartFrame.maxY - h, width: w, height: h), display: true)
    layoutContents()
    linesView.needsLayout = true
  }

  // MARK: - 控制条

  /// 强制白字, 保证按钮文字一定可见(治反复"控制条看不见")。
  private static func barTitle(_ s: String) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [
      .foregroundColor: NSColor.white,
      .font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
  }

  private func setupControlBar() {
    func mkBtn(_ title: String, _ sel: Selector) -> NSButton {
      let b = BarButton(title: title, target: self, action: sel)
      b.isBordered = false
      b.wantsLayer = true
      b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
      b.layer?.cornerRadius = 8       // 小药丸
      b.attributedTitle = Self.barTitle(title)   // 显式白字, 切换时也更新 attributedTitle
      return b
    }
    // 控制条整体: 深色药丸容器(灵动岛模块感), 固定右上角
    controlBar.wantsLayer = true
    controlBar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.50).cgColor
    controlBar.layer?.cornerRadius = 14
    controlBar.layer?.borderWidth = 0.5
    controlBar.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    playPauseButton = mkBtn("⏸", #selector(togglePlay))
    editButton = mkBtn("编辑", #selector(toggleEdit))
    voiceButton = mkBtn("🎤", #selector(toggleVoice))
    // 全部控制堆右上: 回退·暂停·编辑·框小中大·字号·字体·字色·清·关闭
    let stack = NSStackView(views: [
      mkBtn("⏪", #selector(stepBack)), playPauseButton, editButton,
      mkBtn("慢", #selector(speedDown)), mkBtn("快", #selector(speedUp)),
      mkBtn("小", #selector(sizeSmall)), mkBtn("中", #selector(sizeMedium)), mkBtn("大", #selector(sizeLarge)),
      mkBtn("A-", #selector(fontDown)), mkBtn("A+", #selector(fontUp)),
      mkBtn("字体", #selector(pickFont)), mkBtn("字色", #selector(pickColor)),
      mkBtn("清", #selector(clearScript)), mkBtn("收起", #selector(toggleCollapse)),
      mkBtn("✕", #selector(closePrompter)),
    ])
    stack.orientation = .horizontal; stack.spacing = 3; stack.distribution = .fillEqually
    // 换方法: 用 Auto Layout 钉死填满容器, 不再用 frame(避免 bounds=0 时算出负尺寸→按钮看不见)
    stack.translatesAutoresizingMaskIntoConstraints = false
    controlBar.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: controlBar.leadingAnchor, constant: 5),
      stack.trailingAnchor.constraint(equalTo: controlBar.trailingAnchor, constant: -5),
      stack.topAnchor.constraint(equalTo: controlBar.topAnchor, constant: 3),
      stack.bottomAnchor.constraint(equalTo: controlBar.bottomAnchor, constant: -3),
    ])
    contentView?.addSubview(controlBar)
  }

  // MARK: - 底部光之路 + 精灵 + 连击

  private func setupJourney() {
    journeyBar.wantsLayer = true
    trackLayer.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
    trackLayer.cornerRadius = 2
    // 干净的发光进度填充(青→紫渐变 + 柔光), 替代小人赛道
    trackFill.colors = [NSColor(srgbRed: 0.51, green: 0.55, blue: 0.97, alpha: 1).cgColor,
                        NSColor(srgbRed: 0.85, green: 0.27, blue: 0.94, alpha: 1).cgColor]   // 靛→紫红
    trackFill.startPoint = CGPoint(x: 0, y: 0.5); trackFill.endPoint = CGPoint(x: 1, y: 0.5)
    trackFill.cornerRadius = 2
    trackFill.shadowColor = NSColor(srgbRed: 0.66, green: 0.33, blue: 0.97, alpha: 1).cgColor
    trackFill.shadowRadius = 5; trackFill.shadowOpacity = 0.85; trackFill.shadowOffset = .zero
    // 发光彗星头: 进度前端一颗亮点 + 青色柔光, 随时间脉冲(Vibe Island 那种醒目感)
    headDot.backgroundColor = NSColor.white.cgColor
    headDot.cornerRadius = 7
    headDot.bounds = CGRect(x: 0, y: 0, width: 14, height: 14)
    headDot.borderWidth = 2
    headDot.borderColor = NSColor(srgbRed: 0.77, green: 0.71, blue: 0.99, alpha: 0.9).cgColor
    headDot.shadowColor = NSColor(srgbRed: 0.66, green: 0.33, blue: 0.97, alpha: 1).cgColor
    headDot.shadowRadius = 12; headDot.shadowOpacity = 1.0; headDot.shadowOffset = .zero
    let s = screenScale
    comboLayer.fontSize = 12; comboLayer.alignmentMode = .left; comboLayer.contentsScale = s
    comboLayer.anchorPoint = CGPoint(x: 0, y: 0.5); comboLayer.bounds = CGRect(x: 0, y: 0, width: 240, height: 18)
    comboLayer.string = ""
    speedLabel.contentsScale = s; speedLabel.alignmentMode = .left
    speedLabel.anchorPoint = CGPoint(x: 0, y: 0.5); speedLabel.bounds = CGRect(x: 0, y: 0, width: 140, height: 16)
    speedLabel.zPosition = 60
    contentView?.layer?.addSublayer(speedLabel)
    journeyBar.layer?.addSublayer(trackLayer)
    journeyBar.layer?.addSublayer(trackFill)
    journeyBar.layer?.addSublayer(headDot)
    journeyBar.layer?.addSublayer(comboLayer)
    contentView?.addSubview(journeyBar)
    updateSpeedLabel()
  }

  private func updateSpeedLabel() {
    speedLabel.string = NSAttributedString(string: String(format: "速度 %.1f×", speed), attributes: [
      .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
      .foregroundColor: NSColor(srgbRed: 0.77, green: 0.71, blue: 0.99, alpha: 1)])
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

  /// 6号: 彩色流光描边(青→紫→粉缓慢流动)。borderView 鼠标穿透, 永远在最上层。
  private func setupColoredBorder() {
    borderView.wantsLayer = true
    borderGradient.colors = [
      NSColor(srgbRed: 0.51, green: 0.55, blue: 0.97, alpha: 1).cgColor,   // 靛
      NSColor(srgbRed: 0.66, green: 0.33, blue: 0.97, alpha: 1).cgColor,   // 紫
      NSColor(srgbRed: 0.85, green: 0.27, blue: 0.94, alpha: 1).cgColor,   // 紫红
      NSColor(srgbRed: 0.51, green: 0.55, blue: 0.97, alpha: 1).cgColor]
    borderGradient.locations = [0, 0.4, 0.7, 1]
    borderGradient.startPoint = CGPoint(x: 0, y: 0)
    borderGradient.endPoint = CGPoint(x: 1, y: 1)
    borderMask.fillColor = NSColor.clear.cgColor
    borderMask.strokeColor = NSColor.black.cgColor
    borderMask.lineWidth = 2
    borderGradient.mask = borderMask
    borderView.layer?.addSublayer(borderGradient)
    contentView?.addSubview(borderView)
    let a = CABasicAnimation(keyPath: "locations")
    a.fromValue = [-0.3, 0.1, 0.4, 0.7]; a.toValue = [0.3, 0.7, 1.0, 1.3]
    a.duration = 6; a.repeatCount = .infinity
    borderGradient.add(a, forKey: "flow")
  }

  // MARK: - 灵动岛 收起/展开 胶囊

  /// 通用控制按钮(白字小药丸), 大框/胶囊共用。
  private func makeBarButton(_ title: String, _ sel: Selector) -> NSButton {
    let b = BarButton(title: title, target: self, action: sel)
    b.isBordered = false; b.wantsLayer = true
    b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
    b.layer?.cornerRadius = 8
    b.attributedTitle = Self.barTitle(title)
    return b
  }

  private func setupPill() {
    pillView.wantsLayer = true
    pillView.isHidden = true
    // 收起态: 复用 linesView 显示 2-3 行小字 + 底进度 + 右上角控制条(后退/暂停/速度/展开)
    pillBar.wantsLayer = true
    pillBar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.50).cgColor
    pillBar.layer?.cornerRadius = 13
    pillBar.layer?.borderWidth = 0.5
    pillBar.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    pillPlay = makeBarButton("⏸", #selector(togglePlay))
    pillExpand = makeBarButton("⤢", #selector(toggleCollapse))
    let st = NSStackView(views: [
      makeBarButton("⏪", #selector(stepBack)), pillPlay,
      makeBarButton("慢", #selector(speedDown)), makeBarButton("快", #selector(speedUp)),
      pillExpand,
    ])
    st.orientation = .horizontal; st.spacing = 3; st.distribution = .fillEqually
    st.translatesAutoresizingMaskIntoConstraints = false
    pillBar.addSubview(st)
    NSLayoutConstraint.activate([
      st.leadingAnchor.constraint(equalTo: pillBar.leadingAnchor, constant: 5),
      st.trailingAnchor.constraint(equalTo: pillBar.trailingAnchor, constant: -5),
      st.topAnchor.constraint(equalTo: pillBar.topAnchor, constant: 3),
      st.bottomAnchor.constraint(equalTo: pillBar.bottomAnchor, constant: -3),
    ])
    pillTrack.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
    pillTrack.cornerRadius = 1.5
    pillFill.colors = [NSColor(srgbRed: 0.51, green: 0.55, blue: 0.97, alpha: 1).cgColor,
                       NSColor(srgbRed: 0.85, green: 0.27, blue: 0.94, alpha: 1).cgColor]
    pillFill.startPoint = CGPoint(x: 0, y: 0.5); pillFill.endPoint = CGPoint(x: 1, y: 0.5)
    pillFill.cornerRadius = 1.5
    pillView.layer?.addSublayer(pillTrack)
    pillView.layer?.addSublayer(pillFill)
    pillView.addSubview(pillBar)
    contentView?.addSubview(pillView)
  }

  /// 念稿态(大框)↔ 收起态(顶部小胶囊)。
  @objc private func toggleCollapse() {
    collapsed.toggle()
    if collapsed {
      expandedFrame = frame
      setCollapsedVisibility(true)
      // 很宽很矮的横条: 2-3 行小字 + 右上角控制条, 不占地方, 可拖到镜头下面
      let pw = min(max(expandedFrame.width, 520), 700), ph: CGFloat = 118
      animateFrame(to: NSRect(x: frame.midX - pw / 2, y: frame.maxY - ph, width: pw, height: ph))
    } else {
      setCollapsedVisibility(false)
      animateFrame(to: expandedFrame)
    }
  }

  /// 收起态: 复用 linesView 显示2-3行小字, 只隐藏大控制条等。边框始终在。
  private func setCollapsedVisibility(_ c: Bool) {
    pillView.isHidden = !c
    linesView.isHidden = false        // 收起态仍显示文字(小字2-3行)
    controlBar.isHidden = c
    journeyBar.isHidden = c
    fxView.isHidden = c
    resizeHandle.isHidden = c
    if c { editScroll.isHidden = true; rescuePanel.isHidden = true }
  }

  /// 逐帧平滑动画(每步 setFrame + 重排, 收展时内容跟着丝滑变)。
  private func animateFrame(to target: NSRect) {
    animTimer?.invalidate()
    let start = frame, steps = 14
    var i = 0
    animTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
      Task { @MainActor in
        guard let self else { t.invalidate(); return }
        i += 1
        let p = min(1, CGFloat(i) / CGFloat(steps))
        let e = p * p * (3 - 2 * p)
        let f = NSRect(x: start.minX + (target.minX - start.minX) * e,
                       y: start.minY + (target.minY - start.minY) * e,
                       width: start.width + (target.width - start.width) * e,
                       height: start.height + (target.height - start.height) * e)
        self.setFrame(f, display: true)
        self.layoutContents()
        if p >= 1 { t.invalidate(); self.animTimer = nil }
      }
    }
  }

  private var screenScale: CGFloat { screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

  private func layoutContents() {
    guard let cv = contentView else { return }
    let w = cv.bounds.width, h = cv.bounds.height
    let barH: CGFloat = 30, barW: CGFloat = min(w - 16, 560), journeyH: CGFloat = 30
    effectView.frame = cv.bounds
    skyView.frame = cv.bounds
    skyGradient.frame = cv.bounds
    fxView.frame = cv.bounds
    borderView.frame = cv.bounds
    borderGradient.frame = cv.bounds
    borderMask.frame = cv.bounds
    borderMask.path = CGPath(roundedRect: cv.bounds.insetBy(dx: 1, dy: 1),
                             cornerWidth: 25, cornerHeight: 25, transform: nil)

    // ===== 收起态: 很宽很矮的横条, 复用 linesView 显示 2-3 行小字 =====
    if collapsed {
      pillView.frame = cv.bounds
      let bh: CGFloat = 26, bw: CGFloat = 200
      pillBar.frame = NSRect(x: w - bw - 8, y: h - bh - 6, width: bw, height: bh)   // 右上角控制条
      pillTrack.frame = CGRect(x: 12, y: 6, width: max(20, w - 24), height: 3)       // 底进度
      speedLabel.position = CGPoint(x: 14, y: 20)                                      // 收起态速度数值
      linesView.frame = NSRect(x: 12, y: 11, width: max(20, w - 24), height: h - bh - 18)
      let cf: CGFloat = 18                                   // 收起态固定小字(不随宽度变大)
      if abs(linesView.fontSize - cf) > 0.5 { linesView.fontSize = cf }
      updateJourney()
      return
    }

    // ===== 念稿态(大框) =====
    controlBar.frame = NSRect(x: w - barW - 8, y: h - barH - 8, width: barW, height: barH)

    journeyBar.frame = NSRect(x: 0, y: 2, width: w, height: journeyH)
    let trackY: CGFloat = 13, trackH: CGFloat = 4
    let left: CGFloat = 18, right = w - 18
    comboLayer.position = CGPoint(x: 18, y: trackY + trackH / 2 + 16)   // 仅语音诊断状态用
    trackLayer.frame = CGRect(x: left, y: trackY, width: max(1, right - left), height: trackH)
    speedLabel.position = CGPoint(x: 20, y: journeyH + 10)              // 常驻速度数值(左下)

    let contentRect = NSRect(x: 0, y: journeyH + 4, width: w, height: h - barH - journeyH - 14)
    linesView.frame = contentRect
    editScroll.frame = contentRect.insetBy(dx: 16, dy: 12)

    let rpW = min(w - 40, 380), rpH: CGFloat = 40
    rescuePanel.frame = NSRect(x: (w - rpW) / 2, y: journeyH + 12, width: rpW, height: rpH)
    rescueStack.frame = rescuePanel.bounds.insetBy(dx: 8, dy: 6)
    resizeHandle.frame = NSRect(x: w - 18, y: 0, width: 18, height: 18)   // 右下角
    let autoFont = max(14, min(80, (w * 0.048 * fontScale).rounded()))   // 字号随框自适应 × 手动倍数
    if abs(linesView.fontSize - autoFont) > 0.5 { linesView.fontSize = autoFont }
    updateJourney()
  }

  func show() {
    if let screen = NSScreen.main {
      let f = screen.visibleFrame
      setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - frame.height - 16))
    }
    orderFrontRegardless()
    maybeAutopasteClipboardForDebugVerification()
    maybeRunEditPasteProbe()
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

    if !finished, linesView.progress >= 0.992 { finished = true }   // 抵达终点(无庆祝特效)
  }

  /// 干净的发光进度填充随念稿进度延伸(无小人/无天色)。
  private func updateJourney() {
    let p = linesView.progress
    let t = trackLayer.frame
    CATransaction.begin(); CATransaction.setDisableActions(true)
    trackFill.frame = CGRect(x: t.minX, y: t.minY, width: max(0.1, t.width * p), height: t.height)
    // 发光彗星头: 随进度走 + 脉冲(只大框显示)
    headDot.isHidden = collapsed
    if !collapsed {
      let pulse = 0.5 + 0.5 * sin(CACurrentMediaTime() * 3)
      headDot.position = CGPoint(x: t.minX + t.width * p, y: t.midY)
      headDot.shadowRadius = 7 + 7 * pulse
      let sc = 1 + 0.35 * pulse
      headDot.transform = CATransform3DMakeScale(sc, sc, 1)
    }
    if collapsed {                              // 收起态: 底部进度
      let pt = pillTrack.frame
      pillFill.frame = CGRect(x: pt.minX, y: pt.minY, width: max(0.1, pt.width * p), height: pt.height)
    }
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
    // 灵动岛黑玻璃 + 极克制冷调点缀: 近黑, 随进度微微泛蓝→青→紫, 高级深邃
    let dayTop = NSColor(srgbRed: 0.04, green: 0.07, blue: 0.13, alpha: 0.55)   // 近黑泛蓝
    let dayBot = NSColor(srgbRed: 0.03, green: 0.09, blue: 0.15, alpha: 0.40)
    let duskTop = NSColor(srgbRed: 0.02, green: 0.09, blue: 0.15, alpha: 0.58)  // 近黑泛青
    let duskBot = NSColor(srgbRed: 0.01, green: 0.12, blue: 0.16, alpha: 0.42)
    let nightTop = NSColor(srgbRed: 0.07, green: 0.04, blue: 0.15, alpha: 0.60) // 近黑泛紫
    let nightBot = NSColor(srgbRed: 0.05, green: 0.06, blue: 0.17, alpha: 0.44)
    let top: NSColor, bot: NSColor
    if p < 0.5 { top = mix(dayTop, duskTop, p / 0.5); bot = mix(dayBot, duskBot, p / 0.5) }
    else { top = mix(duskTop, nightTop, (p - 0.5) / 0.5); bot = mix(duskBot, nightBot, (p - 0.5) / 0.5) }
    return [top.cgColor, bot.cgColor]
  }

  // MARK: - 连击 / 火花

  /// 念过一行不再有连击/火花/精灵反馈(走极简高级)。
  private func onLineComplete() {}

  /// 连击显示已撤掉; 保留空实现以清空状态行。
  private func refreshCombo(pulse: Bool) { comboLayer.string = "" }

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
    playPauseButton.attributedTitle = Self.barTitle(playing ? "⏸" : "▶")
    pillPlay?.attributedTitle = Self.barTitle(playing ? "⏸" : "▶")
    rescuePanel.isHidden = playing || editing || collapsed   // 收起态不弹救场面板
    if !playing { retreatCount = 0; retreatButton.title = "← 退1句" }
  }

  @objc private func toggleEdit() {
    editing.toggle()
    if editing {
      editText.string = normalize(linesView.script)   // 编辑框也去空格(之前漏了这个面)
      editScroll.isHidden = false; linesView.isHidden = true; fxView.isHidden = true
      rescuePanel.isHidden = true
      makeKeyAndOrderFront(nil); makeFirstResponder(editText)
    } else {
      setLiveScript(editText.string)
      editScroll.isHidden = true; linesView.isHidden = false; fxView.isHidden = false
    }
    editButton.attributedTitle = Self.barTitle(editing ? "✓完成" : "编辑")
    editButton.layer?.backgroundColor = (editing ? NSColor(srgbRed: 0.66, green: 0.33, blue: 0.97, alpha: 0.8)
                                                  : NSColor.white.withAlphaComponent(0.15)).cgColor
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
      setLiveScript(s)   // 去格式 + 当场显示
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
    let curColor = linesView.textColor
    for (t, c) in Self.textColorChoices {
      let i = NSMenuItem(title: t, action: #selector(setTextColor(_:)), keyEquivalent: "")
      i.target = self; i.representedObject = c
      i.state = (c == curColor) ? .on : .off
      i.image = Self.colorSwatch(c)
      colorSub.addItem(i)
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
      setLiveScript(text)
    }
  }

  /// 去格式: 删空行 + 删行内所有空格(半角/全角/Tab), 一个字挨一个字, 标点保留。
  private func normalize(_ s: String) -> String {
    TeleprompterScriptSanitizer.normalize(s)
  }

  /// 设新稿到显示态(去格式 + 复位)。粘贴/导入/编辑完成统一走这里。
  private func setLiveScript(_ s: String) {
    let normalized = normalize(s)
    TeleprompterScriptSanitizer.logValue("setLiveScript input", value: s)
    TeleprompterScriptSanitizer.logValue("setLiveScript normalized", value: normalized)
    linesView.script = normalized
    linesView.scrollOffset = 0; combo = 0; finished = false; refreshCombo(pulse: false)
  }

  private func maybeAutopasteClipboardForDebugVerification() {
    guard !didRunLaunchClipboardProbe else { return }
    didRunLaunchClipboardProbe = true
    guard TeleprompterScriptSanitizer.shouldAutopasteClipboardOnLaunch(),
          let clipboard = NSPasteboard.general.string(forType: .string),
          !clipboard.isEmpty else { return }
    TeleprompterScriptSanitizer.logValue("launch clipboard raw", value: clipboard)
    setLiveScript(clipboard)
  }

  /// 自检探针: 真实跑编辑框两条输入路径(打字/输入法/拖拽 走总闸, ⌘V 走 paste), 验证去空格。
  private func maybeRunEditPasteProbe() {
    guard TeleprompterScriptSanitizer.shouldRunEditPasteProbe() else { return }
    if !editing { toggleEdit() }          // 进编辑态
    makeFirstResponder(editText)

    // 路径①: 模拟打字/输入法/拖拽 → 触发 shouldChangeTextIn 总闸
    editText.string = ""
    let typed = "你\u{20}好\u{3000}世\u{09}界，Hello\u{20}\u{20}world！A\u{20}B\u{A0}C\u{2009}D\u{200B}E\u{FEFF}。"
    TeleprompterScriptSanitizer.logValue("probe insertText raw", value: typed)
    editText.insertText(typed, replacementRange: editText.selectedRange())
    TeleprompterScriptSanitizer.logValue("probe editText AFTER insertText", value: editText.string)

    // 路径②: 模拟编辑框 ⌘V 粘贴(剪贴板) → PlainTextView.paste
    editText.string = ""
    editText.paste(nil)
    TeleprompterScriptSanitizer.logValue("probe editText AFTER paste", value: editText.string)

    if editing { toggleEdit() }           // 退出编辑 → 走 setLiveScript → 渲染面
  }

  /// 清空: 回显示态 + 留一行提示, 你直接 ⌘V 当场就显示(不用点完成)。
  @objc private func clearScript() {
    if editing { toggleEdit() }      // 退出编辑态回显示态
    linesView.script = "⌘V 粘贴你的逐字稿"
    linesView.scrollOffset = 0; combo = 0; finished = false; refreshCombo(pulse: false)
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
