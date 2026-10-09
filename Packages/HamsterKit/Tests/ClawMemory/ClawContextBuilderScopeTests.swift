import XCTest
@testable import HamsterKit

final class ClawContextBuilderScopeTests: XCTestCase {
  private var root: URL!
  private var store: ClawMemoryStore!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-scope-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
  }

  override func tearDownWithError() throws {
    store = nil
    try? FileManager.default.removeItem(at: root)
  }

  func testGlobalQueryInjectsOnlyTheUniquelyNamedPersonsContext() throws {
    let alice = HeartTargetProfile(name: "小王", aliases: ["Alice"])
    let bob = HeartTargetProfile(name: "老张", aliases: ["Bob"])
    try seedPerson(alice, memory: "答应小王周五交付方案", task: "给小王发方案")
    try seedPerson(bob, memory: "老张喜欢电话沟通", task: "给老张回电话")
    try store.upsertTask(ClawSecretaryTask(title: "全局事项", sourceType: "test"))

    let pack = builder(profiles: [alice, bob]).build(
      contactID: nil,
      query: "我答应过小王什么？"
    )

    XCTAssertEqual(pack.resolvedContactID, alice.id)
    XCTAssertEqual(pack.contactDisplayName, "小王")
    XCTAssertEqual(pack.contactMemories.map(\.subjectID), [alice.id])
    XCTAssertTrue(pack.openTasks.contains(where: { $0.title == "给小王发方案" }))
    XCTAssertTrue(pack.openTasks.contains(where: { $0.title == "全局事项" }))
    XCTAssertFalse(pack.openTasks.contains(where: { $0.title == "给老张回电话" }))
    XCTAssertTrue(pack.promptBlock().contains("小王相关记忆"))
  }

  func testAmbiguousAliasDoesNotInjectEitherPersonsMemory() throws {
    let first = HeartTargetProfile(name: "王一", aliases: ["小王"])
    let second = HeartTargetProfile(name: "王二", aliases: ["小王"])
    try seedPerson(first, memory: "第一人的私事")
    try seedPerson(second, memory: "第二人的私事")

    let pack = builder(profiles: [first, second]).build(contactID: nil, query: "小王最近怎么样")

    XCTAssertNil(pack.resolvedContactID)
    XCTAssertTrue(pack.contactMemories.isEmpty)
    XCTAssertTrue(pack.recentConversation.isEmpty)
  }

  func testRelationshipWordsAloneNeverSelectAPerson() {
    let profiles = [
      HeartTargetProfile(name: "王一", relationship: "客户"),
      HeartTargetProfile(name: "王二", relationship: "客户"),
    ]
    XCTAssertNil(ClawQueryPersonResolver().resolve(query: "最近哪个客户要跟进？", profiles: profiles))
  }

  func testInvalidatedV2CannotReappearThroughActiveLegacyProjection() throws {
    let person = HeartTargetProfile(name: "旧记忆测试")
    let sdk = DefaultMemorySDK(store: store)
    let record = MemoryV2Record(
      type: .preference, state: .active, scope: .person,
      content: "已过期的私人偏好", personID: person.id,
      provenance: MemoryProvenance(originType: .userExplicit, ingestionMethod: "test")
    )
    try sdk.remember(record)
    XCTAssertTrue(try sdk.contextualMemories(scope: "contact", personID: person.id)
      .contains { $0.id == record.id })
    var invalidated = record
    invalidated.state = .invalidated
    invalidated.version += 1
    try store.saveMemoryV2(invalidated)
    XCTAssertFalse(try sdk.contextualMemories(scope: "contact", personID: person.id)
      .contains { $0.id == record.id })
  }

  func testOlderPersonMemoryRemainsVisibleAmongManyOtherPeople() throws {
    let alice = HeartTargetProfile(name: "艾丽")
    let bob = HeartTargetProfile(name: "贝贝")
    let sdk = DefaultMemorySDK(store: store)
    try sdk.remember(MemoryV2Record(
      type: .preference, state: .active, scope: .person,
      content: "艾丽的旧交流偏好", personID: alice.id,
      provenance: MemoryProvenance(originType: .userExplicit, ingestionMethod: "test")
    ))
    for i in 0..<125 {
      try sdk.remember(MemoryV2Record(
        type: .preference, state: .active, scope: .person,
        content: "贝贝第\(i)条较新的交流偏好", personID: bob.id,
        provenance: MemoryProvenance(originType: .userExplicit, ingestionMethod: "test")
      ))
    }
    let pack = builder(profiles: [alice, bob]).build(contactID: alice.id)
    XCTAssertTrue(pack.contactMemories.contains { $0.content == "艾丽的旧交流偏好" })
    XCTAssertFalse(pack.contactMemories.contains { $0.subjectID == bob.id })
  }

  func testSDKContextReadsV2AndLegacyWithoutCrossPersonLeak() throws {
    let alice = HeartTargetProfile(name: "艾丽")
    let bob = HeartTargetProfile(name: "贝贝")
    let sdk = DefaultMemorySDK(store: store)
    try sdk.remember(MemoryV2Record(
      type: .preference, state: .confirmed, scope: .person,
      content: "艾丽喜欢简短回复", personID: alice.id,
      provenance: MemoryProvenance(originType: .userExplicit, ingestionMethod: "test")
    ))
    try sdk.remember(MemoryV2Record(
      type: .preference, state: .active, scope: .person,
      content: "贝贝习惯电话沟通", personID: bob.id,
      provenance: MemoryProvenance(originType: .userExplicit, ingestionMethod: "test")
    ))
    try seedPerson(alice, memory: "艾丽的旧版记忆")
    let alicePack = builder(profiles: [alice, bob]).build(contactID: alice.id)
    XCTAssertTrue(alicePack.contactMemories.contains { $0.content == "艾丽喜欢简短回复" })
    XCTAssertTrue(alicePack.contactMemories.contains { $0.content == "艾丽的旧版记忆" })
    XCTAssertFalse(alicePack.contactMemories.contains { $0.content == "贝贝习惯电话沟通" })
    let globalPack = builder(profiles: [alice, bob]).build(contactID: nil, query: "今天做什么")
    XCTAssertTrue(globalPack.contactMemories.isEmpty)
    XCTAssertFalse(globalPack.globalMemories.contains { $0.content == "艾丽喜欢简短回复" })
  }

  func testExplicitContactOverridesANameInTheQuery() throws {
    let selected = HeartTargetProfile(name: "当前对象")
    let mentioned = HeartTargetProfile(name: "另一个人")
    try seedPerson(selected, memory: "当前对象的记忆")
    try seedPerson(mentioned, memory: "另一个人的记忆")

    let pack = builder(profiles: [selected, mentioned]).build(
      contactID: selected.id,
      query: "另一个人说过什么"
    )

    XCTAssertEqual(pack.resolvedContactID, selected.id)
    XCTAssertEqual(pack.contactMemories.map(\.subjectID), [selected.id])
  }

  private func builder(profiles: [HeartTargetProfile]) -> ClawContextBuilder {
    ClawContextBuilder(store: store, profilesProvider: { profiles })
  }

  private func seedPerson(
    _ profile: HeartTargetProfile,
    memory: String,
    task: String? = nil
  ) throws {
    try store.upsertMemory(ClawMemoryItem(
      kind: .relationship,
      scope: "contact",
      subjectID: profile.id,
      content: memory,
      sourceType: "test"
    ))
    if let task {
      try store.upsertTask(ClawSecretaryTask(title: task, contactID: profile.id, sourceType: "test"))
    }
  }
}
