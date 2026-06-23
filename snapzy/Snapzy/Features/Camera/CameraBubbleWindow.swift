//
//  CameraBubbleWindow.swift
//  Snapzy (靓相 Shotlit)
//
//  Face bubble 露脸画中画浮窗 — round, draggable, floats on top.
//  Mirrors the overlay-window pattern (transparent borderless NSWindow)
//  so it can later be captured into recordings like the other overlays.
//

import AppKit

/// A round, draggable webcam bubble window. 圆形可拖动的露脸浮窗。
@MainActor
final class CameraBubbleWindow: NSWindow {
  private let capture = CameraCaptureService()

  init(diameter: CGFloat = 180) {
    let rect = NSRect(x: 0, y: 0, width: diameter, height: diameter)
    super.init(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)

    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isMovableByWindowBackground = true   // drag to move 拖动移动

    let container = NSView(frame: rect)
    container.wantsLayer = true
    if let layer = container.layer {
      layer.cornerRadius = diameter / 2
      layer.masksToBounds = true
      layer.borderWidth = 3
      layer.borderColor = NSColor.white.cgColor
      layer.backgroundColor = NSColor.black.cgColor
    }
    contentView = container

    let preview = capture.previewLayer
    preview.frame = rect
    preview.cornerRadius = diameter / 2
    preview.masksToBounds = true
    container.layer?.addSublayer(preview)

    capture.start()
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
}
