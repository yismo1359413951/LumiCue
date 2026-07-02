//
//  LumiCueDeepLinkHandlerTests.swift
//  LumiCueTests
//
//  Unit tests for lumicue:// automation URL parsing.
//

import XCTest
@testable import LumiCue

final class LumiCueDeepLinkHandlerTests: XCTestCase {

  func testCanonicalRoutesParseExpectedActions() throws {
    let cases: [(String, LumiCueDeepLinkAction)] = [
      ("lumicue://capture/fullscreen", .captureFullscreen),
      ("lumicue://capture/area", .captureArea),
      ("lumicue://capture/application", .captureApplication),
      ("lumicue://capture/area-annotate", .captureAreaAnnotate),
      ("lumicue://capture/scrolling", .captureScrolling),
      ("lumicue://capture/ocr", .captureOCR),
      ("lumicue://capture/smart-element", .captureSmartElement),
      ("lumicue://capture/object-cutout", .captureObjectCutout),
      ("lumicue://record/screen", .recordScreen),
      ("lumicue://record/application", .recordApplication),
      ("lumicue://open/annotate", .openAnnotate),
      ("lumicue://open/video-editor", .openVideoEditor),
      ("lumicue://open/cloud-uploads", .openCloudUploads),
      ("lumicue://open/history", .openHistory),
      ("lumicue://show/shortcuts", .showShortcuts),
      ("lumicue://settings", .openSettings(nil)),
    ]

    for (urlString, expectedAction) in cases {
      let url = try XCTUnwrap(URL(string: urlString))
      XCTAssertEqual(LumiCueDeepLinkAction(url: url), expectedAction, urlString)
    }
  }

  func testApplicationCaptureAliasesParseExpectedAction() throws {
    let aliases = [
      "lumicue://capture/window",
      "lumicue://application-capture",
      "lumicue://window-capture",
      "lumicue://screenshot/window",
    ]

    for urlString in aliases {
      let url = try XCTUnwrap(URL(string: urlString))
      XCTAssertEqual(LumiCueDeepLinkAction(url: url), .captureApplication, urlString)
    }
  }

  func testApplicationRecordingAliasesParseExpectedAction() throws {
    let aliases = [
      "lumicue://record/window",
      "lumicue://application-recording",
      "lumicue://window-recording",
      "lumicue://recording/window",
    ]

    for urlString in aliases {
      let url = try XCTUnwrap(URL(string: urlString))
      XCTAssertEqual(LumiCueDeepLinkAction(url: url), .recordApplication, urlString)
    }
  }

  func testSettingsTabRoutesParseExpectedTabs() throws {
    let cases: [(String, PreferencesTab)] = [
      ("general", .general),
      ("capture", .capture),
      ("annotate", .annotate),
      ("quick-access", .quickAccess),
      ("history", .history),
      ("shortcuts", .shortcuts),
      ("permissions", .permissions),
      ("cloud", .cloud),
      ("advanced", .advanced),
      ("about", .about),
    ]

    for (tabName, expectedTab) in cases {
      let queryURL = try XCTUnwrap(URL(string: "lumicue://settings?tab=\(tabName)"))
      XCTAssertEqual(LumiCueDeepLinkAction(url: queryURL), .openSettings(expectedTab), tabName)

      let pathURL = try XCTUnwrap(URL(string: "lumicue://settings/\(tabName)"))
      XCTAssertEqual(LumiCueDeepLinkAction(url: pathURL), .openSettings(expectedTab), tabName)
    }
  }

  func testUnsupportedRoutesReturnNil() throws {
    let urls = [
      "https://capture/area",
      "lumicue://",
      "lumicue://capture/unknown",
      "lumicue://record/stop",
      "lumicue://open/unknown",
    ]

    for urlString in urls {
      let url = try XCTUnwrap(URL(string: urlString))
      XCTAssertNil(LumiCueDeepLinkAction(url: url), urlString)
    }
  }
}
