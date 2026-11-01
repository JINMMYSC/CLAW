import Foundation
import XCTest
@testable import HamsterKit

final class ClawScreenshotConfirmedProfilePrivacyTests: XCTestCase {
  private func makeStore() -> (ClawMemoryStore, URL) {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-confirmed-profile-\(UUID().uuidString)")
    return (ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite")), root)
  }

  func testAutoCreatedContactCannotAuthorizeScreenshotImport() throws {
    let (store, root) = makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let unconfirmed = HeartTargetProfile(name: "Unconfirmed fixture", autoCreated: true)
    let service = ClawScreenshotIngestionService(
      store: store, profileLookup: { $0 == unconfirmed.id ? unconfirmed : nil }
    )
    let message = ClawConversationMessage(
      contactID: unconfirmed.id, speaker: .other,
      content: "Private fixture", sourceType: "screenshot"
    )
    XCTAssertThrowsError(try service.confirmReviewed(messages: [message], for: unconfirmed))
    XCTAssertTrue(try store.conversation(contactID: unconfirmed.id).isEmpty)
  }

  func testGroupContactCannotAuthorizeIndividualScreenshotImport() throws {
    let (store, root) = makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let group = HeartTargetProfile(name: "Group fixture", isGroup: true)
    let service = ClawScreenshotIngestionService(
      store: store, profileLookup: { $0 == group.id ? group : nil }
    )
    let message = ClawConversationMessage(
      contactID: group.id, speaker: .other,
      content: "Private group fixture", sourceType: "screenshot"
    )
    XCTAssertThrowsError(try service.confirmReviewed(messages: [message], for: group))
    XCTAssertTrue(try store.conversation(contactID: group.id).isEmpty)
  }

  func testChangedAvatarFingerprintInvalidatesStaleScreenshotReview() throws {
    let (store, root) = makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let snapshot = HeartTargetProfile(
      name: "Confirmed person", avatarFingerprint: "avatar-original"
    )
    var current = snapshot
    current.avatarFingerprint = "avatar-replaced"
    // A stale external snapshot may retain the same timestamp. Identity
    // changes must be checked independently of updatedAt.
    XCTAssertEqual(current.updatedAt, snapshot.updatedAt)
    let service = ClawScreenshotIngestionService(
      store: store, profileLookup: { $0 == snapshot.id ? current : nil }
    )
    let message = ClawConversationMessage(
      contactID: snapshot.id, speaker: .other,
      content: "Private avatar evidence", sourceType: "screenshot"
    )
    XCTAssertThrowsError(try service.confirmReviewed(messages: [message], for: snapshot))
    XCTAssertTrue(try store.conversation(contactID: snapshot.id).isEmpty)
  }

  func testChangedAliasesInvalidateStaleScreenshotReview() throws {
    let (store, root) = makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let snapshot = HeartTargetProfile(
      name: "Confirmed person", aliases: ["old-chat-title"]
    )
    var current = snapshot
    current.aliases = ["different-person-title"]
    XCTAssertEqual(current.updatedAt, snapshot.updatedAt)
    let service = ClawScreenshotIngestionService(
      store: store, profileLookup: { $0 == snapshot.id ? current : nil }
    )
    let message = ClawConversationMessage(
      contactID: snapshot.id, speaker: .other,
      content: "Private alias evidence", sourceType: "screenshot"
    )
    XCTAssertThrowsError(try service.confirmReviewed(messages: [message], for: snapshot))
    XCTAssertTrue(try store.conversation(contactID: snapshot.id).isEmpty)
  }

  func testExplicitlyConfirmedIndividualStillImportsReviewedScreenshot() throws {
    let (store, root) = makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let person = HeartTargetProfile(name: "Confirmed fixture")
    let service = ClawScreenshotIngestionService(
      store: store, profileLookup: { $0 == person.id ? person : nil }
    )
    let message = ClawConversationMessage(
      contactID: person.id, speaker: .other,
      content: "Reviewed fixture", sourceType: "screenshot"
    )
    XCTAssertEqual(try service.confirmReviewed(messages: [message], for: person), 1)
    XCTAssertEqual(try store.conversation(contactID: person.id).count, 1)
  }
}
