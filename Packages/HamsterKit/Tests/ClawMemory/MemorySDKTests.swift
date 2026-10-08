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

  func testRepeatedSaveOfSameVersionIsIdempotent() throws {
    let record = makeRecord(content: "只保存一个版本")
    try sdk.remember(record)
    try sdk.remember(record)

    XCTAssertEqual(try store.memoryV2Count(), 1)
    XCTAssertEqual(try store.memoryV2VersionCount(id: record.id), 1)
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
