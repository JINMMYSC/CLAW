import Foundation
import XCTest
@testable import HamsterKit

final class ClawScreenshotUnpersistedProfilePrivacyTests: XCTestCase {
  func testExplicitReviewRejectsNeverSavedContactWithoutAnyMemoryWrites() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-unpersisted-review-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    // A transient OCR identity is not a persisted, user-confirmed contact.
    let unpersisted = HeartTargetProfile(name: "Synthetic unpersisted contact \(UUID())")
    let message = ClawConversationMessage(
      contactID: unpersisted.id, speaker: .other,
      content: "Private OCR bubble", sourceType: "screenshot"
    )

    XCTAssertThrowsError(
      try ClawScreenshotIngestionService(store: store)
        .confirmReviewedWithReceipt(messages: [message], for: unpersisted),
      "A caller-provided profile snapshot must not authorize private chat storage"
    )
    XCTAssertTrue(try store.conversation(contactID: unpersisted.id).isEmpty)
    XCTAssertTrue(try store.tasks().isEmpty)
    XCTAssertEqual(try store.memoryV2Count(), 0)
  }

  func testUnboundOCRBubbleCannotBeImportedUnderUnpersistedContact() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-unbound-review-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let unpersisted = HeartTargetProfile(name: "Never saved \(UUID())")
    let message = ClawConversationMessage(
      contactID: nil, speaker: .me,
      content: "Unbound OCR bubble", sourceType: "screenshot"
    )

    XCTAssertThrowsError(
      try ClawScreenshotIngestionService(store: store)
        .confirmReviewed(messages: [message], for: unpersisted)
    )
    XCTAssertTrue(try store.conversation(contactID: unpersisted.id).isEmpty)
  }
}
