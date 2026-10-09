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

  func testOtherPeopleCannotDisplaceOldSelectedMemoryBeforeCandidateLimit() throws {
    let selected = UUID(), other = UUID()
    let wanted = record("只有选中人物的历史偏好", scope: .person, personID: selected)
    try sdk.remember(wanted)
    for index in 0..<110 {
      try sdk.remember(record("其他人的偏好记录\(index)", scope: .person, personID: other))
    }
    let result = try MemoryRouter(store: store).recall(
      MemoryRecallRequest(query: "历史偏好", personID: selected, scope: .person, limit: 1)
    )
    XCTAssertEqual(result.first?.id, wanted.id)
  }

  func testExpiredAndInactiveCannotDisplaceOlderActiveMemory() throws {
    let selected = UUID()
    let wanted = record("长久有效的聊天习惯", scope: .person, personID: selected)
    try sdk.remember(wanted)
    for index in 0..<95 {
      var invalid = record("过期聊天习惯\(index)", scope: .person, personID: selected)
      invalid.state = index.isMultiple(of: 2) ? .candidate : .active
      invalid.expiresAt = Date().addingTimeInterval(-100)
      try sdk.remember(invalid)
    }
    let result = try MemoryRouter(store: store).recall(
      MemoryRecallRequest(query: "聊天习惯", personID: selected, scope: .person, limit: 1)
    )
    XCTAssertEqual(result.first?.id, wanted.id)
  }

  func testCloudDeniedRowsCannotDisplaceOlderAllowedContext() throws {
    let wanted = record("可以分享的个人交流偏好", scope: .global)
    try sdk.remember(wanted)
    for index in 0..<100 {
      var denied = record("本地机密偏好\(index)", scope: .global)
      denied.cloudPermission = .neverSend
      try sdk.remember(denied)
    }
    let context = try sdk.context(MemoryContextRequest(
      recall: MemoryRecallRequest(query: "交流偏好", scope: .global, limit: 1)
    ))
    XCTAssertEqual(context.records.first?.id, wanted.id)
  }

  func testOwnerTaggedGlobalRecordNeverEntersUnscopedRecall() throws {
    let personID = UUID()
    let wanted = record("无归属全局信息", scope: .global)
    try sdk.remember(wanted)
    var owned = record("有归属的全局信息", scope: .global)
    owned.personID = personID
    try sdk.remember(owned)
    let global = try MemoryRouter(store: store).recall(
      MemoryRecallRequest(query: "信息", scope: .global, limit: 10)
    )
    XCTAssertEqual(global.map(\.id), [wanted.id])
  }


  func testRecencyUsesProvidedClockAndCapsFutureDates() {
    let now = Date(timeIntervalSince1970: 2_100_000_000)
    let day: TimeInterval = 86_400
    XCTAssertEqual(MemoryRouter.recencyFactor(updatedAt: now, now: now), 1, accuracy: 0.00001)
    XCTAssertEqual(MemoryRouter.recencyFactor(updatedAt: now.addingTimeInterval(365 * day), now: now), 1, accuracy: 0.00001)
    XCTAssertEqual(MemoryRouter.recencyFactor(updatedAt: now.addingTimeInterval(-90 * day), now: now), 0.5, accuracy: 0.00001)
    XCTAssertEqual(MemoryRouter.recencyFactor(updatedAt: now.addingTimeInterval(-365 * day), now: now), 0, accuracy: 0.00001)
  }

  func testRecallRanksAgainstInjectedClockRatherThanWallClock() throws {
    let now = Date(timeIntervalSince1970: 2_100_000_000)
    let day: TimeInterval = 86_400
    var oldImportant = record("优先级高的历史记录", scope: .global)
    oldImportant.updatedAt = now.addingTimeInterval(-400 * day)
    oldImportant.importance = 0.95
    var recentLowPriority = record("优先级低的近期记录", scope: .global)
    recentLowPriority.updatedAt = now.addingTimeInterval(-10 * day)
    recentLowPriority.importance = 0.55
    try sdk.remember(oldImportant)
    try sdk.remember(recentLowPriority)

    let result = try MemoryRouter(store: store).recall(
      MemoryRecallRequest(query: "", scope: .global, limit: 1), now: now
    )
    XCTAssertEqual(result.first?.id, oldImportant.id)
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
