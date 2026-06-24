//
//  CameraBubbleWindow.swift
//  Snapzy (靓相 Shotlit)
//
//  Face bubble 露脸画中画浮窗 — shaped (circle/heart/star/...), draggable,
//  single-click to cycle shape, shows the beauty-processed camera frames.
//

import AppKit

/// A shaped, draggable webcam bubble showing beauty-processed frames.
/// 可换形状、可拖动、显示美颜后画面的露脸浮窗。
@MainActor
final class CameraBubbleWindow: NSWindow {
  private let capture = CameraCaptureService()
  private(set) var shape: BubbleShape

  private let previewHost = CALayer()
  private let displayLayer = CALayer()
  private let maskLayer = CAShapeLayer()
  private let borderLayer = CAShapeLayer()

  private var dragStart: NSPoint?
  private var didDrag = false

  init(diameter: CGFloat = 180, shape: BubbleShape = .heart) {
    self.shape = shape
    let rect = NSRect(x: 0, y: 0, width: diameter, height: diameter)
    super.init(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)

    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let content = NSView(frame: rect)
    content.wantsLayer = true
    contentView = content

    // 画面层(显示美颜后每帧, 被形状 mask 裁剪) processed-frame layer, clipped to shape
    previewHost.frame = rect
    displayLayer.frame = rect
    displayLayer.contentsGravity = .resizeAspectFill
    displayLayer.backgroundColor = NSColor.black.cgColor
    previewHost.addSublayer(displayLayer)
    previewHost.mask = maskLayer
    content.layer?.addSublayer(previewHost)

    // 形状轮廓白边 shape outline border
    borderLayer.fillColor = NSColor.clear.cgColor
    borderLayer.strokeColor = NSColor.white.cgColor
    borderLayer.lineWidth = 4
    content.layer?.addSublayer(borderLayer)

    applyShape(rect: rect)

    // 每帧更新显示(禁隐式动画) update each frame, no implicit animation
    capture.onFrame = { [weak displayLayer] cgImage in
      guard let displayLayer else { return }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      displayLayer.contents = cgImage
      CATransaction.commit()
    }
    capture.start()
  }

  private func applyShape(rect: CGRect) {
    let path = shape.path(in: rect)
    maskLayer.path = path
    borderLayer.path = path
  }

  /// Cycle to next shape (single click). 单击循环切换到下一个形状。
  func cycleShape() {
    let all = BubbleShape.allCases
    if let idx = all.firstIndex(of: shape) {
      shape = all[(idx + 1) % all.count]
    }
    let rect = contentView?.bounds ?? NSRect(origin: .zero, size: frame.size)
    applyShape(rect: rect)
  }

  /// Adjust beauty strength. 调节美颜强度。
  func setBeauty(smoothing: Float, whitening: Float) {
    capture.beauty.smoothing = smoothing
    capture.beauty.whitening = whitening
  }

  /// Show at the bottom-right corner. 显示在屏幕右下角。
  func show() {
    if let screen = NSScreen.main {
      let visible = screen.visibleFrame
      let d = frame.width
      setFrameOrigin(NSPoint(x: visible.maxX - d - 40, y: visible.minY + 40))
    }
    orderFrontRegardless()
  }

  /// Window id for ScreenCaptureKit "except" list. 供录屏"例外"名单用的窗口 id。
  var overlayWindowID: CGWindowID { CGWindowID(windowNumber) }

  // MARK: - Drag to move + single click to cycle shape 拖动移动 + 单击换形状

  override var canBecomeKey: Bool { true }

  override func mouseDown(with event: NSEvent) {
    dragStart = event.locationInWindow
    didDrag = false
  }

  override func mouseDragged(with event: NSEvent) {
    didDrag = true
    guard dragStart != nil else { return }
    let origin = frame.origin
    setFrameOrigin(NSPoint(x: origin.x + event.deltaX, y: origin.y - event.deltaY))
  }

  override func mouseUp(with event: NSEvent) {
    if !didDrag {
      showOptionsMenu(with: event) // 单击: 弹出选项菜单
    }
    dragStart = nil
  }

  // MARK: - 选项菜单(形状/滤镜/美颜) options popup menu

  private func showOptionsMenu(with event: NSEvent) {
    guard let view = contentView else { return }
    let menu = NSMenu()

    // 形状 Shape
    let shapeSub = NSMenu()
    for s in BubbleShape.allCases {
      let item = NSMenuItem(title: s.displayName, action: #selector(pickShape(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = s
      item.state = (s == shape) ? .on : .off
      shapeSub.addItem(item)
    }
    let shapeItem = NSMenuItem(title: "Shape 形状", action: nil, keyEquivalent: "")
    menu.addItem(shapeItem)
    menu.setSubmenu(shapeSub, for: shapeItem)

    // 滤镜 Filter
    let filterSub = NSMenu()
    for f in BeautyFilterType.allCases {
      let item = NSMenuItem(title: f.displayName, action: #selector(pickFilter(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = f
      item.state = (f == capture.beauty.filter) ? .on : .off
      filterSub.addItem(item)
    }
    let filterItem = NSMenuItem(title: "Filter 滤镜", action: nil, keyEquivalent: "")
    menu.addItem(filterItem)
    menu.setSubmenu(filterSub, for: filterItem)

    // 美颜滑块 Beauty (0-100, 拖动实时调节 GpuPixel)
    let beautySub = NSMenu()
    let sliders: [(String, Int, Float)] = [
      ("Smooth 磨皮", 0, capture.gpSmoothing),
      ("Whiten 美白", 1, capture.gpWhitening),
      ("Slim 瘦脸", 2, capture.gpFaceSlim),
      ("Eye 大眼", 3, capture.gpEyeZoom),
    ]
    for (title, tag, val) in sliders {
      let item = NSMenuItem()
      item.view = makeBeautySlider(title: title, tag: tag, value: val)
      beautySub.addItem(item)
    }
    let beautyItem = NSMenuItem(title: "Beauty 美颜(拖滑块)", action: nil, keyEquivalent: "")
    menu.addItem(beautyItem)
    menu.setSubmenu(beautySub, for: beautyItem)

    NSMenu.popUpContextMenu(menu, with: event, for: view)
  }

  @objc private func pickShape(_ sender: NSMenuItem) {
    guard let s = sender.representedObject as? BubbleShape else { return }
    shape = s
    applyShape(rect: contentView?.bounds ?? NSRect(origin: .zero, size: frame.size))
  }

  @objc private func pickFilter(_ sender: NSMenuItem) {
    guard let f = sender.representedObject as? BeautyFilterType else { return }
    capture.beauty.filter = f
  }

  @objc private func pickBeauty(_ sender: NSMenuItem) {
    guard let v = sender.representedObject as? [Float], v.count == 2 else { return }
    capture.beauty.smoothing = v[0]
    capture.beauty.whitening = v[1]
  }

  /// 建一个带标签的美颜滑块(菜单项视图)。tag 0磨皮/1美白/2瘦脸/3大眼。
  private func makeBeautySlider(title: String, tag: Int, value: Float) -> NSView {
    let v = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 40))
    let label = NSTextField(labelWithString: title)
    label.frame = NSRect(x: 14, y: 21, width: 180, height: 15)
    label.font = .systemFont(ofSize: 11)
    label.textColor = .labelColor
    let slider = NSSlider(frame: NSRect(x: 14, y: 4, width: 192, height: 16))
    slider.minValue = 0
    slider.maxValue = 100
    slider.doubleValue = Double(value * 100)
    slider.tag = tag
    slider.target = self
    slider.action = #selector(beautySliderChanged(_:))
    slider.isContinuous = true
    v.addSubview(label)
    v.addSubview(slider)
    return v
  }

  @objc private func beautySliderChanged(_ sender: NSSlider) {
    let v = Float(sender.doubleValue / 100.0)
    switch sender.tag {
    case 0: capture.gpSmoothing = v
    case 1: capture.gpWhitening = v
    case 2: capture.gpFaceSlim = v
    case 3: capture.gpEyeZoom = v
    default: break
    }
  }
}
