import XCTest
@testable import HamsteriOS

final class ClawComposerPresentationTests: XCTestCase {
  func testEmptyComposerShowsPlusAction() {
    XCTAssertEqual(ClawComposerPresentation.trailingAction(for: "  \n"), .more)
  }

  func testNonEmptyComposerShowsSendAction() {
    XCTAssertEqual(ClawComposerPresentation.trailingAction(for: "你好"), .send)
  }

  func testOneShotDictationPreservesDraftForUserReview() {
    XCTAssertEqual(ClawComposerPresentation.appendDictation(" 你好 ", to: ""), "你好")
    XCTAssertEqual(ClawComposerPresentation.appendDictation("下一句", to: "未发送草稿"), "未发送草稿\n下一句")
    XCTAssertEqual(ClawComposerPresentation.appendDictation("   ", to: "未发送草稿"), "未发送草稿")
  }
}
