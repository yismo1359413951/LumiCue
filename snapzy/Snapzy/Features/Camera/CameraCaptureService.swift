//
//  CameraCaptureService.swift
//  Snapzy (靓相 Shotlit)
//
//  Camera capture 摄像头采集 — grabs frames, runs beauty, delivers processed frames.
//

import AVFoundation
import AppKit

/// Captures the webcam, runs beauty per-frame, calls back with processed CGImages.
/// 采集摄像头，逐帧美颜，回调处理后的画面。
@MainActor
final class CameraCaptureService: NSObject {
  let session = AVCaptureSession()
  private let output = AVCaptureVideoDataOutput()
  private let videoQueue = DispatchQueue(label: "shotlit.camera.video")
  nonisolated let beauty = BeautyProcessor()
  private var isConfigured = false

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
}

// MARK: - Frame delegate (runs on videoQueue) 帧回调(在后台队列)

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
  nonisolated func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    guard let cgImage = beauty.process(pixelBuffer) else { return }
    let sendable = UncheckedSendableImage(cgImage)
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
