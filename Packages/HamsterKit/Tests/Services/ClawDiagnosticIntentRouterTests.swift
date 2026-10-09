import Foundation
import XCTest
@testable import HamsterKit

final class ClawDiagnosticIntentRouterTests: XCTestCase {
  func testExplicitCommandsAndTypicalTroubleshootingQuestions() {
    XCTAssertEqual(ClawDiagnosticIntentRouter.match("/自检"), .overview)
    XCTAssertEqual(ClawDiagnosticIntentRouter.match("/diagnose"), .overview)
    XCTAssertEqual(ClawDiagnosticIntentRouter.match("刚才为什么语音识别不了？"), .voice)
    XCTAssertEqual(ClawDiagnosticIntentRouter.match("录音一直失败了"), .voice)
    XCTAssertEqual(ClawDiagnosticIntentRouter.match("iCloud 复制失败"), .sync)
    XCTAssertEqual(ClawDiagnosticIntentRouter.match("检查软件状态"), .overview)
  }

  func testNormalPersonalConversationDoesNotTriggerDiagnostics() {
    XCTAssertEqual(ClawDiagnosticIntentRouter.match("怎么和朋友发语音比较礼貌"), .none)
    XCTAssertEqual(ClawDiagnosticIntentRouter.match("我想和朋友同步一下安排"), .none)
    XCTAssertEqual(ClawDiagnosticIntentRouter.match("今天记忆里谁和我说过话"), .none)
    XCTAssertEqual(ClawDiagnosticIntentRouter.match("你好"), .none)
  }
}
