//
//  MetalBeautyRenderer.swift
//  Snapzy (靓相 Shotlit)
//
//  Metal beauty pipeline 实时美颜渲染管线
//  — face-slimming(瘦脸) + bilateral smoothing(磨皮) + whitening(美白)
//    + auto-framing(人脸居中缩小, 模糊背景填充) + mirror(镜像).
//

import CoreImage
import CoreVideo
import Metal
import simd

/// nonisolated + Sendable so the camera's background queue can call it.
nonisolated final class MetalBeautyRenderer: @unchecked Sendable {
  var smoothing: Float = 0.7   // 磨皮
  var whitening: Float = 0.1   // 美白(轻,避免偏色)
  var thinFace: Float = 0.0    // 瘦脸暂关(之前做坏=下巴变方,待专业重做)
  var chinFace: Float = 0.0    // 瘦下巴暂关
  var autoFrame: Bool = false  // 自动构图暂关(=脸被P一半的根源,先直接显示完整画面)
  var filter: BeautyFilterType = .original // 默认正常颜色(程序滤镜阴间,先止损,待专业.cube)

  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pipeline: MTLComputePipelineState
  private let ciContext: CIContext
  private var textureCache: CVMetalTextureCache?
  private let faceTracker = FaceTracker()

  // 跨帧平滑(防抖)
  private var smCenterX: CGFloat = 0.5
  private var smCenterY: CGFloat = 0.5
  private var smRoll: CGFloat = 0
  private var smSize: CGFloat = 0.4
  private var smChinX: CGFloat = 0.5
  private var smChinY: CGFloat = 0.0
  private var hasFace = false

  init() {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue(),
          let library = device.makeDefaultLibrary(),
          let fn = library.makeFunction(name: "beautyKernel"),
          let pipeline = try? device.makeComputePipelineState(function: fn)
    else { fatalError("Metal beauty pipeline unavailable") }
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

    // 1. 人脸检测(给瘦脸 + 自动构图共用) + 平滑
    if let face = faceTracker.detect(pixelBuffer) {
      let a: CGFloat = hasFace ? 0.2 : 1.0
      smCenterX += (face.centerX - smCenterX) * a
      smCenterY += (face.centerY - smCenterY) * a
      smRoll += (face.roll - smRoll) * a
      smSize += (face.size - smSize) * a
      smChinX += (face.chinX - smChinX) * a
      smChinY += (face.chinY - smChinY) * a
      hasFace = true
    }

    // 2. 输入/输出纹理
    var cvTexIn: CVMetalTexture?
    let status = CVMetalTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault, cache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexIn
    )
    guard status == kCVReturnSuccess, let cvTexIn,
          let inputTexture = CVMetalTextureGetTexture(cvTexIn) else { return nil }
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
    )
    desc.usage = [.shaderWrite, .shaderRead]
    guard let outputTexture = device.makeTexture(descriptor: desc) else { return nil }

    // 3. Metal: 瘦脸 + 磨皮 + 美白
    guard let cmd = queue.makeCommandBuffer(),
          let enc = cmd.makeComputeCommandEncoder() else { return nil }
    enc.setComputePipelineState(pipeline)
    enc.setTexture(inputTexture, index: 0)
    enc.setTexture(outputTexture, index: 1)
    var s = smoothing, wt = whitening
    enc.setBytes(&s, length: MemoryLayout<Float>.size, index: 0)
    enc.setBytes(&wt, length: MemoryLayout<Float>.size, index: 1)
    // face: (centerX, 1-centerY 转左上, size, thinFace)
    var face4 = SIMD4<Float>(Float(smCenterX), Float(1.0 - smCenterY), Float(smSize),
                             hasFace ? thinFace : 0)
    enc.setBytes(&face4, length: MemoryLayout<SIMD4<Float>>.size, index: 2)
    var chin = hasFace ? chinFace : 0
    enc.setBytes(&chin, length: MemoryLayout<Float>.size, index: 3)
    var chinPos = SIMD2<Float>(Float(smChinX), Float(1.0 - smChinY)) // 精确下巴尖(转左上原点)
    enc.setBytes(&chinPos, length: MemoryLayout<SIMD2<Float>>.size, index: 4)
    let tg = MTLSize(width: 16, height: 16, depth: 1)
    let groups = MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1)
    enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
    enc.endEncoding()
    cmd.commit()
    cmd.waitUntilCompleted()

    // 4. 纹理 → CIImage → 翻转到显示方向
    let opts: [CIImageOption: Any] = [.colorSpace: CGColorSpaceCreateDeviceRGB()]
    guard let mtlImage = CIImage(mtlTexture: outputTexture, options: opts) else { return nil }
    let extent = CGRect(x: 0, y: 0, width: w, height: h)
    var image = mtlImage.transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -h))

    // 5. 自动构图: 人脸居中缩小 + 模糊背景填充(消黑边)
    if autoFrame, hasFace {
      let fcx = smCenterX * w
      let fcy = (1.0 - smCenterY) * h
      let targetRatio: CGFloat = 0.40
      let scale = min(max(targetRatio / max(smSize, 0.01), 0.45), 2.0)
      let fg = image
        .transformed(by: CGAffineTransform(translationX: -fcx, y: -fcy))
        .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        .transformed(by: CGAffineTransform(translationX: w / 2, y: h / 2))
        .cropped(to: extent)
      let bg = image
        .clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 22])
        .cropped(to: extent)
      image = fg.composited(over: bg)
    }

    // 6. 滤镜
    image = filter.apply(image).cropped(to: extent)

    // 7. 水平镜像(像照镜子)
    image = image
      .transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -w, y: 0))
      .cropped(to: extent)

    return ciContext.createCGImage(image, from: extent)
  }
}
