//
//  BubbleShape.swift
//  Snapzy (靓相 Shotlit)
//
//  Face bubble shapes 露脸 bubble 的形状 — circle/square/heart/star/...
//  NOTE: CALayer geometry is Y-up (origin bottom-left), so custom paths
//  below are authored with fy=0 at the bottom and fy=1 at the top.
//  注意: 图层坐标系 Y 轴朝上, 自定义形状按"底部 fy=0、顶部 fy=1"绘制。
//

import AppKit

/// Shapes for the face bubble. 露脸 bubble 的可选形状。
enum BubbleShape: String, CaseIterable {
  case circle       // 圆形
  case square       // 正方形
  case roundedRect  // 圆角矩形
  case ellipse      // 椭圆
  case heart        // 心形
  case star         // 星形
  case hexagon      // 六边形
  case triangle     // 三角形

  /// Display name (English then Chinese). 显示名(先英文后中文)。
  var displayName: String {
    switch self {
    case .circle: return "Circle 圆形"
    case .square: return "Square 正方形"
    case .roundedRect: return "Rounded 圆角矩形"
    case .ellipse: return "Ellipse 椭圆"
    case .heart: return "Heart 心形"
    case .star: return "Star 星形"
    case .hexagon: return "Hexagon 六边形"
    case .triangle: return "Triangle 三角形"
    }
  }

  /// Path for this shape inside the given rect. 该形状在给定矩形内的路径。
  func path(in rect: CGRect) -> CGPath {
    switch self {
    case .circle, .ellipse:
      return CGPath(ellipseIn: rect, transform: nil)
    case .square:
      return CGPath(rect: rect, transform: nil)
    case .roundedRect:
      let r = min(rect.width, rect.height) * 0.18
      return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    case .heart:
      return Self.heartPath(in: rect)
    case .star:
      return Self.starPath(in: rect, points: 5)
    case .hexagon:
      return Self.polygonPath(in: rect, sides: 6)
    case .triangle:
      return Self.polygonPath(in: rect, sides: 3)
    }
  }

  // MARK: - Custom paths (Y-up)

  /// 标准 ❤️ 心形: 两瓣圆凸在上, 尖在下, 顶部中央凹陷。
  private static func heartPath(in rect: CGRect) -> CGPath {
    let p = CGMutablePath()
    let w = rect.width, h = rect.height
    let x = rect.minX, y = rect.minY
    func P(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { CGPoint(x: x + fx * w, y: y + fy * h) }
    p.move(to: P(0.5, 0.04)) // 底部尖
    // 左侧下行 → 左瓣顶 → 顶部中央凹陷
    p.addCurve(to: P(0.03, 0.66), control1: P(0.30, 0.28), control2: P(0.03, 0.48))
    p.addCurve(to: P(0.5, 0.80), control1: P(0.03, 0.94), control2: P(0.37, 0.95))
    // 顶部中央凹陷 → 右瓣顶 → 右侧回底尖
    p.addCurve(to: P(0.97, 0.66), control1: P(0.63, 0.95), control2: P(0.97, 0.94))
    p.addCurve(to: P(0.5, 0.04), control1: P(0.97, 0.48), control2: P(0.70, 0.28))
    p.closeSubpath()
    return p
  }

  /// N 角星, 尖朝上。
  private static func starPath(in rect: CGRect, points: Int) -> CGPath {
    let p = CGMutablePath()
    let cx = rect.midX, cy = rect.midY
    let rOuter = min(rect.width, rect.height) / 2
    let rInner = rOuter * 0.42
    let step = CGFloat.pi / CGFloat(points)
    var angle = CGFloat.pi / 2 // 顶点朝上 (Y-up)
    for i in 0 ..< (points * 2) {
      let r = (i % 2 == 0) ? rOuter : rInner
      let pt = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
      if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
      angle += step
    }
    p.closeSubpath()
    return p
  }

  /// 正多边形, 一个顶点朝上。
  private static func polygonPath(in rect: CGRect, sides: Int) -> CGPath {
    let p = CGMutablePath()
    let cx = rect.midX, cy = rect.midY
    let r = min(rect.width, rect.height) / 2
    let step = 2 * CGFloat.pi / CGFloat(sides)
    var angle = CGFloat.pi / 2 // 顶点朝上 (Y-up)
    for i in 0 ..< sides {
      let pt = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
      if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
      angle += step
    }
    p.closeSubpath()
    return p
  }
}
