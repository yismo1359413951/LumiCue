//
//  MetalBeautyRenderer.swift
//  Snapzy (靓相 Shotlit)
//
//  Metal beauty pipeline 实时美颜渲染管线
//  — bilateral-filter beauty(磨皮美白) + auto-framing(人脸居中/拉正).
//

import CoreImage
import CoreVideo
import Metal

/// Runs Metal beauty + auto-framing on each camera frame, returns a CGImage.
/// 逐帧跑 Metal 美颜 + 自动构图(居中/拉正)，返回处理后 CGImage。
/// nonisolated + Sendable so the camera's background queue can call it.
nonisolated final class MetalBeautyRenderer: @unchecked Sendable {
  /// 磨皮强度 0~1
  var smoothing: Float = 0.7
  /// 美白强度 0~1
  var whitening: Float = 0.35
  /// 自动构图(人脸居中+水平拉正) auto-framing on/off
  var autoFrame: Bool = true
  /// 当前滤镜 current color filter
  var filter: BeautyFilterType = .japanese

  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLComputePipelineState
  private let ciContext: CIContext
  private var textureCache: CVMetalTextureCache?
  private let faceTracker = FaceTracker()

  // 跨帧平滑(防抖) smoothed face params
  private var smCenterX: CGFloat = 0.5
  private var smCenterY: CGFloat = 0.5
  private var smRoll: CGFloat = 0
  private var smSize: CGFloat = 0.4
  private var hasFace = false

  init() {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue(),
          let library = device.makeDefaultLibrary(),
          let fn = library.makeFunction(name: "beautyKernel"),
          let pipeline = try? device.makeComputePipelineState(function: fn)
    else {
      fatalError("Metal beauty pipeline unavailable")
    }
    self.device = device
    self.queue = queue
    self.pipeline = pipeline
    self.ciContext = CIContext(mtlDevice: device)
    CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
  }

  func process(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
    guard let cache = textureCache else { return nil }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let w = CGFloat(width), h = CGFloat(height)

    // 输入纹理
    var cvTextureIn: CVMetalTexture?
    let status = CVMetalTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault, cache, pixelBuffer, nil,
      .bgra8Unorm, width, height, 0, &cvTextureIn
    )
    guard status == kCVReturnSuccess,
          let cvTextureIn,
          let inputTexture = CVMetalTextureGetTexture(cvTextureIn)
    else { return nil }

    // 输出纹理
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
    )
    desc.usage = [.shaderWrite, .shaderRead]
    guard let outputTexture = device.makeTexture(descriptor: desc) else { return nil }

    // 跑美颜 compute
    guard let commandBuffer = queue.makeCommandBuffer(),
          let encoder = commandBuffer.makeComputeCommandEncoder()
    else { return nil }
    encoder.setComputePipelineState(pipeline)
    encoder.setTexture(inputTexture, index: 0)
    encoder.setTexture(outputTexture, index: 1)
    var s = smoothing
    var wt = whitening
    encoder.setBytes(&s, length: MemoryLayout<Float>.size, index: 0)
    encoder.setBytes(&wt, length: MemoryLayout<Float>.size, index: 1)
    let tg = MTLSize(width: 16, height: 16, depth: 1)
    let groups = MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1)
    encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    // 纹理 → CIImage → 翻转到显示方向
    let options: [CIImageOption: Any] = [.colorSpace: CGColorSpaceCreateDeviceRGB()]
    guard let mtlImage = CIImage(mtlTexture: outputTexture, options: options) else { return nil }
    let extent = CGRect(x: 0, y: 0, width: w, height: h)
    var image = mtlImage.transformed(
      by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -h)
    )

    // 自动构图: 人脸居中 + 水平拉正
    if autoFrame, let face = faceTracker.detect(pixelBuffer) {
      // 平滑(低通)防抖
      // 平滑(低通)跟随, 防抖
      let a: CGFloat = hasFace ? 0.2 : 1.0
      smCenterX += (face.centerX - smCenterX) * a
      smCenterY += (face.centerY - smCenterY) * a
      smRoll += (face.roll - smRoll) * a
      smSize += (face.size - smSize) * a
      hasFace = true

      let fcx = smCenterX * w
      let fcy = (1.0 - smCenterY) * h // 翻转后 y
      // 动态缩放: 让完整人脸占画面约 38%(脸更小,完整落在形状内,留足余量)
      let targetRatio: CGFloat = 0.38
      let scale = min(max(targetRatio / max(smSize, 0.01), 0.45), 2.0)

      // 诊断: 暂关旋转拉正(怀疑之前转歪了), 只做居中+缩放
      image = image
        .transformed(by: CGAffineTransform(translationX: -fcx, y: -fcy)) // 人脸→原点
        .transformed(by: CGAffineTransform(scaleX: scale, y: scale))      // 缩放到完整脸合适大小
        .transformed(by: CGAffineTransform(translationX: w / 2, y: h / 2)) // →画面中心
    }

    // crop + 黑底兜底(旋转露出的区域)
    let bg = CIImage(color: CIColor.black).cropped(to: extent)
    image = image.cropped(to: extent).composited(over: bg)

    // 滤镜 color filter
    image = filter.apply(image).cropped(to: extent)

    // 水平镜像(前置摄像头像照镜子, 符合直觉, 消除左右反的别扭感)
    image = image
      .transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -w, y: 0))
      .cropped(to: extent)

    return ciContext.createCGImage(image, from: extent)
  }
}
