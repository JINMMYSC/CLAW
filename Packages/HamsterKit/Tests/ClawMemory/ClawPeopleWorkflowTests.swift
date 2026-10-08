import XCTest
@testable import HamsterKit

final class ClawPeopleWorkflowTests: XCTestCase {
  private var root: URL!
  private var store: ClawMemoryStore!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("claw-people-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
  }

  override func tearDownWithError() throws {
    store = nil
    try? FileManager.default.removeItem(at: root)
  }

  func testReassignsDependentMemoryConversationAndTasks() throws {
    let source = UUID()
    let destination = UUID()
    try store.upsertMemory(ClawMemoryItem(
      kind: .relationship,
      scope: "contact",
      subjectID: source,
      content: "source memory",
      sourceType: "test"
    ))
    _ = try store.appendConversation(ClawConversationMessage(
      contactID: source,
      speaker: .other,
      content: "hello",
      occurredAt: Date(),
      sourceType: "test"
    ))
    _ = try store.upsertTask(ClawSecretaryTask(title: "follow up", contactID: source, sourceType: "test"))

    try store.reassignContactReferences(from: source, to: destination)

    XCTAssertEqual(try store.memories(scope: "contact", subjectID: destination).map(\.content), ["source memory"])
    XCTAssertEqual(try store.conversation(contactID: destination).map(\.content), ["hello"])
    XCTAssertEqual(try store.tasks().compactMap(\.contactID), [destination])
  }

  func testDeletingProfileCannotSilentlyPromotePrivateRecordsToGlobal() throws {
    let source = UUID()
    try store.upsertMemory(ClawMemoryItem(
      kind: .fact,
      scope: "contact",
      subjectID: source,
      content: "preserved",
      sourceType: "test"
    ))
    _ = try store.upsertTask(ClawSecretaryTask(title: "preserved task", contactID: source, sourceType: "test"))

    XCTAssertThrowsError(try store.reassignContactReferences(from: source, to: nil))
    XCTAssertTrue(try store.memories(scope: "global").isEmpty)
    XCTAssertEqual(try store.memories(scope: "contact", subjectID: source).map(\.content), ["preserved"])
    XCTAssertEqual(try store.tasks().first?.contactID, source)
  }

  func testContactDeletionGateRetainsPersonScopedData() throws {
    let person = UUID()
    XCTAssertFalse(try store.hasContactReferences(id: person))
    try store.upsertMemory(ClawMemoryItem(
      kind: .relationship,
      scope: "contact",
      subjectID: person,
      content: "仅属于此人的保密记忆",
      sourceType: "test"
    ))
    XCTAssertTrue(try store.hasContactReferences(id: person))
    XCTAssertTrue(try store.memories(scope: "global").isEmpty)
    XCTAssertEqual(
      try store.memories(scope: "contact", subjectID: person).map(\.content),
      ["仅属于此人的保密记忆"]
    )
  }

  func testMergePreservesDestinationAndAddsSourceIdentity() {
    let source = HeartTargetProfile(
      name: "Alice",
      bio: "source bio",
      relationship: "朋友",
      aliases: ["A"],
      lastSeenAt: Date(timeIntervalSince1970: 20)
    )
    let destination = HeartTargetProfile(
      name: "艾丽丝",
      bio: "destination bio",
      aliases: ["A"],
      lastSeenAt: Date(timeIntervalSince1970: 10)
    )

    let merged = ClawPeopleWorkflowService.mergedProfile(source: source, destination: destination)

    XCTAssertEqual(merged.id, destination.id)
    XCTAssertEqual(merged.relationship, "朋友")
    XCTAssertEqual(merged.aliases, ["A", "Alice"])
    XCTAssertEqual(merged.lastSeenAt, source.lastSeenAt)
    XCTAssertTrue(merged.bio.contains("source bio"))
    XCTAssertTrue(merged.bio.contains("destination bio"))
  }
}
