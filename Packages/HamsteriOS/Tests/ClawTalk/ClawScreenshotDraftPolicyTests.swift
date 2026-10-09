import XCTest
@testable import HamsterKeyboardKit

final class ClawScreenshotDraftPolicyTests: XCTestCase {
  func testPreservesExistingUnsentTextBeforeOCR() {
    XCTAssertEqual(
      ClawScreenshotDraftPolicy.combine(
        existing: "之前正在编辑的内容",
        recognized: "对方：刚下班\n我：辛苦啦"
      ),
      "之前正在编辑的内容\n对方：刚下班\n我：辛苦啦"
    )
  }

  func testEmptyOCRDoesNotClearDraft() {
    XCTAssertEqual(
      ClawScreenshotDraftPolicy.combine(existing: "原草稿", recognized: " \n "),
      "原草稿"
    )
  }

  func testExistingNewlineIsNotDoubled() {
    XCTAssertEqual(
      ClawScreenshotDraftPolicy.combine(existing: "已有\n", recognized: "新识别的文字"),
      "已有\n新识别的文字"
    )
  }

  func testRecognizedTextIsTrimmedButOriginalIsPreservedExactly() {
    XCTAssertEqual(
      ClawScreenshotDraftPolicy.combine(existing: "用户文字 ", recognized: " \n对方：你好\n "),
      "用户文字 \n对方：你好"
    )
  }
}
