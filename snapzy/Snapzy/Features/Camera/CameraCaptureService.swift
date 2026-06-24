//
//  CameraCaptureService.swift
//  Snapzy (靓相 Shotlit)
//
//  Camera capture 摄像头采集 — grabs frames, runs GpuPixel beauty, delivers processed frames.
//

import AVFoundation
import AppKit

/// Captures the webcam, runs beauty per-frame, calls back with processed CGImages.
/// 采集摄像头，逐帧美颜（GpuPixel 专业引擎），回调处理后的画面。
@MainActor
final class CameraCaptureService: NSObject {
  let session = AVCaptureSession()
  private let output = AVCaptureVideoDataOutput()
  private let videoQueue = DispatchQueue(label: "shotlit.camera.video")
  nonisolated let beauty = MetalBeautyRenderer() // 旧引擎(fallback)
  private var isConfigured = false

  // GpuPixel 专业美颜引擎(磨皮/美白/瘦脸/大眼), 在 videoQueue 线程使用
  nonisolated(unsafe) private var gpuBeauty: GpuPixelBeauty?
  nonisolated(unsafe) private var gpuInitTried = false
  nonisolated(unsafe) var useGpuPixel = false // 美颜引擎黑屏待修(OpenGL线程坑), 暂用正常画面
  nonisolated(unsafe) var gpSmoothing: Float = 0.6  // 磨皮
  nonisolated(unsafe) var gpWhitening: Float = 0.3  // 美白
  nonisolated(unsafe) var gpFaceSlim: Float = 0.0   // 瘦脸
  nonisolated(unsafe) var gpEyeZoom: Float = 0.0    // 大眼
  nonisolated(unsafe) var currentDeviceID: String?  // 当前摄像头设备唯一ID

  /// GpuPixel 资源目录(framework 内含 models/ 和 res/)
  nonisolated private static var gpuResourcePath: String {
    let fw = Bundle.main.privateFrameworksPath ?? Bundle.main.bundlePath
    return fw + "/gpupixel.framework/Resources"
  }

  /// Called on the main actor with each processed frame. 每帧处理后在主线程回调。
  var onFrame: (@MainActor (CGImage) -> Void)?

  func start() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureAndRun()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        guard granted else { return }
        Task { @MainActor in self.configureAndRun() }
      }
    default:
      break
    }
  }

  func stop() {
    if session.isRunning { session.stopRunning() }
  }

  /// 所有可用摄像头(含 iPhone 连续互通相机, 画质秒杀 Mac 前置)。
  func availableCameras() -> [AVCaptureDevice] {
    var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
    if #available(macOS 14.0, *) { types.append(.external); types.append(.continuityCamera) }
    return AVCaptureDevice.DiscoverySession(
      deviceTypes: types, mediaType: .video, position: .unspecified).devices
  }

  /// 切换摄像头(重配 session input, 保留 output)。
  func switchCamera(to device: AVCaptureDevice) {
    session.beginConfiguration()
    for input in session.inputs { session.removeInput(input) }
    if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
      session.addInput(input)
      currentDeviceID = device.uniqueID
    }
    session.commitConfiguration()
  }

  private func configureAndRun() {
    if !isConfigured {
      session.beginConfiguration()
      session.sessionPreset = .high
      let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        ?? AVCaptureDevice.default(for: .video)
      if let device,
         let input = try? AVCaptureDeviceInput(device: device),
         session.canAddInput(input) {
        session.addInput(input)
      }
      output.alwaysDiscardsLateVideoFrames = true
      output.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      ]
      output.setSampleBufferDelegate(self, queue: videoQueue)
      if session.canAddOutput(output) { session.addOutput(output) }
      session.commitConfiguration()
      isConfigured = true
    }
    if !session.isRunning {
      session.startRunning()
    }
  }

  // MARK: - GpuPixel 帧处理(videoQueue 线程, OpenGL 上下文亲和此线程)

  nonisolated private func processWithGpuPixel(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
    if !gpuInitTried {
      gpuInitTried = true
      gpuBeauty = GpuPixelBeauty(resourcePath: Self.gpuResourcePath)
      if gpuBeauty == nil { NSLog("[Camera] GpuPixel 初始化失败, 回退旧引擎") }
    }
    guard let gp = gpuBeauty else { return nil }
    gp.setSmoothing(gpSmoothing, whitening: gpWhitening, faceSlim: gpFaceSlim, eyeZoom: gpEyeZoom)

    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
    let w = CVPixelBufferGetWidth(pixelBuffer)
    let h = CVPixelBufferGetHeight(pixelBuffer)
    let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
    var ow: Int32 = 0, oh: Int32 = 0
    guard let rgba = gp.processBGRA(base.assumingMemoryBound(to: UInt8.self),
                                    width: Int32(w), height: Int32(h), stride: Int32(stride),
                                    outWidth: &ow, outHeight: &oh) else { return nil }
    return Self.rgbaToCGImage(rgba, width: Int(ow), height: Int(oh))
  }

  nonisolated private static func rgbaToCGImage(_ data: Data, width: Int, height: Int) -> CGImage? {
    guard width > 0, height > 0, data.count >= width * height * 4 else { return nil }
    let cs = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(
      rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: width * 4, space: cs, bitmapInfo: bitmapInfo,
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }
}

// MARK: - Frame delegate (runs on videoQueue) 帧回调(在后台队列)

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
  nonisolated func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    var cgImage: CGImage?
    if useGpuPixel {
      cgImage = processWithGpuPixel(pixelBuffer)
    }
    if cgImage == nil {
      cgImage = beauty.process(pixelBuffer) // 回退旧引擎
    }
    guard let result = cgImage else { return }
    let sendable = UncheckedSendableImage(result)
    Task { @MainActor in
      self.onFrame?(sendable.image)
    }
  }
}

/// Wrap CGImage to cross the isolation boundary. 包装 CGImage 以跨越隔离边界。
private struct UncheckedSendableImage: @unchecked Sendable {
  let image: CGImage
  init(_ image: CGImage) { self.image = image }
}
