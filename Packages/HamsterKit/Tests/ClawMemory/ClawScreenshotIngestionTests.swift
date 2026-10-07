import XCTest
@testable import HamsterKit

final class ClawScreenshotIngestionTests: XCTestCase {
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
