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
