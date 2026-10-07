import XCTest
@testable import HamsterKit

final class StandingIntentTests: XCTestCase {
  func testIntentMatchingExpirationAndCancellation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("standing-intent-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let memoryStore = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let store = StandingIntentStore(memoryStore: memoryStore)
    let personID = UUID()
    let active = intent(personID: personID, expiresAt: Date(timeIntervalSinceNow: 3600))
    let expired = intent(personID: personID, expiresAt: Date(timeIntervalSinceNow: -1))
    try store.save(active)
    try store.save(expired)

    XCTAssertEqual(
      try store.match(trigger: "下次联系", personID: personID, context: "项目群", now: Date()).map(\.id),
      [active.id]
    )
    try store.cancel(id: active.id)
    XCTAssertTrue(try store.match(trigger: "下次联系", personID: personID, context: "项目群").isEmpty)
  }

  func testFlushExtractsPromiseTaskAndPreferenceWithEvidence() {
    let sessionID = UUID()
    let personID = UUID()
    let messages = [
      ClawConversationMessage(contactID: personID, speaker: .me, content: "我答应周五交方案", sourceType: "chat"),
      ClawConversationMessage(contactID: personID, speaker: .other, content: "我喜欢简短回复", sourceType: "chat"),
    ]

    let result = MemoryFlushService().extract(sessionID: sessionID, messages: messages, personID: personID)

    XCTAssertFalse(result.tasks.isEmpty)
    XCTAssertTrue(result.records.contains(where: { $0.type == .preference }))
    XCTAssertTrue(result.records.allSatisfy { !$0.evidence.isEmpty && $0.sessionID == sessionID })
  }

  private func intent(personID: UUID, expiresAt: Date) -> StandingIntent {
    StandingIntent(
      trigger: "下次联系",
      personID: personID,
      context: "项目群",
      condition: "再次聊天",
      action: "提醒确认方案",
      expiresAt: expiresAt,
      provenance: MemoryProvenance(originType: .userExplicit, ingestionMethod: "test")
    )
  }
}
