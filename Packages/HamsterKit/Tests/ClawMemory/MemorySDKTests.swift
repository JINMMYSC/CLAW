import XCTest
@testable import HamsterKit

final class MemorySDKTests: XCTestCase {
  private var root: URL!
  private var store: ClawMemoryStore!
  private var sdk: DefaultMemorySDK!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("memory-sdk-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    sdk = DefaultMemorySDK(store: store)
  }

  override func tearDownWithError() throws {
    sdk = nil
    store = nil
    try? FileManager.default.removeItem(at: root)
  }

  func testRememberPreservesScopeProvenanceEvidenceAndLegacyProjection() throws {
    let raw = RawMemoryEvent(kind: "message", content: "用户说喜欢简短回复")
    let evidence = MemoryEvidence(rawEventID: raw.id, excerpt: raw.content)
    let record = makeRecord(content: "喜欢简短回复", evidence: [evidence])

    try store.saveMemoryV2(record, rawEvents: [raw])
    try sdk.remember(record, evidence: [evidence])

    let loaded = try XCTUnwrap(store.memoryV2(id: record.id))
    XCTAssertEqual(loaded.scope, .global)
    XCTAssertEqual(loaded.provenance.originType, .userExplicit)
    XCTAssertEqual(loaded.evidence, [evidence])
    XCTAssertEqual(try store.memories().first(where: { $0.id == record.id })?.content, record.content)
  }

  func testRecallExcludesCandidatesAndKeepsPersonScope() throws {
    let personID = UUID()
    try sdk.remember(makeRecord(content: "小王喜欢电话", state: .active, scope: .person, personID: personID))
    try sdk.remember(makeRecord(content: "另一条候选", state: .candidate, scope: .person, personID: personID))

    let result = try sdk.recall(MemoryRecallRequest(query: "电话", personID: personID, scope: .person))
    XCTAssertEqual(result.map(\.content), ["小王喜欢电话"])
  }

  func testCorrectionWinsAndForgetIsReversibleVersionedState() throws {
    let original = makeRecord(content: "喜欢咖啡", state: .active)
    try sdk.remember(original)
    var replacement = original
    replacement.content = "不喝咖啡"
    try sdk.correct(id: original.id, replacement: replacement)

    let corrected = try XCTUnwrap(store.memoryV2(id: original.id))
    XCTAssertEqual(corrected.version, 2)
    XCTAssertEqual(corrected.state, .confirmed)
    XCTAssertEqual(corrected.provenance.originType, .userCorrection)

    try sdk.forget(id: original.id, mode: .archive)
    XCTAssertEqual(try store.memoryV2(id: original.id)?.state, .archived)
    XCTAssertEqual(try store.memoryV2(id: original.id)?.version, 3)
  }

  func testFTSRowIDUpdateReplacesOldTermsAndPreservesOtherPeople() throws {
    let alice = UUID(), bob = UUID()
    var first = makeRecord(content: "第一人的旧关键词", scope: .person, personID: alice)
    let second = makeRecord(content: "第二人的保留词", scope: .person, personID: bob)
    try sdk.remember(first)
    try sdk.remember(second)
    first.content = "第一人的新关键词"
    first.version += 1
    try sdk.remember(first)
    XCTAssertTrue(try store.searchMemoryV2(query: "新关键词").contains { $0.id == first.id })
    XCTAssertFalse(try store.searchMemoryV2(query: "旧关键词").contains { $0.id == first.id })
    XCTAssertTrue(try store.searchMemoryV2(query: "保留词").contains { $0.id == second.id })
  }

  func testFullDeleteDoesNotRetainVersionOrAuditSnapshots() throws {
    let raw = RawMemoryEvent(kind: "chat", content: "必须真正删除的证据")
    let evidence = MemoryEvidence(rawEventID: raw.id, excerpt: raw.content)
    let sensitive = makeRecord(content: "本机需要擦除的保密内容", evidence: [evidence])
    try store.saveMemoryV2(sensitive, rawEvents: [raw])
    let keep = makeRecord(content: "其他人的记录要保留")
    try sdk.remember(keep)
    let forget = MemoryForgetEngine(sdk: sdk, store: store)
    try forget.forget(id: sensitive.id, mode: .fullDelete)
    XCTAssertNil(try store.memoryV2(id: sensitive.id))
    XCTAssertEqual(try store.memoryV2VersionCount(id: sensitive.id), 0)
    XCTAssertTrue(try store.rawEvents(ids: [raw.id]).isEmpty)
    XCTAssertNil(try store.memory(id: sensitive.id))
    XCTAssertEqual(try store.memoryV2(id: keep.id)?.content, keep.content)
    XCTAssertThrowsError(try sdk.forget(id: sensitive.id, mode: .fullDelete))
  }

  func testRepeatedSaveOfSameVersionIsIdempotent() throws {
    let record = makeRecord(content: "只保存一个版本")
    try sdk.remember(record)
    try sdk.remember(record)

    XCTAssertEqual(try store.memoryV2Count(), 1)
    XCTAssertEqual(try store.memoryV2VersionCount(id: record.id), 1)
  }

  func testFlushBatchWritesAllVersionsLegacyAndEvidence() throws {
    let sessionID = UUID()
    let raw = RawMemoryEvent(kind: "chat", content: "双方确认")
    let records = (0..<30).map { i in
      makeRecord(content: "batch \(i)", evidence: [
        MemoryEvidence(rawEventID: raw.id, excerpt: raw.content)
      ])
    }
    let session = MemoryFlushSession(sessionID: sessionID, records: records, rawEvents: [raw])
    try sdk.flush(session)
    XCTAssertEqual(try store.memoryV2Count(), 30)
    XCTAssertEqual(try store.memories(limit: 100).count, 30)
    XCTAssertEqual(try store.memoryV2(id: records[0].id)?.sessionID, sessionID)
    XCTAssertEqual(try store.memoryV2(id: records[29].id)?.evidence.count, 1)
  }

  func testBatchRollsBackEverythingWhenEvidenceConflicts() throws {
    let evidenceID = UUID()
    let a = makeRecord(content: "batch first",
      evidence: [MemoryEvidence(id: evidenceID, rawEventID: UUID())])
    let b = makeRecord(content: "batch conflict",
      evidence: [MemoryEvidence(id: evidenceID, rawEventID: UUID())])
    XCTAssertThrowsError(try store.saveMemoryV2Batch([a,b]))
    XCTAssertEqual(try store.memoryV2Count(), 0)
    XCTAssertNil(try store.memoryV2(id: a.id))
  }

  func testV2AndLegacyProjectionRollbackTogetherWhenEvidenceConflicts() throws {
    let sharedEvidenceID = UUID()
    let first = makeRecord(
      content: "第一条",
      evidence: [MemoryEvidence(id: sharedEvidenceID, rawEventID: UUID())]
    )
    try sdk.remember(first, evidence: first.evidence)

    let second = makeRecord(
      content: "第二条",
      evidence: [MemoryEvidence(id: sharedEvidenceID, rawEventID: UUID())]
    )
    XCTAssertThrowsError(try sdk.remember(second, evidence: second.evidence))
    XCTAssertNil(try store.memoryV2(id: second.id))
    XCTAssertNil(try store.memory(id: second.id))
    XCTAssertEqual(try store.memoryV2Count(), 1)
  }

  private func makeRecord(
    content: String,
    state: MemoryState = .active,
    scope: MemoryScope = .global,
    personID: UUID? = nil,
    evidence: [MemoryEvidence] = []
  ) -> MemoryV2Record {
    MemoryV2Record(
      type: .preference,
      state: state,
      scope: scope,
      content: content,
      personID: personID,
      provenance: MemoryProvenance(originType: .userExplicit, ingestionMethod: "test"),
      evidence: evidence
    )
  }
}
