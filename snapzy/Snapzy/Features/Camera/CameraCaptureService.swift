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

  // 美颜参数(滑杆值; gpupixel 引擎已移除 — 它只有 x86_64 且与提词器无关, 曾导致 arm64 版闪退)
  nonisolated(unsafe) var gpSmoothing: Float = 0.6  // 磨皮
  nonisolated(unsafe) var gpWhitening: Float = 0.3  // 美白
  nonisolated(unsafe) var gpFaceSlim: Float = 0.0   // 瘦脸
  nonisolated(unsafe) var gpEyeZoom: Float = 0.0    // 大眼
  nonisolated(unsafe) var currentDeviceID: String?  // 当前摄像头设备唯一ID

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
    guard let result = beauty.process(pixelBuffer) else { return }   // Metal 美颜引擎
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
