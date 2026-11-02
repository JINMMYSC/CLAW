import Foundation
import XCTest
@testable import HamsterKit

final class ClawSecretaryExplicitTaskConsentTests: XCTestCase {
  func testExtractedTasksAreSuggestionsNotAutomaticallyPersisted() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-task-consent-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClawMemoryStore(databaseURL: directory.appendingPathComponent("test.sqlite"))
    let message = ClawConversationMessage(
      contactID: nil,
      speaker: .me,
      content: "明天联系客户确认订单",
      sourceType: "claw-assistant"
    )
    let extractor = ClawSecretaryExtractor()
    XCTAssertFalse(extractor.extractTasks(from: message).isEmpty,
                   "The user may still preview suggested tasks")

    // No explicit user confirmation: the assistant must not create a task.
    extractor.persistExtractedTasks(from: message, store: store)
    XCTAssertTrue(try store.tasks(status: .open).isEmpty,
                  "Sending a chat message must not silently create a persistent task")
  }
}
