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
      cycleShape()
    }
    dragStart = nil
  }
}
