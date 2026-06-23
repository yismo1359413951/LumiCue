//
//  SandboxOffDataMigrationServiceTests.swift
//  SnapzyTests
//
//  Tests for one-time App Sandbox data migration.
//

import Foundation
import XCTest
@testable import Snapzy

@MainActor
final class SandboxOffDataMigrationServiceTests: XCTestCase {
  private var rootDirectory: URL!
  private var homeDirectory: URL!
  private var libraryDirectory: URL!
  private var applicationSupportDirectory: URL!
  private var defaults: UserDefaults!
  private var bundleIdentifier: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    rootDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_SandboxOffMigration_\(UUID().uuidString)", isDirectory: true)
    homeDirectory = rootDirectory.appendingPathComponent("Home", isDirectory: true)
    libraryDirectory = rootDirectory
      .appendingPathComponent("DestinationLibrary", isDirectory: true)
    applicationSupportDirectory = libraryDirectory
      .appendingPathComponent("Application Support", isDirectory: true)
    bundleIdentifier = "com.trongduong.snapzy.tests.\(UUID().uuidString)"
    defaults = UserDefaultsFactory.make()

    try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    defaults.removeObject(forKey: PreferencesKeys.sandboxOffMigrationCompleted)
    defaults = nil
    try? FileManager.default.removeItem(at: rootDirectory)
    try super.tearDownWithError()
  }

  func testRunIfNeeded_migratesSandboxedApplicationSupportPreferencesAndLogsOnce() throws {
    let sourceData = sourceDataDirectory()
    let sourceAppSupport = sourceData
      .appendingPathComponent("Library/Application Support/Snapzy", isDirectory: true)
    let sourceLogs = sourceData
      .appendingPathComponent("Library/Logs/Snapzy", isDirectory: true)
    let sourcePreferences = sourceData
      .appendingPathComponent("Library/Preferences", isDirectory: true)
      .appendingPathComponent("\(bundleIdentifier!).plist")
    try FileManager.default.createDirectory(at: sourceAppSupport, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: sourceAppSupport.appendingPathComponent("Captures", isDirectory: true),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(at: sourceLogs, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: sourcePreferences.deletingLastPathComponent(), withIntermediateDirectories: true)

    try Data("database".utf8).write(to: sourceAppSupport.appendingPathComponent("snapzy.db"))
    try Data("capture".utf8).write(to: sourceAppSupport.appendingPathComponent("Captures/capture.png"))
    try Data("log".utf8).write(to: sourceLogs.appendingPathComponent("snapzy_2026-06-21.txt"))
    XCTAssertTrue(
      ([
        PreferencesKeys.screenshotFormat: "webp",
        PreferencesKeys.historyEnabled: false,
      ] as NSDictionary).write(to: sourcePreferences, atomically: true)
    )

    let firstResult = try makeService().runIfNeeded()

    XCTAssertTrue(firstResult.didRun)
    XCTAssertEqual(firstResult.copiedApplicationSupportItems, 2)
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.screenshotFormat), "webp")
    XCTAssertFalse(defaults.bool(forKey: PreferencesKeys.historyEnabled))
    XCTAssertTrue(defaults.bool(forKey: PreferencesKeys.sandboxOffMigrationCompleted))
    XCTAssertTrue(FileManager.default.fileExists(atPath: destinationAppSupport().appendingPathComponent("snapzy.db").path))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: destinationAppSupport().appendingPathComponent("Captures/capture.png").path
      )
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: libraryDirectory.appendingPathComponent("Logs/Snapzy/snapzy_2026-06-21.txt").path
      )
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: destinationAppSupport().appendingPathComponent(".sandbox-off-migration-completed").path
      )
    )

    let secondResult = try makeService().runIfNeeded()

    XCTAssertFalse(secondResult.didRun)
    XCTAssertEqual(secondResult.copiedApplicationSupportItems, 0)
  }

  func testRunIfNeeded_preservesExistingUnsandboxedFilesAndPreferences() throws {
    let sourceAppSupport = sourceDataDirectory()
      .appendingPathComponent("Library/Application Support/Snapzy", isDirectory: true)
    try FileManager.default.createDirectory(
      at: sourceAppSupport.appendingPathComponent("Captures", isDirectory: true),
      withIntermediateDirectories: true
    )
    try Data("sandbox database".utf8).write(to: sourceAppSupport.appendingPathComponent("snapzy.db"))
    try Data("sandbox capture".utf8).write(to: sourceAppSupport.appendingPathComponent("Captures/capture.png"))

    try FileManager.default.createDirectory(
      at: destinationAppSupport().appendingPathComponent("Captures", isDirectory: true),
      withIntermediateDirectories: true
    )
    try Data("current database".utf8).write(to: destinationAppSupport().appendingPathComponent("snapzy.db"))

    let sourcePreferences = sourceDataDirectory()
      .appendingPathComponent("Library/Preferences", isDirectory: true)
      .appendingPathComponent("\(bundleIdentifier!).plist")
    try FileManager.default.createDirectory(at: sourcePreferences.deletingLastPathComponent(), withIntermediateDirectories: true)
    XCTAssertTrue(
      ([
        PreferencesKeys.historyEnabled: false,
        PreferencesKeys.screenshotFormat: "webp",
      ] as NSDictionary).write(to: sourcePreferences, atomically: true)
    )

    let destinationPreferences = libraryDirectory
      .appendingPathComponent("Preferences", isDirectory: true)
      .appendingPathComponent("\(bundleIdentifier!).plist")
    try FileManager.default.createDirectory(at: destinationPreferences.deletingLastPathComponent(), withIntermediateDirectories: true)
    XCTAssertTrue(([PreferencesKeys.historyEnabled: true] as NSDictionary).write(to: destinationPreferences, atomically: true))
    defaults.set(true, forKey: PreferencesKeys.historyEnabled)

    let result = try makeService().runIfNeeded()

    XCTAssertEqual(result.copiedApplicationSupportItems, 1)
    XCTAssertEqual(result.skippedApplicationSupportItems, 1)
    XCTAssertEqual(
      try String(contentsOf: destinationAppSupport().appendingPathComponent("snapzy.db")),
      "current database"
    )
    XCTAssertEqual(
      try String(contentsOf: destinationAppSupport().appendingPathComponent("Captures/capture.png")),
      "sandbox capture"
    )
    XCTAssertTrue(defaults.bool(forKey: PreferencesKeys.historyEnabled))
    XCTAssertEqual(defaults.string(forKey: PreferencesKeys.screenshotFormat), "webp")
  }

  func testRunIfNeeded_skipsWhileStillRunningSandboxed() throws {
    let result = try makeService(isRunningSandboxed: true).runIfNeeded()

    XCTAssertFalse(result.didRun)
    XCTAssertFalse(defaults.bool(forKey: PreferencesKeys.sandboxOffMigrationCompleted))
  }

  func testRunIfNeeded_marksCompletedWhenNoSandboxContainerExists() throws {
    let firstResult = try makeService().runIfNeeded()
    let secondResult = try makeService().runIfNeeded()

    XCTAssertTrue(firstResult.didRun)
    XCTAssertFalse(secondResult.didRun)
    XCTAssertTrue(defaults.bool(forKey: PreferencesKeys.sandboxOffMigrationCompleted))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: destinationAppSupport().appendingPathComponent(".sandbox-off-migration-completed").path
      )
    )
  }

  func testRunIfNeeded_doesNotMarkCompletedWhenApplicationSupportCopyFails() throws {
    let sourceAppSupport = sourceDataDirectory()
      .appendingPathComponent("Library/Application Support/Snapzy", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceAppSupport, withIntermediateDirectories: true)
    try Data("database".utf8).write(to: sourceAppSupport.appendingPathComponent("snapzy.db"))

    try FileManager.default.removeItem(at: applicationSupportDirectory)
    try Data("not a directory".utf8).write(to: applicationSupportDirectory)

    XCTAssertThrowsError(try makeService().runIfNeeded())
    XCTAssertFalse(defaults.bool(forKey: PreferencesKeys.sandboxOffMigrationCompleted))
  }

  private func makeService(isRunningSandboxed: Bool = false) -> SandboxOffDataMigrationService {
    SandboxOffDataMigrationService {
      SandboxOffDataMigrationService.Configuration(
        bundleIdentifier: self.bundleIdentifier,
        homeDirectory: self.homeDirectory,
        applicationSupportDirectory: self.applicationSupportDirectory,
        libraryDirectory: self.libraryDirectory,
        userDefaults: self.defaults,
        fileManager: .default,
        isRunningSandboxed: isRunningSandboxed
      )
    }
  }

  private func sourceDataDirectory() -> URL {
    homeDirectory
      .appendingPathComponent("Library/Containers", isDirectory: true)
      .appendingPathComponent(bundleIdentifier, isDirectory: true)
      .appendingPathComponent("Data", isDirectory: true)
  }

  private func destinationAppSupport() -> URL {
    applicationSupportDirectory.appendingPathComponent("Snapzy", isDirectory: true)
  }
}

