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
}
