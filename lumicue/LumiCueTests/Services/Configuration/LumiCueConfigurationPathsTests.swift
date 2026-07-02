//
//  LumiCueConfigurationPathsTests.swift
//  LumiCueTests
//
//  Tests for user-managed TOML configuration paths.
//

import Darwin
import XCTest
@testable import LumiCue

@MainActor
final class LumiCueConfigurationPathsTests: XCTestCase {
  func testSuggestedConfigURLUsesProvidedHomeDirectory() {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    let url = LumiCueConfigurationPaths.suggestedConfigURL(homeDirectory: home)

    XCTAssertEqual(url.path, "/Users/example/.config/lumicue/config.toml")
  }

  func testSuggestedConfigDirectoryURLUsesProvidedHomeDirectory() {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    let url = LumiCueConfigurationPaths.suggestedConfigDirectoryURL(homeDirectory: home)

    XCTAssertEqual(url.path, "/Users/example/.config/lumicue")
  }

  func testExpandedUserPathUsesProvidedHomeDirectory() {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    XCTAssertEqual(
      LumiCueConfigurationPaths.expandedUserPath("~/Desktop", homeDirectory: home),
      "/Users/example/Desktop"
    )
    XCTAssertEqual(
      LumiCueConfigurationPaths.expandedUserPath("/tmp/lumicue", homeDirectory: home),
      "/tmp/lumicue"
    )
  }

  func testSuggestedConfigURLUsesAccountHomeDirectory() throws {
    guard
      let passwd = getpwuid(getuid()),
      let home = passwd.pointee.pw_dir
    else {
      throw XCTSkip("No POSIX home directory is available for the current user.")
    }

    let expectedHome = URL(fileURLWithPath: String(cString: home), isDirectory: true)
    let expectedURL = LumiCueConfigurationPaths.suggestedConfigURL(homeDirectory: expectedHome)

    XCTAssertEqual(LumiCueConfigurationService.shared.suggestedConfigURL.path, expectedURL.path)
  }
}
