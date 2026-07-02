import AppKit
import XCTest
@testable import LumiCue

@MainActor
final class TeleprompterDisplayTextComposerTests: XCTestCase {
  func testDisplayLines_removesWhitespaceButKeepsPunctuation() {
    let lines = TeleprompterDisplayTextComposer.displayLines(
      from: "你 好　世\t界，Hello  world！A B C​D﻿E。",
      wrapWidth: 2000,
      font: .systemFont(ofSize: 30, weight: .semibold),
      paragraphStyle: centeredParagraph()
    )

    XCTAssertEqual(lines, ["你好世界，Helloworld！ABCDE。"])
  }

  func testDisplayLines_wrapsAtCharacterBoundariesWithoutChangingContent() {
    let lines = TeleprompterDisplayTextComposer.displayLines(
      from: "我建议都做，但主推一个。如果只押三个，我会押A+B的混合：",
      wrapWidth: 240,
      font: .systemFont(ofSize: 30, weight: .semibold),
      paragraphStyle: centeredParagraph()
    )

    XCTAssertGreaterThan(lines.count, 1)
    XCTAssertEqual(lines.joined(), "我建议都做，但主推一个。如果只押三个，我会押A+B的混合：")
    XCTAssertTrue(lines.allSatisfy { !$0.contains(where: \.isWhitespace) })
  }

  private func centeredParagraph() -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineBreakMode = .byWordWrapping
    return style
  }
}
