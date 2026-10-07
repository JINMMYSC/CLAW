import XCTest
@testable import HamsterKit

final class ClawDreamEngineTests: XCTestCase {
  func testDreamRunsFourStagesAndRollbackRestoresRecord() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dream-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let sdk = DefaultMemorySDK(store: store)
    let first = record("用户连续三次要求简短回复", confidence: 0.72)
    let second = record("用户要求简短回复", confidence: 0.74)
    try sdk.remember(first)
    try sdk.remember(second)

    let engine = ClawDreamEngine(store: store)
    let run = try engine.run(records: [first, second], budget: ClawDreamBudget(maxMutations: 1))

    XCTAssertEqual(run.completedStages, [.light, .rem, .deep, .audit])
    XCTAssertEqual(run.mutations.count, 1)
    XCTAssertFalse(try store.memoryAuditRecords(memoryID: run.mutations[0].memoryID).isEmpty)

    try engine.rollback(runID: run.id)
    XCTAssertEqual(try store.memoryV2(id: first.id)?.state, .active)
    XCTAssertEqual(try store.memoryV2(id: second.id)?.state, .active)
  }

  func testLowTrustDreamProposalRequiresReview() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dream-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let lowTrust = MemoryV2Record(
      type: .semantic,
      state: .candidate,
      scope: .global,
      content: "外部网页推测",
      provenance: MemoryProvenance(originType: .externalContent, ingestionMethod: "web")
    )

    let run = try ClawDreamEngine(store: store).run(records: [lowTrust], budget: .init(maxMutations: 1))
    XCTAssertEqual(run.mutations.first?.requiresReview, true)
    XCTAssertNil(try store.memoryV2(id: lowTrust.id))
  }

  private func record(_ content: String, confidence: Double) -> MemoryV2Record {
    MemoryV2Record(
      type: .preference,
      state: .active,
      scope: .global,
      content: content,
      normalizedKey: "short-reply",
      confidence: confidence,
      provenance: MemoryProvenance(originType: .userBehavior, ingestionMethod: "chat")
    )
  }
}
