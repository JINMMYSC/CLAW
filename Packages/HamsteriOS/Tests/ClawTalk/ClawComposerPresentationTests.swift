import XCTest
@testable import HamsteriOS

final class ClawComposerPresentationTests: XCTestCase {
  func testEmptyComposerShowsPlusAction() {
    XCTAssertEqual(ClawComposerPresentation.trailingAction(for: "  \n"), .more)
  }

  func testNonEmptyComposerShowsSendAction() {
    XCTAssertEqual(ClawComposerPresentation.trailingAction(for: "你好"), .send)
  }
}
