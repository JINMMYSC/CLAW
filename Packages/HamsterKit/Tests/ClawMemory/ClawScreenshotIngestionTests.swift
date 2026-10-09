import XCTest
@testable import HamsterKit

final class ClawScreenshotIngestionTests: XCTestCase {
  func testUnknownScreenshotTitleRequiresReviewWithoutCreatingOrSelectingPerson() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot-ingest-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let title = "待确认联系人\(UUID().uuidString.prefix(8))"
    let beforeIDs = Set(HeartTargetService.shared.profiles.map(\.id))
    let beforeSelection = HeartTargetService.shared.selectedProfile?.id
    let lines = [
      VisionOCRService.OCRLine(text: title, boundingBox: .init(x: 0.35, y: 0.9, width: 0.3, height: 0.04), confidence: 0.99),
      VisionOCRService.OCRLine(text: "明天下午提交设计", boundingBox: .init(x: 0.1, y: 0.5, width: 0.3, height: 0.04), confidence: 0.99),
    ]

    let result = try ClawScreenshotIngestionService(store: store).ingest(lines: lines, selectedProfile: nil, sourceRef: "test")

    XCTAssertTrue(result.requiresReview)
    XCTAssertNil(result.profile, "An unknown title must not be silently converted to a new person")
    XCTAssertEqual(Set(HeartTargetService.shared.profiles.map(\.id)), beforeIDs)
    XCTAssertEqual(HeartTargetService.shared.selectedProfile?.id, beforeSelection)
    XCTAssertTrue(try store.conversation(contactID: nil, limit: 10).isEmpty)
    XCTAssertTrue(try store.tasks(status: .open, limit: 10).isEmpty)
  }

  func testExplicitReviewRequiresApprovalAndDeduplicatesRepeatedScreenshots() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot-review-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let profile = HeartTargetProfile(name: "审核联系人")
    let lines = [
      VisionOCRService.OCRLine(text: "审核联系人", boundingBox: .init(x: 0.35, y: 0.9, width: 0.3, height: 0.04), confidence: 0.99),
      VisionOCRService.OCRLine(text: "明天下午提交设计", boundingBox: .init(x: 0.1, y: 0.5, width: 0.3, height: 0.04), confidence: 0.99),
    ]
    let service = ClawScreenshotIngestionService(store: store)
    let preview = try service.ingest(lines: lines, selectedProfile: profile, sourceRef: "test", requireUserReview: true)
    XCTAssertTrue(preview.requiresReview)
    XCTAssertEqual(try store.conversation(contactID: profile.id).count, 0)
    XCTAssertTrue(try store.tasks(status: .open).isEmpty)
    XCTAssertFalse(preview.messages.isEmpty)
    var confirmed = preview.messages
    for index in confirmed.indices {
      confirmed[index].speaker = .other
    }
    let first = try service.confirmReviewed(messages: confirmed, for: profile)
    XCTAssertEqual(first, confirmed.count)
    XCTAssertEqual(try store.conversation(contactID: profile.id).count, confirmed.count)
    let second = try service.confirmReviewed(messages: confirmed, for: profile)
    XCTAssertEqual(second, 0, "Reimporting an overlapping screenshot must not re-create derived records")
  }

  func testSameScreenshotReimportAtDifferentTimeIsIdempotent() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot-repeat-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let profile = HeartTargetProfile(name: "重复截图")
    let lines = [
      VisionOCRService.OCRLine(text: "重复截图", boundingBox: .init(x: 0.4, y: 0.9, width: 0.2, height: 0.04), confidence: 0.99),
      VisionOCRService.OCRLine(text: "周五提交方案", boundingBox: .init(x: 0.1, y: 0.5, width: 0.25, height: 0.04), confidence: 0.95)
    ]
    let service = ClawScreenshotIngestionService(store: store)
    let source = "screenshot-digest:fixture"
    let firstPreview = try service.ingest(lines: lines, selectedProfile: profile,
      capturedAt: Date(timeIntervalSince1970: 1000), sourceRef: source, requireUserReview: true)
    let secondPreview = try service.ingest(lines: lines, selectedProfile: profile,
      capturedAt: Date(timeIntervalSince1970: 7000), sourceRef: source, requireUserReview: true)
    var firstMessages = firstPreview.messages
    var secondMessages = secondPreview.messages
    for i in firstMessages.indices { firstMessages[i].speaker = .other }
    for i in secondMessages.indices { secondMessages[i].speaker = .other }
    XCTAssertEqual(try service.confirmReviewed(messages: firstMessages, for: profile), firstMessages.count)
    XCTAssertEqual(try service.confirmReviewed(messages: secondMessages, for: profile), 0)
    XCTAssertEqual(try store.conversation(contactID: profile.id).count, firstMessages.count)
  }

  func testDifferentScreenshotsOnlyDeduplicateLongExactOverlapForSamePerson() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("overlap-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let service = ClawScreenshotIngestionService(store: store)
    let person = HeartTargetProfile(name: "A")
    let longText = "这份完整的项目验收方案需要下周五之前交给客户确认"
    let a = ClawConversationMessage(contactID: person.id, speaker: .other,
      content: longText, sourceType: "screenshot", sourceRef: "screenshot-digest:a")
    let b = ClawConversationMessage(contactID: person.id, speaker: .other,
      content: longText, occurredAt: a.occurredAt.addingTimeInterval(3600),
      sourceType: "screenshot", sourceRef: "screenshot-digest:b")
    XCTAssertEqual(try service.confirmReviewed(messages: [a], for: person), 1)
    XCTAssertEqual(try service.confirmReviewed(messages: [b], for: person), 0)
    XCTAssertEqual(try store.conversation(contactID: person.id).count, 1)

    let short1 = ClawConversationMessage(contactID: person.id, speaker: .other,
      content: "好的", sourceType: "screenshot", sourceRef: "screenshot-digest:c")
    let short2 = ClawConversationMessage(contactID: person.id, speaker: .other,
      content: "好的", sourceType: "screenshot", sourceRef: "screenshot-digest:d")
    XCTAssertEqual(try service.confirmReviewed(messages: [short1], for: person), 1)
    XCTAssertEqual(try service.confirmReviewed(messages: [short2], for: person), 1)
    XCTAssertEqual(try store.conversation(contactID: person.id).count, 3)

    let anotherPerson = HeartTargetProfile(name: "B")
    XCTAssertEqual(try service.confirmReviewed(messages: [b], for: anotherPerson), 1)
    XCTAssertEqual(try store.conversation(contactID: anotherPerson.id).count, 1)
  }

  func testAtomicImportRejectsUnconfirmedSpeakersWithoutPartialWrites() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("atomic-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let person = UUID()
    let approved = ClawConversationMessage(contactID: person, speaker: .other,
      content: "周五提交真实资料", sourceType: "screenshot")
    let invalid = ClawConversationMessage(contactID: person, speaker: .unknown,
      content: "未经确认", sourceType: "screenshot")
    XCTAssertThrowsError(try store.commitScreenshotImport([approved, invalid], personID: person))
    XCTAssertTrue(try store.conversation(contactID: person).isEmpty)
    XCTAssertTrue(try store.tasks().isEmpty)
    XCTAssertEqual(try store.memoryV2Count(), 0)
  }

  func testScreenshotUndoReceiptPreservesEarlierAndOtherPeopleImports() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("undo-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let service = ClawScreenshotIngestionService(store: store)
    let profile = HeartTargetProfile(name: "A")
    let other = HeartTargetProfile(name: "B")
    let old = ClawConversationMessage(contactID: profile.id, speaker: .other,
      content: "上一次导入", sourceType: "screenshot", sourceRef: "screenshot-digest:old")
    let fresh = ClawConversationMessage(contactID: profile.id, speaker: .other,
      content: "周五提交新的项目方案", sourceType: "screenshot", sourceRef: "screenshot-digest:new")
    let separate = ClawConversationMessage(contactID: other.id, speaker: .other,
      content: "其他人的信息", sourceType: "screenshot", sourceRef: "screenshot-digest:other")
    let first = try service.confirmReviewedWithReceipt(messages: [old], for: profile)
    _ = try service.confirmReviewedWithReceipt(messages: [separate], for: other)
    let receipt = try service.confirmReviewedWithReceipt(messages: [old,fresh], for: profile)
    XCTAssertEqual(receipt.messageIDs, [fresh.id])
    XCTAssertThrowsError(try service.undo(ClawScreenshotImportReceipt(
      personID: other.id, messageIDs: receipt.messageIDs)))
    XCTAssertEqual(try store.conversation(contactID: profile.id).count, 2)
    XCTAssertEqual(try service.undo(receipt), 1)
    XCTAssertEqual(try store.conversation(contactID: profile.id).map(\.id), [old.id])
    XCTAssertEqual(try store.conversation(contactID: other.id).map(\.id), [separate.id])
    XCTAssertEqual(try store.tasks().filter { $0.contactID == profile.id }.count, 0)
    XCTAssertEqual(first.messageIDs, [old.id])
  }

  func testReviewRejectsUnknownSpeakerWithoutWritingAnything() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot-review-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let profile = HeartTargetProfile(name: "待确认用户")
    let unknown = ClawConversationMessage(
      contactID: nil, speaker: .unknown, content: "今晚发方案", sourceType: "screenshot"
    )
    XCTAssertThrowsError(try ClawScreenshotIngestionService(store: store).confirmReviewed(messages: [unknown], for: profile))
    XCTAssertTrue(try store.conversation(contactID: profile.id).isEmpty)
  }

  func testLowConfidenceOrUnknownSpeakerRequiresReview() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot-ingest-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let lines = [
      VisionOCRService.OCRLine(text: "项目群", boundingBox: .init(x: 0.35, y: 0.9, width: 0.3, height: 0.04), confidence: 0.98),
      VisionOCRService.OCRLine(text: "周五交方案", boundingBox: .init(x: 0.44, y: 0.5, width: 0.12, height: 0.04), confidence: 0.55),
    ]

    let result = try ClawScreenshotIngestionService(store: store).ingest(lines: lines, selectedProfile: nil, sourceRef: "test")

    XCTAssertTrue(result.requiresReview)
    XCTAssertEqual(result.messages.count, 1)
    XCTAssertEqual(try store.conversation(contactID: result.profile?.id, limit: 10).count, 0)
  }

  func testHighConfidenceMessagesPersistAndCreateTasks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot-ingest-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let profile = HeartTargetProfile(name: "小王")
    let lines = [
      VisionOCRService.OCRLine(text: "小王", boundingBox: .init(x: 0.4, y: 0.9, width: 0.2, height: 0.04), confidence: 0.99),
      VisionOCRService.OCRLine(text: "周五提交方案", boundingBox: .init(x: 0.1, y: 0.5, width: 0.25, height: 0.04), confidence: 0.95),
    ]

    let result = try ClawScreenshotIngestionService(store: store).ingest(lines: lines, selectedProfile: profile, sourceRef: "test")

    XCTAssertFalse(result.requiresReview)
    XCTAssertEqual(try store.conversation(contactID: profile.id, limit: 10).count, 1)
    XCTAssertFalse(try store.tasks(status: .open, limit: 10).isEmpty)
  }
}
