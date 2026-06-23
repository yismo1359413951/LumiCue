//
//  FaceTracker.swift
//  Snapzy (靓相 Shotlit)
//
//  Face tracking 人脸追踪 — Apple Vision 检测人脸位置与倾斜角(自动构图/拉正用).
//

import CoreVideo
import Foundation
import Vision

/// Detects the primary face's position and roll. 检测主要人脸的位置与倾斜角。
/// nonisolated + Sendable so the camera's background queue can call it.
nonisolated final class FaceTracker: @unchecked Sendable {
  struct FaceInfo {
    var centerX: CGFloat // normalized 0~1 (Vision origin 左下)
    var centerY: CGFloat
    var roll: CGFloat // 弧度, 头部倾斜角
    var size: CGFloat // normalized, max(width,height)
  }

  /// Detect the largest face in the frame. 检测画面中最大的人脸。
  func detect(_ pixelBuffer: CVPixelBuffer) -> FaceInfo? {
    let request = VNDetectFaceRectanglesRequest()
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
    try? handler.perform([request])
    guard let faces = request.results as? [VNFaceObservation], !faces.isEmpty else { return nil }
    // 取最大的脸
    let face = faces.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }!
    let bb = face.boundingBox
    let roll: CGFloat = face.roll.map { CGFloat(truncating: $0) } ?? 0
    return FaceInfo(centerX: bb.midX, centerY: bb.midY, roll: roll, size: max(bb.width, bb.height))
  }
}
