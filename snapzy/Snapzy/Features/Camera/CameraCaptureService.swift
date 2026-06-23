//
//  CameraCaptureService.swift
//  Snapzy (靓相 Shotlit)
//
//  Camera capture 摄像头采集 — front camera feed for the face bubble.
//

import AVFoundation
import AppKit

/// Captures the webcam feed and exposes a preview layer for the bubble.
/// 采集摄像头画面，提供给露脸 bubble 显示的预览层。
@MainActor
final class CameraCaptureService {
  let session = AVCaptureSession()
  let previewLayer: AVCaptureVideoPreviewLayer
  private var isConfigured = false

  init() {
    previewLayer = AVCaptureVideoPreviewLayer(session: session)
    previewLayer.videoGravity = .resizeAspectFill
  }

  /// Request permission then start the session. 请求权限并启动采集。
  func start() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureAndRun()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        guard granted else { return }
        Task { @MainActor in self.configureAndRun() }
      }
    case .denied, .restricted:
      break
    @unknown default:
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
      session.commitConfiguration()
      isConfigured = true
    }
    if !session.isRunning {
      session.startRunning()
    }
  }
}
