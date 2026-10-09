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

  func testContactDeletionGateAlsoProtectsStandingIntents() throws {
    let person = UUID()
    XCTAssertFalse(try store.hasContactReferences(id: person))
    let intent = StandingIntent(
      trigger: "下次联系", personID: person,
      context: "项目群", condition: "再次聊天",
      action: "提醒完成报价",
      provenance: MemoryProvenance(originType: .userExplicit, ingestionMethod: "test")
    )
    try store.saveStandingIntent(intent)
    XCTAssertTrue(try store.hasContactReferences(id: person),
                  "A standing intent must prevent unsafe person deletion")
  }

  func testPurgePersonRemovesLocalLineageButLeavesOtherPersonIntact() throws {
    let person = UUID(), other = UUID()
    let sdk = DefaultMemorySDK(store: store)
    let event = RawMemoryEvent(kind: "chat", content: "第一人的私密证据")
    let evidence = MemoryEvidence(rawEventID: event.id, excerpt: event.content)
    let record = MemoryV2Record(type: .preference, state: .active, scope: .person,
      content: "第一人的私人喜好", personID: person,
      provenance: .init(originType: .userExplicit, ingestionMethod: "test"),
      evidence: [evidence])
    try store.saveMemoryV2(record, rawEvents: [event])
    let otherRecord = MemoryV2Record(type: .preference, state: .active, scope: .person,
      content: "另一个人的私人喜好", personID: other,
      provenance: .init(originType: .userExplicit, ingestionMethod: "test"))
    try sdk.remember(otherRecord)
    try store.appendConversation(ClawConversationMessage(contactID: person,
      speaker: .other, content: "私密聊天", sourceType: "test"))
    try store.upsertTask(ClawSecretaryTask(title: "私密事项",
      contactID: person, sourceType: "test"))
    try store.saveStandingIntent(StandingIntent(trigger: "记住", personID: person,
      context: "测试", condition: "下次", action: "联系",
      provenance: .init(originType: .userExplicit, ingestionMethod: "test")))

    XCTAssertTrue(try store.hasContactReferences(id: person))
    try store.purgePersonLocalRecords(id: person)
    XCTAssertFalse(try store.hasContactReferences(id: person))
    XCTAssertNil(try store.memoryV2(id: record.id))
    XCTAssertEqual(try store.memoryV2VersionCount(id: record.id), 0)
    XCTAssertTrue(try store.rawEvents(ids: [event.id]).isEmpty)
    XCTAssertTrue(try store.conversation(contactID: person).isEmpty)
    XCTAssertTrue(try store.tasks().filter { $0.contactID == person }.isEmpty)
    XCTAssertTrue(try store.standingIntents().filter { $0.personID == person }.isEmpty)
    XCTAssertEqual(try store.memoryV2(id: otherRecord.id)?.content, "另一个人的私人喜好")
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
