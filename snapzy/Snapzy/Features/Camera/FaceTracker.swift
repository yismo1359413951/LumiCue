//
//  FaceTracker.swift
//  Snapzy (靓相 Shotlit)
//
//  Face tracking 人脸追踪 — Apple Vision 76点关键点(自动构图 + 分部位精细美颜).
//

import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// Detects the primary face: box + roll + 关键部位精确点(下巴/脸颊).
/// nonisolated + Sendable so the camera's background queue can call it.
nonisolated final class FaceTracker: @unchecked Sendable {
  struct FaceInfo {
    var centerX: CGFloat // 脸框中心(归一, Vision 左下原点)
    var centerY: CGFloat
    var roll: CGFloat
    var size: CGFloat
    // 分部位精确点(归一化, Vision 左下原点)
    var chinX: CGFloat = 0.5 // 下巴尖
    var chinY: CGFloat = 0.0
    var leftCheekX: CGFloat = 0.0 // 左脸颊外缘
    var rightCheekX: CGFloat = 1.0 // 右脸颊外缘
    var cheekY: CGFloat = 0.5
  }

  func detect(_ pixelBuffer: CVPixelBuffer) -> FaceInfo? {
    let request = VNDetectFaceLandmarksRequest()
    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
    try? handler.perform([request])
    guard let faces = request.results as? [VNFaceObservation], !faces.isEmpty else { return nil }
    let face = faces.max {
      $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
    }!
    let bb = face.boundingBox
    let roll: CGFloat = face.roll.map { CGFloat(truncating: $0) } ?? 0

    var info = FaceInfo(centerX: bb.midX, centerY: bb.midY, roll: roll, size: max(bb.width, bb.height))

    // 脸轮廓关键点 → 下巴尖 + 左右脸颊(转图像归一化坐标)
    if let contour = face.landmarks?.faceContour {
      let imgPts = contour.normalizedPoints.map {
        CGPoint(x: bb.minX + $0.x * bb.width, y: bb.minY + $0.y * bb.height)
      }
      if !imgPts.isEmpty {
        if let chin = imgPts.min(by: { $0.y < $1.y }) { // 最低点=下巴尖(Vision 左下, 下=y小)
          info.chinX = chin.x; info.chinY = chin.y
        }
        if let l = imgPts.min(by: { $0.x < $1.x }) { info.leftCheekX = l.x }
        if let r = imgPts.max(by: { $0.x < $1.x }) { info.rightCheekX = r.x }
        info.cheekY = bb.midY
      }
    }
    return info
  }
}
