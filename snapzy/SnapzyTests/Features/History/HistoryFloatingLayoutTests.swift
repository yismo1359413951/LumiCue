//
//  HistoryFloatingLayoutTests.swift
//  SnapzyTests
//
//  Unit tests for HistoryFloatingLayout math and HistoryFloatingTimeFilter.
//

import AppKit
import XCTest
@testable import Snapzy

final class HistoryFloatingLayoutTests: XCTestCase {

  // MARK: - clampedScale

  func testClampedScale_clampsBelowMinimum() {
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(0.1), 0.8)
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(-5), 0.8)
  }

  func testClampedScale_clampsAboveMaximum() {
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(2.0), 1.4)
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(99), 1.4)
  }

  func testClampedScale_passesThroughValidRange() {
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(0.8), 0.8)
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(1.0), 1.0)
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(1.25), 1.25)
    XCTAssertEqual(HistoryFloatingLayout.clampedScale(1.4), 1.4)
  }

  // MARK: - storedScale

  func testStoredScale_readsPersistedValue() throws {
    let defaults = try makeDefaults()
    defaults.set(1.25, forKey: PreferencesKeys.historyFloatingScale)

    XCTAssertEqual(HistoryFloatingLayout.storedScale(userDefaults: defaults), 1.25, accuracy: 0.0001)
  }

  func testStoredScale_clampsPersistedValue() throws {
    let defaults = try makeDefaults()
    defaults.set(5.0, forKey: PreferencesKeys.historyFloatingScale)

    XCTAssertEqual(HistoryFloatingLayout.storedScale(userDefaults: defaults), 1.4, accuracy: 0.0001)
  }

  func testStoredScale_defaultsToOneWhenMissing() throws {
    let defaults = try makeDefaults()
    XCTAssertEqual(HistoryFloatingLayout.storedScale(userDefaults: defaults), 1.0, accuracy: 0.0001)
  }

  // MARK: - basePanelSize

  func testBasePanelSize_compact() {
    let size = HistoryFloatingLayout.basePanelSize(for: .compact)
    XCTAssertEqual(size, CGSize(width: 920, height: 316))
  }

  func testBasePanelSize_expanded() {
    let size = HistoryFloatingLayout.basePanelSize(for: .expanded)
    XCTAssertEqual(size, CGSize(width: 1040, height: 680))
  }

  // MARK: - baseCornerRadius

  func testBaseCornerRadius_compact() {
    XCTAssertEqual(HistoryFloatingLayout.baseCornerRadius(for: .compact), 30)
  }

  func testBaseCornerRadius_expanded() {
    XCTAssertEqual(HistoryFloatingLayout.baseCornerRadius(for: .expanded), 32)
  }

  // MARK: - HistoryFloatingTimeFilter

  func testTimeFilterAllIncludesAnyDate() {
    let now = Date()
    XCTAssertTrue(HistoryFloatingTimeFilter.all.includes(now.addingTimeInterval(-1_000_000), relativeTo: now))
    XCTAssertTrue(HistoryFloatingTimeFilter.all.includes(now.addingTimeInterval(100), relativeTo: now))
  }

  func testTimeFilterLast24HoursExcludesOlder() {
    let now = Date()
    XCTAssertTrue(HistoryFloatingTimeFilter.last24Hours.includes(now.addingTimeInterval(-3600), relativeTo: now))
    XCTAssertFalse(HistoryFloatingTimeFilter.last24Hours.includes(now.addingTimeInterval(-100_000), relativeTo: now))
  }

  func testTimeFilterLast7DaysExcludesOlder() {
    let now = Date()
    XCTAssertTrue(HistoryFloatingTimeFilter.last7Days.includes(now.addingTimeInterval(-100_000), relativeTo: now))
    XCTAssertFalse(HistoryFloatingTimeFilter.last7Days.includes(now.addingTimeInterval(-1_000_000), relativeTo: now))
  }

  func testTimeFilterLast30DaysExcludesOlder() {
    let now = Date()
    XCTAssertTrue(HistoryFloatingTimeFilter.last30Days.includes(now.addingTimeInterval(-1_000_000), relativeTo: now))
    XCTAssertFalse(HistoryFloatingTimeFilter.last30Days.includes(now.addingTimeInterval(-10_000_000), relativeTo: now))
  }

  func testTimeFilterAllCasesAreUnique() {
    let all = HistoryFloatingTimeFilter.allCases
    XCTAssertEqual(Set(all).count, all.count)
  }

  // MARK: - HistoryFloatingPresentationMode

  func testPresentationModeEquality() {
    XCTAssertEqual(HistoryFloatingPresentationMode.compact, HistoryFloatingPresentationMode.compact)
    XCTAssertNotEqual(HistoryFloatingPresentationMode.compact, HistoryFloatingPresentationMode.expanded)
  }

  // MARK: - Helpers

  private func makeDefaults(
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> UserDefaults {
    let suiteName = "SnapzyTests.HistoryFloatingLayoutTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName), file: file, line: line)
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}
