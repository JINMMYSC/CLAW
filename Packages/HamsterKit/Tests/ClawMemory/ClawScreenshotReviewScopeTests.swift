import Foundation
import XCTest
@testable import HamsterKit

/// A reviewed screenshot must never silently cross a person's identity
/// boundary or turn synthetic rows into trusted human conversation history.
final class ClawScreenshotReviewScopeTests: XCTestCase {
  func testRejectsScreenshotBubbleAlreadyBoundToAnotherPerson() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-review-scope-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let service = ClawScreenshotIngestionService(store: store)
    let original = HeartTargetProfile(name: "原联系人")
    let selected = HeartTargetProfile(name: "另一联系人")
    let bubble = ClawConversationMessage(
      contactID: original.id, speaker: .other, content: "仅属于原联系人",
      sourceType: "screenshot", sourceRef: "screenshot-digest:cross-person"
    )

    XCTAssertThrowsError(try service.confirmReviewed(messages: [bubble], for: selected))
    XCTAssertTrue(try store.conversation(contactID: original.id).isEmpty)
    XCTAssertTrue(try store.conversation(contactID: selected.id).isEmpty)
  }

  func testRejectsSystemRowsInHumanScreenshotImport() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-review-system-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let profile = HeartTargetProfile(name: "审核对象")
    let row = ClawConversationMessage(
      contactID: profile.id, speaker: .system, content: "系统自动生成内容",
      sourceType: "screenshot", sourceRef: "screenshot-digest:system"
    )

    XCTAssertThrowsError(try ClawScreenshotIngestionService(store: store)
      .confirmReviewed(messages: [row], for: profile))
    XCTAssertTrue(try store.conversation(contactID: profile.id).isEmpty)
  }
}
