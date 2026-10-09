import XCTest
@testable import HamsterKit

final class MemoryRouterTests: XCTestCase {
  private var root: URL!
  private var store: ClawMemoryStore!
  private var sdk: DefaultMemorySDK!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("memory-router-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    sdk = DefaultMemorySDK(store: store)
  }

  override func tearDownWithError() throws {
    sdk = nil
    store = nil
    try? FileManager.default.removeItem(at: root)
  }

  func testGlobalRecallNeverLeaksPersonMemory() throws {
    let personID = UUID()
    try sdk.remember(record("全局偏好：简短回复", scope: .global))
    try sdk.remember(record("小王的私人偏好：喝茶", scope: .person, personID: personID))

    let result = try MemoryRouter(store: store).recall(
      MemoryRecallRequest(query: "偏好", scope: .global)
    )

    XCTAssertEqual(result.map(\.content), ["全局偏好：简短回复"])
  }

  func testPersonRecallIncludesGlobalAndSelectedPersonButDeduplicatesByNormalizedKey() throws {
    let selected = UUID()
    let unrelated = UUID()
    try sdk.remember(record("默认简短回复", scope: .global))
    try sdk.remember(record("小王喜欢喝茶", scope: .person, personID: selected, key: "drink-tea"))
    try sdk.remember(record("小王爱喝茶", scope: .person, personID: selected, key: "drink-tea"))
    try sdk.remember(record("小李喜欢咖啡", scope: .person, personID: unrelated))

    let result = try MemoryRouter(store: store).recall(
      MemoryRecallRequest(query: "喝", personID: selected, scope: .person, limit: 10)
    )

    XCTAssertTrue(result.contains(where: { $0.content == "默认简短回复" }))
    XCTAssertEqual(result.filter { $0.normalizedKey == "drink-tea" }.count, 1)
    XCTAssertFalse(result.contains(where: { $0.personID == unrelated }))
  }

  func testFTSFindsMatchingContentAndHonorsLimit() throws {
    try sdk.remember(record("周五提交项目方案", scope: .global))
    try sdk.remember(record("周六购买咖啡豆", scope: .global))

    let result = try MemoryRouter(store: store).recall(
      MemoryRecallRequest(query: "项目", scope: .global, limit: 1)
    )

    XCTAssertEqual(result.map(\.content), ["周五提交项目方案"])
  }

  func testOldUnspacedChineseMemoryIsFoundBeyondRecentWindow() throws {
    let historical = record("特别罕见的独特方案需要周五提交", scope: .global)
    try sdk.remember(historical)
    for index in 0..<125 {
      try sdk.remember(record("最近的普通记录第\(index)条", scope: .global))
    }
    let found = try MemoryRouter(store: store).recall(
      MemoryRecallRequest(query: "独特方案", scope: .global, limit: 10)
    )
    XCTAssertTrue(found.contains(where: { $0.id == historical.id }),
                  "Chinese substring lookup must not be limited to recent V2 records")
  }


  func testOtherPeopleCannotDisplaceOlderSelectedPersonBeforeCandidateLimit() throws {
    let selected = UUID()
    let target = try saveRetrievalFixture("selected historical", personID: selected, timestamp: 1_000)
    try addRetrievalNoise(personID: UUID())
    let found = try recallFixture(query: "", personID: selected)
    XCTAssertEqual(found.map(\.id), [target.id])
  }

  func testInactiveRecordsCannotDisplaceOlderActiveRecordBeforeCandidateLimit() throws {
    let target = try saveRetrievalFixture("active historical", timestamp: 1_000)
    for state in [MemoryState.candidate, .archived, .invalidated] {
      try addRetrievalNoise(state: state)
    }
    XCTAssertEqual(try recallFixture(query: "").map(\.id), [target.id])
  }

  func testExpiredRecordsCannotDisplaceOlderUnexpiredRecordBeforeCandidateLimit() throws {
    let target = try saveRetrievalFixture("unexpired historical", timestamp: 1_000)
    try addRetrievalNoise(expiresAt: Date(timeIntervalSince1970: 1))
    XCTAssertEqual(try recallFixture(query: "").map(\.id), [target.id])
  }

  func testPersonOwnedGlobalRowsNeverEnterGlobalRecall() throws {
    _ = try saveRetrievalFixture("owned global", personID: UUID(), scope: .global, timestamp: 1_000)
    XCTAssertTrue(try recallFixture(query: "").isEmpty)
  }

  func testProjectOwnedGlobalRowsNeverEnterUnscopedRecall() throws {
    _ = try saveRetrievalFixture("project global", projectID: UUID(), timestamp: 1_000)
    XCTAssertTrue(try recallFixture(query: "").isEmpty)
  }

  func testFTSFiltersPersonBeforeCandidateLimit() throws {
    let selected = UUID()
    let target = try saveRetrievalFixture(
      "alpha " + Array(repeating: "padding", count: 200).joined(separator: " "),
      personID: selected, timestamp: 1_000
    )
    try addRetrievalNoise(personID: UUID(), prefix: "alpha")
    XCTAssertEqual(try recallFixture(query: "alpha", personID: selected).map(\.id), [target.id])
  }

  func testChineseSubstringFallbackFiltersPersonBeforeCandidateLimit() throws {
    let selected = UUID()
    let target = try saveRetrievalFixture("历史记录包含独特方案需要讨论", personID: selected, timestamp: 1_000)
    try addRetrievalNoise(personID: UUID(), prefix: "新记录包含独特方案需要讨论")
    XCTAssertEqual(try recallFixture(query: "独特方案", personID: selected).map(\.id), [target.id])
  }

  func testPunctuationOnlyQueryUsesScopedRecentFallback() throws {
    let selected = UUID()
    let target = try saveRetrievalFixture("selected historical", personID: selected, timestamp: 1_000)
    try addRetrievalNoise(personID: UUID())
    XCTAssertEqual(try recallFixture(query: "...", personID: selected).map(\.id), [target.id])
  }

  @discardableResult
  private func saveRetrievalFixture(
    _ content: String,
    personID: UUID? = nil,
    projectID: UUID? = nil,
    scope: MemoryScope? = nil,
    state: MemoryState = .active,
    expiresAt: Date? = nil,
    timestamp: TimeInterval
  ) throws -> MemoryV2Record {
    var item = record(content, scope: scope ?? (personID == nil ? .global : .person), personID: personID)
    item.projectID = projectID
    item.state = state
    item.expiresAt = expiresAt
    item.updatedAt = Date(timeIntervalSince1970: timestamp)
    try sdk.remember(item)
    return item
  }

  private func addRetrievalNoise(
    personID: UUID? = nil,
    state: MemoryState = .active,
    expiresAt: Date? = nil,
    prefix: String = "new unrelated"
  ) throws {
    for index in 0..<100 {
      try saveRetrievalFixture(
        "\(prefix) \(state.rawValue) \(index)", personID: personID,
        state: state, expiresAt: expiresAt, timestamp: 2_000 + Double(index)
      )
    }
  }

  private func recallFixture(query: String, personID: UUID? = nil) throws -> [MemoryV2Record] {
    try MemoryRouter(store: store).recall(
      MemoryRecallRequest(query: query, personID: personID, scope: personID == nil ? .global : .person, limit: 1)
    )
  }

  private func record(
    _ content: String,
    scope: MemoryScope,
    personID: UUID? = nil,
    key: String? = nil
  ) -> MemoryV2Record {
    MemoryV2Record(
      type: .semantic,
      state: .active,
      scope: scope,
      content: content,
      normalizedKey: key,
      personID: personID,
      provenance: MemoryProvenance(originType: .userExplicit, ingestionMethod: "test")
    )
  }
}
