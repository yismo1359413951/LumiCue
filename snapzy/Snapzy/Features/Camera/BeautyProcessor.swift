//
//  BeautyProcessor.swift
//  Snapzy (靓相 Shotlit)
//
//  Real-time beauty 实时美颜 — edge-preserving smoothing(保边磨皮) + whitening(美白).
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo

/// Core Image based beauty processor. 基于 Core Image 的美颜处理器。
/// nonisolated + Sendable so the camera's background queue can call it.
nonisolated final class BeautyProcessor: @unchecked Sendable {
  private let context = CIContext(options: [.useSoftwareRenderer: false])

  // ⚠️ Core Image 磨皮(降噪+gamma)效果差(雾蒙蒙),暂关。
  // 待移植 AwemeLike/GPUImage 的专业磨皮 shader(双边滤波+高反差保留+肤色检测)到 Metal。
  /// 磨皮强度 0~1  smoothing strength
  var smoothing: Float = 0.0
  /// 美白强度 0~1  whitening strength
  var whitening: Float = 0.0

  /// Process one camera frame, return a processed CGImage.
  /// 处理一帧摄像头画面，返回处理后的 CGImage。
  func process(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
    var image = CIImage(cvPixelBuffer: pixelBuffer)
    let extent = image.extent
    guard !extent.isEmpty else { return nil }

    // 磨皮: 保边降噪(磨皮肤瑕疵但保留五官清晰, 不糊)
    // edge-preserving noise reduction — smooths skin, keeps features sharp
    if smoothing > 0.01,
       let nr = CIFilter(name: "CINoiseReduction") {
      nr.setValue(image, forKey: kCIInputImageKey)
      nr.setValue(0.012 + 0.05 * smoothing, forKey: "inputNoiseLevel") // 磨皮力度
      nr.setValue(0.85, forKey: "inputSharpness")                      // 保留锐度(五官清晰)
      if let out = nr.outputImage?.cropped(to: extent) { image = out }
    }

    // 美白: 提亮 + gamma 提中间调 + 轻微降饱和
    // whitening — brighten + lift midtones via gamma + slight desaturate
    if whitening > 0.01 {
      let color = CIFilter.colorControls()
      color.inputImage = image
      color.brightness = 0.28 * whitening
      color.saturation = 1.0 - 0.05 * whitening
      color.contrast = 1.0
      if let out = color.outputImage?.cropped(to: extent) { image = out }

      if let gamma = CIFilter(name: "CIGammaAdjust") {
        gamma.setValue(image, forKey: kCIInputImageKey)
        gamma.setValue(1.0 - 0.3 * whitening, forKey: "inputPower") // <1 提亮
        if let out = gamma.outputImage?.cropped(to: extent) { image = out }
      }
    }

    return context.createCGImage(image, from: extent)
  }
}
