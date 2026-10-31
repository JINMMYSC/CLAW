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
  func testRenamedSnapshotCannotWriteToCurrentContact() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-screenshot-renamed-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let stale = HeartTargetProfile(name: "Before")
    var current = stale
    current.name = "After"
    current.updatedAt = stale.updatedAt.addingTimeInterval(10)
    let service = ClawScreenshotIngestionService(store: store, profileLookup: { id in
      id == current.id ? current : nil
    })
    let message = ClawConversationMessage(
      contactID: stale.id, speaker: .other, content: "Fixture",
      sourceType: "screenshot"
    )
    XCTAssertThrowsError(try service.confirmReviewed(messages: [message], for: stale))
    XCTAssertTrue(try store.conversation(contactID: stale.id).isEmpty)
  }

  func testCurrentIndividualCanImportWithoutCreatingTasks() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-screenshot-current-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let person = HeartTargetProfile(name: "Confirmed Fixture")
    let service = ClawScreenshotIngestionService(store: store, profileLookup: { id in
      id == person.id ? person : nil
    })
    let message = ClawConversationMessage(
      contactID: person.id, speaker: .other, content: "Fixture",
      sourceType: "screenshot"
    )
    XCTAssertEqual(try service.confirmReviewed(messages: [message], for: person), 1)
    XCTAssertEqual(try store.conversation(contactID: person.id).count, 1)
    XCTAssertTrue(try store.tasks().isEmpty)
  }

  func testGroupSnapshotCannotBeUsedAsIndividualImportAuthority() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-screenshot-group-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let group = HeartTargetProfile(name: "Group Fixture", isGroup: true)
    let service = ClawScreenshotIngestionService(store: store, profileLookup: { id in
      id == group.id ? group : nil
    })
    let message = ClawConversationMessage(
      contactID: group.id, speaker: .other, content: "Fixture",
      sourceType: "screenshot"
    )
    XCTAssertThrowsError(try service.confirmReviewed(messages: [message], for: group))
    XCTAssertTrue(try store.conversation(contactID: group.id).isEmpty)
  }
}
