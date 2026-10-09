@testable import HamsterKit
import XCTest

final class ClawScaleGateTests: XCTestCase {
  func testTwoThousandMemoryWriteAndRecallBudget() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("claw-scale-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let writeStart = Date()
    for index in 0..<2_000 {
      try store.saveMemoryV2(MemoryV2Record(
        type: .semantic, state: .active, scope: .global,
        content: "deterministic memory \(index)", normalizedKey: "fixture-\(index)",
        provenance: .init(originType: .systemObserved, ingestionMethod: "scale-fixture")
      ))
    }
    let writeDuration = Date().timeIntervalSince(writeStart)
    let recallStart = Date()
    let result = try store.searchMemoryV2(query: "deterministic memory 1999", limit: 30)
    let recallDuration = Date().timeIntervalSince(recallStart)
    XCTAssertEqual(try store.memoryV2Count(), 2_000)
    XCTAssertFalse(result.isEmpty)
    XCTAssertLessThan(writeDuration, 30, "2k V2 writes exceeded the release gate")
    XCTAssertLessThan(recallDuration, 3, "2k hybrid recall exceeded the release gate")
  }

  /// Release-only stress gate. Keep regular CI light: explicitly run with
  /// TEST_RUNNER_CLAW_STRESS_TEST=1 on a simulator to exercise the full scale.
  func testOptInHundredThousandMemoriesAndPersonIsolation() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["CLAW_STRESS_TEST"] == "1" || env["TEST_RUNNER_CLAW_STRESS_TEST"] == "1" else {
      throw XCTSkip("100k memory stress is opt-in; run the CI workflow_dispatch stress_100k input")
    }
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-100k-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let alice = UUID()
    let bob = UUID()
    let historical = MemoryV2Record(
      type: .semantic, state: .active, scope: .person,
      content: "唯一的历史方案需要星期五验收",
      normalizedKey: "historical-unique",
      personID: alice,
      provenance: .init(originType: .systemObserved, ingestionMethod: "scale-fixture")
    )

    let writeStart = Date()
    // Use production's batched transaction path. The earlier per-record
    // baseline was 1,259s for 100k writes on the CI simulator.
    var batch = [historical]
    for index in 1..<100_000 {
      let scope: MemoryScope = index.isMultiple(of: 20) ? .global : .person
      let personID: UUID? = scope == .person ? bob : nil
      batch.append(MemoryV2Record(
        type: .semantic, state: .active, scope: scope,
        content: "规模测试记录 \(index) 的变化",
        normalizedKey: "scale-\(index)", personID: personID,
        provenance: .init(originType: .systemObserved, ingestionMethod: "scale-fixture")
      ))
      if batch.count == 500 {
        try store.saveMemoryV2Batch(batch)
        batch.removeAll(keepingCapacity: true)
      }
    }
    if !batch.isEmpty { try store.saveMemoryV2Batch(batch) }
    let writeDuration = Date().timeIntervalSince(writeStart)
    let scopedStart = Date()
    let aliceRows = try store.memoryV2(scope: .person, personID: alice, limit: 80)
    let scopedDuration = Date().timeIntervalSince(scopedStart)
    let searchStart = Date()
    let recalled = try store.searchMemoryV2(query: "唯一的历史方案", limit: 30)
    let searchDuration = Date().timeIntervalSince(searchStart)
    XCTAssertEqual(try store.memoryV2Count(), 100_000)
    XCTAssertEqual(aliceRows.map(\.id), [historical.id])
    XCTAssertTrue(recalled.contains { $0.id == historical.id },
                  "Old Chinese facts must remain discoverable at 100k records")
    print("CLAW_SCALE_100K: writes=\(writeDuration)s, indexed_person_recall=\(scopedDuration)s, keyword_recall=\(searchDuration)s")
  }
}
