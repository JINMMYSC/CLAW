import XCTest
@testable import HamsteriOS

final class ClawComposerPresentationTests: XCTestCase {
  func testEmptyComposerShowsPlusAction() {
    XCTAssertEqual(ClawComposerPresentation.trailingAction(for: "  \n"), .more)
  }

  func testNonEmptyComposerShowsSendAction() {
    XCTAssertEqual(ClawComposerPresentation.trailingAction(for: "你好"), .send)
  }

  func testSwitchingPeopleKeepsUnsentDraftsIsolated() {
    let alice = UUID(), bob = UUID()
    var cache: [String: String] = [:]
    let aliceText = "只属于艾丽的草稿"
    let bobText = ClawDraftContext.switching(
      currentText: aliceText, from: alice, to: bob, cache: &cache
    )
    XCTAssertEqual(bobText, "")
    let restored = ClawDraftContext.switching(
      currentText: "只属于贝贝的草稿", from: bob, to: alice, cache: &cache
    )
    XCTAssertEqual(restored, aliceText)
    let global = ClawDraftContext.switching(
      currentText: restored, from: alice, to: nil, cache: &cache
    )
    XCTAssertEqual(global, "")
    XCTAssertEqual(cache[ClawDraftContext.key(bob)], "只属于贝贝的草稿")
  }

  func testOneShotDictationPreservesDraftForUserReview() {
    XCTAssertEqual(ClawComposerPresentation.appendDictation(" 你好 ", to: ""), "你好")
    XCTAssertEqual(ClawComposerPresentation.appendDictation("下一句", to: "未发送草稿"), "未发送草稿\n下一句")
    XCTAssertEqual(ClawComposerPresentation.appendDictation("   ", to: "未发送草稿"), "未发送草稿")
  }
}
