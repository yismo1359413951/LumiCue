//
//  RecordingAnnotationStateTests.swift
//  SnapzyTests
//
//  Unit tests for RecordingAnnotationState append, clear, count limit, and cleanup.
//

import CoreGraphics
import XCTest
@testable import Snapzy

@MainActor
final class RecordingAnnotationStateTests: XCTestCase {

  private var state: RecordingAnnotationState!

  override func setUp() {
    super.setUp()
    state = RecordingAnnotationState()
  }

  override func tearDown() {
    state.stopCleanupTimer()
    state = nil
    super.tearDown()
  }

  func testAppendAnnotation_increasesCount() {
    let item = AnnotationItem(type: .rectangle, bounds: CGRect(x: 0, y: 0, width: 10, height: 10), properties: AnnotationProperties())
    state.appendAnnotation(item, tool: .rectangle)
    XCTAssertEqual(state.annotations.count, 1)
  }

  func testClearAll_removesAll() {
    let item = AnnotationItem(type: .rectangle, bounds: CGRect(x: 0, y: 0, width: 10, height: 10), properties: AnnotationProperties())
    state.appendAnnotation(item, tool: .rectangle)
    state.clearAll()
    XCTAssertTrue(state.annotations.isEmpty)
    XCTAssertNil(state.selectedAnnotationId)
  }

  func testDeleteSelected_removesSelected() {
    let item = AnnotationItem(type: .rectangle, bounds: CGRect(x: 0, y: 0, width: 10, height: 10), properties: AnnotationProperties())
    state.appendAnnotation(item, tool: .rectangle)
    state.selectedAnnotationId = item.id
    state.deleteSelected()
    XCTAssertTrue(state.annotations.isEmpty)
    XCTAssertNil(state.selectedAnnotationId)
  }

  func testDeleteSelected_noSelection_noOp() {
    let item = AnnotationItem(type: .rectangle, bounds: CGRect(x: 0, y: 0, width: 10, height: 10), properties: AnnotationProperties())
    state.appendAnnotation(item, tool: .rectangle)
    state.deleteSelected()
    XCTAssertEqual(state.annotations.count, 1)
  }

  func testClearMode_defaultIsPersist() {
    XCTAssertEqual(state.clearMode(for: .rectangle), .persist)
  }

  func testEnforceCountLimit_removesOldest() {
    state.toolClearModes[.rectangle] = .countBased(count: 2)
    for i in 0..<4 {
      let item = AnnotationItem(type: .rectangle, bounds: CGRect(x: CGFloat(i), y: 0, width: 10, height: 10), properties: AnnotationProperties())
      state.appendAnnotation(item, tool: .rectangle)
    }
    XCTAssertEqual(state.annotations.count, 2)
  }

  func testEnforceCountLimit_persistDoesNotRemove() {
    state.toolClearModes[.rectangle] = .persist
    for i in 0..<5 {
      let item = AnnotationItem(type: .rectangle, bounds: CGRect(x: CGFloat(i), y: 0, width: 10, height: 10), properties: AnnotationProperties())
      state.appendAnnotation(item, tool: .rectangle)
    }
    XCTAssertEqual(state.annotations.count, 5)
  }

  func testRemoveExpired_timeBased() {
    state.toolClearModes[.pencil] = .timeBased(seconds: 0.1)
    let item = AnnotationItem(type: .path([CGPoint(x: 0, y: 0)]), bounds: .zero, properties: AnnotationProperties())
    state.appendAnnotation(item, tool: .pencil)
    XCTAssertEqual(state.annotations.count, 1)
    Thread.sleep(forTimeInterval: 0.15)
    state.startCleanupTimer()
    // Allow timer to fire at least once
    let expectation = self.expectation(description: "cleanup")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 2.0)
    XCTAssertTrue(state.annotations.isEmpty)
  }

  func testStartStopCleanupTimer_noCrash() {
    state.startCleanupTimer()
    state.stopCleanupTimer()
  }
}
