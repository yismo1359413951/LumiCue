//
//  AreaSelectionModelsTests.swift
//  SnapzyTests
//
//  Unit tests for AreaSelectionTarget, AreaSelectionResult, and WindowCaptureTarget.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class AreaSelectionModelsTests: XCTestCase {

  func testAreaSelectionTarget_rect_returnsRect() {
    let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
    let target = AreaSelectionTarget.rect(rect)
    XCTAssertEqual(target.rect, rect)
    XCTAssertNil(target.windowTarget)
  }

  func testAreaSelectionTarget_window_returnsFrameAndTarget() {
    let windowTarget = WindowCaptureTarget(
      windowID: 42,
      frame: CGRect(x: 0, y: 0, width: 800, height: 600),
      displayID: 1,
      title: "Test",
      bundleIdentifier: "com.test",
      ownerPID: nil
    )
    let target = AreaSelectionTarget.window(windowTarget)
    XCTAssertEqual(target.rect, windowTarget.frame)
    XCTAssertEqual(target.windowTarget, windowTarget)
  }

  func testAreaSelectionResult_defaultDisplayIDs() {
    let result = AreaSelectionResult(
      target: .rect(CGRect(x: 0, y: 0, width: 100, height: 100)),
      displayID: 1,
      mode: .screenshot
    )
    XCTAssertEqual(result.displayIDs, [1])
    XCTAssertFalse(result.spansMultipleDisplays)
  }

  func testAreaSelectionResult_multipleDisplayIDs() {
    let result = AreaSelectionResult(
      target: .rect(CGRect(x: 0, y: 0, width: 100, height: 100)),
      displayID: 1,
      mode: .screenshot,
      displayIDs: [1, 2]
    )
    XCTAssertTrue(result.spansMultipleDisplays)
    XCTAssertEqual(result.displayIDs.count, 2)
  }

  func testAreaSelectionResult_rectAccessor() {
    let rect = CGRect(x: 5, y: 5, width: 50, height: 50)
    let result = AreaSelectionResult(
      target: .rect(rect),
      displayID: 1,
      mode: .recording
    )
    XCTAssertEqual(result.rect, rect)
  }

  func testWindowCaptureTarget_equatable() {
    let a = WindowCaptureTarget(windowID: 1, frame: .zero, displayID: 1, title: nil, bundleIdentifier: nil, ownerPID: nil)
    let b = WindowCaptureTarget(windowID: 1, frame: .zero, displayID: 1, title: nil, bundleIdentifier: nil, ownerPID: nil)
    let c = WindowCaptureTarget(windowID: 2, frame: .zero, displayID: 1, title: nil, bundleIdentifier: nil, ownerPID: nil)
    XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, c)
  }
}
