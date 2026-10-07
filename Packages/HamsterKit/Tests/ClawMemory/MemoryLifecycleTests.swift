import XCTest
@testable import HamsterKit

final class MemoryLifecycleTests: XCTestCase {
  func testCandidatePromotionRequiresRepetitionAndSourceDiversity() {
    let candidate = record("用户偏好短回复", state: .candidate)
    let engine = MemoryPromotionEngine()

    XCTAssertEqual(
      engine.evaluate(candidate, observationCount: 2, distinctSourceCount: 1).state,
      .candidate
    )
    XCTAssertEqual(
      engine.evaluate(candidate, observationCount: 3, distinctSourceCount: 2).state,
      .active
    )
  }

  func testUserCorrectionWinsConflictAndLowTrustConflictNeedsReview() {
    let existing = record("喜欢咖啡", state: .active, origin: .userCorrection)
    let inferred = record("不喝咖啡", state: .candidate, origin: .clawInference)
    XCTAssertEqual(MemoryConflictResolver().resolve(existing: existing, incoming: inferred), .keepExisting)

    let first = record("会议在周五", state: .active, origin: .connectedService)
    let second = record("会议在周六", state: .candidate, origin: .externalContent)
    guard case .needsReview(let conflict) = MemoryConflictResolver().resolve(existing: first, incoming: second) else {
      return XCTFail("expected a reviewable conflict")
    }
    XCTAssertEqual(conflict.existingMemoryID, first.id)
    XCTAssertEqual(conflict.incomingMemoryID, second.id)
  }

  func testStaleDecayAndForgetCreateReversibleAudit() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("memory-lifecycle-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let sdk = DefaultMemorySDK(store: store)
    var old = record("旧项目状态", state: .active)
    old.updatedAt = Date(timeIntervalSinceNow: -200 * 86_400)
    try sdk.remember(old)

    XCTAssertEqual(MemoryPromotionEngine().decay(old, now: Date()).state, .stale)
    try MemoryForgetEngine(sdk: sdk, store: store).forget(id: old.id, mode: .archive)

    XCTAssertEqual(try store.memoryV2(id: old.id)?.state, .archived)
    let audit = try XCTUnwrap(store.memoryAuditRecords(memoryID: old.id).last)
    XCTAssertEqual(audit.kind, .forget)
    try MemoryForgetEngine(sdk: sdk, store: store).rollback(auditID: audit.id)
    XCTAssertEqual(try store.memoryV2(id: old.id)?.state, .active)
  }

  private func record(
    _ content: String,
    state: MemoryState,
    origin: MemoryOriginType = .userBehavior
  ) -> MemoryV2Record {
    MemoryV2Record(
      type: .preference,
      state: state,
      scope: .global,
      content: content,
      normalizedKey: "preference",
      provenance: MemoryProvenance(originType: origin, ingestionMethod: "test")
    )
  }
}
