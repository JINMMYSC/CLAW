import Foundation
import XCTest
@testable import HamsterKit

final class ClawScreenshotStalePreviewPrivacyTests: XCTestCase {
  func testDeletedSelectedContactCannotOwnNewOCRPreview() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-stale-preview-deleted-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let title = "已删除联系人\(UUID().uuidString.prefix(8))"
    let deleted = HeartTargetProfile(name: title)
    let service = ClawScreenshotIngestionService(store: store, profileLookup: { _ in nil })
    let lines = [
      VisionOCRService.OCRLine(text: title,
        boundingBox: .init(x: 0.35, y: 0.9, width: 0.3, height: 0.04), confidence: 0.99),
      VisionOCRService.OCRLine(text: "明天下午交稿",
        boundingBox: .init(x: 0.1, y: 0.5, width: 0.3, height: 0.04), confidence: 0.99),
    ]

    let preview = try service.ingest(lines: lines, selectedProfile: deleted, sourceRef: "test")
    XCTAssertTrue(preview.requiresReview)
    XCTAssertNil(preview.profile, "Deleted selection must not prefill a private OCR identity")
    XCTAssertTrue(preview.messages.allSatisfy { $0.contactID == nil })
    XCTAssertTrue(try store.conversation(contactID: deleted.id).isEmpty)
  }

  func testRenamedSelectedContactCannotOwnStaleOCRPreview() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-stale-preview-renamed-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let title = "旧联系人\(UUID().uuidString.prefix(8))"
    let old = HeartTargetProfile(name: title)
    var renamed = old
    renamed.name = "新联系人"
    let service = ClawScreenshotIngestionService(store: store, profileLookup: { id in
      id == old.id ? renamed : nil
    })
    let lines = [
      VisionOCRService.OCRLine(text: title,
        boundingBox: .init(x: 0.35, y: 0.9, width: 0.3, height: 0.04), confidence: 0.99),
      VisionOCRService.OCRLine(text: "周五见",
        boundingBox: .init(x: 0.1, y: 0.5, width: 0.3, height: 0.04), confidence: 0.99),
    ]

    let preview = try service.ingest(lines: lines, selectedProfile: old, sourceRef: "test")
    XCTAssertNil(preview.profile, "Renamed selection must require fresh manual identity confirmation")
    XCTAssertTrue(preview.messages.allSatisfy { $0.contactID == nil })
    XCTAssertTrue(try store.conversation(contactID: old.id).isEmpty)
  }
}
