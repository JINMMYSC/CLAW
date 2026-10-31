import Foundation
import XCTest
@testable import HamsterKit

final class ClawScreenshotStaleProfilePrivacyTests: XCTestCase {
  func testDeletedContactSnapshotCannotImportReviewedScreenshot() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-screenshot-stale-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    // Never persist this fixture in the user's App Group contact profiles.
    let deletedSnapshot = HeartTargetProfile(name: "Temporary Fixture")
    let message = ClawConversationMessage(
      contactID: deletedSnapshot.id, speaker: .other,
      content: "Screenshot-only fixture", sourceType: "screenshot"
    )
    let service = ClawScreenshotIngestionService(store: store)

    XCTAssertThrowsError(
      try service.confirmReviewed(messages: [message], for: deletedSnapshot),
      "An unpersisted/deleted contact snapshot must not authorize an import"
    )
    XCTAssertTrue(try store.conversation(contactID: deletedSnapshot.id).isEmpty)
  }
}
