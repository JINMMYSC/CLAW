import XCTest
@testable import HamsterKit

final class ClawSecretaryTaskApprovalTests: XCTestCase {
  private var root: URL!
  private var store: ClawMemoryStore!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-secretary-approval-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
  }

  override func tearDownWithError() throws {
    store = nil
    try? FileManager.default.removeItem(at: root)
  }

  func testAssistantConversationDoesNotSilentlyPersistExtractedTask() throws {
    let message = ClawConversationMessage(
      contactID: UUID(),
      speaker: .me,
      content: "我明天把方案发给你",
      sourceType: "claw-assistant"
    )
    XCTAssertEqual(ClawSecretaryExtractor.shared.extractTasks(from: message).count, 1)
    ClawSecretaryExtractor.shared.persistExtractedTasks(from: message, store: store)
    XCTAssertTrue(try store.tasks(status: nil).isEmpty,
                  "Ordinary AI chat must not create a persistent user task without approval")
  }
}
