//
//  BeautyFilterType.swift
//  Snapzy (靓相 Shotlit)
//
//  Filters 滤镜 — 用 GPUImage 经典专业 lookup(.png) 转 CIColorCube。
//  调色师做的真专业滤镜(amatorka/miss_etikate/soft_elegance), 不是程序瞎调。
//

import AppKit
import CoreGraphics
import CoreImage

enum BeautyFilterType: String, CaseIterable {
  case original, beauty, natural, bright, elegant

  /// Display name (English then Chinese). 显示名(先英后中)。
  var displayName: String {
    switch self {
    case .original: return "Original 原图"
    case .beauty: return "Beauty 美颜"
    case .natural: return "Natural 自然"
    case .bright: return "Bright 明亮"
    case .elegant: return "Elegant 柔和"
    }
  }

  /// 对应的 lookup 资源名。
  private var lookupName: String? {
    switch self {
    case .original: return nil
    case .beauty: return "lookup_beauty"
    case .natural: return "lookup_amatorka"
    case .bright: return "lookup_miss_etikate"
    case .elegant: return "lookup_soft_elegance_1"
    }
  }

  func apply(_ image: CIImage) -> CIImage {
    guard let data = Self.cubeData(for: self) else { return image }
    return image.applyingFilter("CIColorCube", parameters: [
      "inputCubeDimension": 64,
      "inputCubeData": data,
    ]).cropped(to: image.extent)
  }

  // MARK: - lookup.png → CIColorCube data (缓存)

  nonisolated(unsafe) private static var cache: [BeautyFilterType: Data] = [:]

  private static func cubeData(for type: BeautyFilterType) -> Data? {
    if let c = cache[type] { return c }
    guard let name = type.lookupName, let d = loadLookupCube(name) else { return nil }
    cache[type] = d
    return d
  }

  /// 读 512x512 的 GPUImage lookup.png(8x8格), 转成 64³ CIColorCube data。
  private static func loadLookupCube(_ name: String) -> Data? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
          let img = NSImage(contentsOf: url),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return nil }

    let side = 512
    var px = [UInt8](repeating: 0, count: side * side * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8,
                              bytesPerRow: side * 4, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

    let dim = 64
    var cube = [Float](repeating: 0, count: dim * dim * dim * 4)
    var off = 0
    for b in 0 ..< dim {
      let cellX = (b % 8) * 64
      let cellYTop = (b / 8) * 64
      for g in 0 ..< dim {
        for r in 0 ..< dim {
          let x = cellX + r
          // CGBitmapContext buffer row0=top, 与标准 GPUImage 采样一致(不翻 y)
          let y = cellYTop + g
          let pi = (y * side + x) * 4
          cube[off] = Float(px[pi]) / 255
          cube[off + 1] = Float(px[pi + 1]) / 255
          cube[off + 2] = Float(px[pi + 2]) / 255
          cube[off + 3] = 1
          off += 4
        }
      }
    }
    return cube.withUnsafeBytes { Data($0) }
  }
}
