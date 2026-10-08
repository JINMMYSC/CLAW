import XCTest
@testable import HamsterKit

final class MemoryMigrationV2Tests: XCTestCase {
  func testMigrationIsIdempotentAndPreservesIDsAndEvidence() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let memory = ClawMemoryItem(kind: .project, content: "CLAW", sourceType: "legacy")
    let message = ClawConversationMessage(
      contactID: UUID(),
      speaker: .other,
      content: "周五交方案",
      sourceType: "screenshot"
    )
    let task = ClawSecretaryTask(title: "交方案", sourceType: "extractor")
    try store.upsertMemory(memory)
    try store.appendConversation(message)
    try store.upsertTask(task)
    let migration = MemoryMigrationV2(store: store)

    let first = try migration.run()
    let second = try migration.run()

    XCTAssertEqual(first.totalV2Records, 3)
    XCTAssertEqual(second.totalV2Records, 3)
    XCTAssertEqual(try store.memoryV2VersionCount(id: memory.id), 1)
    XCTAssertEqual(try store.memoryV2VersionCount(id: message.id), 1)
    XCTAssertEqual(try store.memoryV2(id: task.id)?.type, .task)
    let migratedMessage = try XCTUnwrap(store.memoryV2(id: message.id))
    XCTAssertEqual(migratedMessage.personID, message.contactID)
    XCTAssertEqual(migratedMessage.evidence.map(\.rawEventID), [message.id])
    XCTAssertEqual(try store.rawEvents(ids: [message.id]).map(\.content), [message.content])
  }

  func testMigrationIncludesArchivedLegacyRows() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let archived = ClawMemoryItem(
      kind: .fact,
      content: "旧事实",
      sourceType: "legacy",
      status: .archived
    )
    try store.upsertMemory(archived)

    try MemoryMigrationV2(store: store).run()

    XCTAssertEqual(try store.memoryV2(id: archived.id)?.state, .archived)
  }
}
