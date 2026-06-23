//
//  BeautyFilterType.swift
//  Snapzy (靓相 Shotlit)
//
//  Filters 滤镜 — real 3D LUT (CIColorCube) color looks, like a beauty camera.
//  程序生成 3D LUT(色彩查找表)，做电影/日系/奶油肌等专业调色。
//  以后可换成导入专业 .cube 文件以达到顶级效果。
//

import CoreImage
import simd

/// Color filter looks backed by real 3D LUTs. 基于真 3D LUT 的滤镜。
enum BeautyFilterType: String, CaseIterable {
  case original, film, japanese, cream, vivid, warm, cool, fade, bw

  /// Display name (English then Chinese). 显示名(先英文后中文)。
  var displayName: String {
    switch self {
    case .original: return "Original 原图"
    case .film: return "Film 电影青橙"
    case .japanese: return "Japanese 日系"
    case .cream: return "Cream 奶油肌"
    case .vivid: return "Vivid 鲜艳"
    case .warm: return "Warm 暖阳"
    case .cool: return "Cool 冷调"
    case .fade: return "Fade 褪色"
    case .bw: return "B&W 黑白"
    }
  }

  /// Apply the LUT to an image. 把 LUT 应用到图像。
  func apply(_ image: CIImage) -> CIImage {
    guard self != .original, let data = Self.cubeData(for: self) else { return image }
    return image.applyingFilter("CIColorCube", parameters: [
      "inputCubeDimension": Self.dim,
      "inputCubeData": data,
    ]).cropped(to: image.extent)
  }

  // MARK: - LUT 生成(缓存)

  private static let dim = 32
  nonisolated(unsafe) private static var cache: [BeautyFilterType: Data] = [:]

  private static func cubeData(for type: BeautyFilterType) -> Data? {
    if let c = cache[type] { return c }
    let data = makeCube { type.map($0) }
    cache[type] = data
    return data
  }

  /// 单点色彩映射(输入/输出 rgb 0~1)。各滤镜的调色核心。
  private func map(_ c: SIMD3<Float>) -> SIMD3<Float> {
    let luma = simd_dot(c, SIMD3<Float>(0.299, 0.587, 0.114))
    switch self {
    case .original:
      return c
    case .film: // 电影青橙: 暗部偏青、亮部偏橙 + 加对比
      var o = c
      o.x += luma * 0.07          // 亮部加橙(红)
      o.y += (luma - 0.5) * 0.03
      o.z += (1 - luma) * 0.09    // 暗部加蓝青
      o = mixContrast(o, 1.12)
      return o
    case .japanese: // 日系: 提亮、降饱和、偏暖
      var o = c * 0.9 + 0.07
      o = desaturate(o, 0.18)
      o.x += 0.015; o.z -= 0.015
      return o
    case .cream: // 奶油肌: 提亮、暖、柔
      var o = c * 0.88 + 0.1
      o.x += 0.03; o.z -= 0.01
      o = mixContrast(o, 0.92)
      return o
    case .vivid: // 鲜艳: 增饱和 + 对比
      return mixContrast(saturate(c, 1.35), 1.08)
    case .warm: // 暖阳
      var o = c
      o.x += 0.05; o.z -= 0.04
      return o
    case .cool: // 冷调
      var o = c
      o.z += 0.06; o.x -= 0.03
      return o
    case .fade: // 褪色胶片: 抬黑 + 降对比 + 轻暖
      var o = c * 0.85 + 0.12
      o = desaturate(o, 0.1)
      return o
    case .bw: // 黑白
      return SIMD3<Float>(repeating: luma)
    }
  }

  // MARK: - 调色小工具

  private func mixContrast(_ c: SIMD3<Float>, _ k: Float) -> SIMD3<Float> {
    (c - 0.5) * k + 0.5
  }

  private func saturate(_ c: SIMD3<Float>, _ k: Float) -> SIMD3<Float> {
    let l = simd_dot(c, SIMD3<Float>(0.299, 0.587, 0.114))
    return SIMD3<Float>(repeating: l) + (c - SIMD3<Float>(repeating: l)) * k
  }

  private func desaturate(_ c: SIMD3<Float>, _ amount: Float) -> SIMD3<Float> {
    saturate(c, 1.0 - amount)
  }

  private static func makeCube(_ map: (SIMD3<Float>) -> SIMD3<Float>) -> Data {
    var floats = [Float](repeating: 0, count: dim * dim * dim * 4)
    var offset = 0
    let denom = Float(dim - 1)
    for b in 0 ..< dim {
      for g in 0 ..< dim {
        for r in 0 ..< dim {
          let inp = SIMD3<Float>(Float(r) / denom, Float(g) / denom, Float(b) / denom)
          let out = simd_clamp(map(inp), SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
          floats[offset] = out.x
          floats[offset + 1] = out.y
          floats[offset + 2] = out.z
          floats[offset + 3] = 1.0
          offset += 4
        }
      }
    }
    return floats.withUnsafeBytes { Data($0) }
  }
}
