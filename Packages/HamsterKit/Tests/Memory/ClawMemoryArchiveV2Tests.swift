@testable import HamsterKit
import Foundation
import XCTest

final class ClawMemoryArchiveV2Tests: XCTestCase {
  func testArchiveRoundTripPreservesIdentityEvidenceAndLineage() throws {
    let raw = RawMemoryEvent(kind: "message", content: "source")
    let record = MemoryV2Record(
      type: .semantic, state: .confirmed, scope: .global, content: "CLAW ships Friday",
      provenance: .init(originType: .userExplicit, ingestionMethod: "test"),
      evidence: [.init(rawEventID: raw.id, excerpt: "source")],
      lineage: .init(rawEventIDs: [raw.id]), version: 4
    )
    let snapshot = ClawMemoryArchiveSnapshot(memories: [record], rawEvents: [raw], audits: [])
    let url = try ClawMemoryArchiveV2().export(snapshot: snapshot, now: Date(timeIntervalSince1970: 1_900_000_000))
    defer { try? FileManager.default.removeItem(at: url) }
    XCTAssertEqual(try ClawMemoryArchiveV2().verifyAndDecode(url), snapshot)
  }

  func testVersionVectorDetectsConcurrentChangesAndDeletionWins() {
    let id = UUID()
    let local = MemorySyncOperation(deviceID: "a", memoryID: id, kind: .upsert, record: nil, vector: .init(["a": 2]), createdAt: .distantPast)
    let remote = MemorySyncOperation(deviceID: "b", memoryID: id, kind: .delete, record: nil, vector: .init(["b": 1]), createdAt: .distantFuture)
    XCTAssertEqual(MemorySyncMerger().merge(local: local, remote: remote), .accepted(remote))
  }

  func testSyncRequiresOptInAndNeverUploadsLocalOnlyMemory() {
    let record = MemoryV2Record(type: .semantic, scope: .localOnly, content: "device secret", provenance: .init(originType: .userExplicit, ingestionMethod: "test"), cloudPermission: .localOnly)
    XCTAssertFalse(MemorySyncPolicy().canSync(record, isOptedIn: true))
    var cloud = record; cloud.scope = .global; cloud.cloudPermission = .privateCloud
    XCTAssertFalse(MemorySyncPolicy().canSync(cloud, isOptedIn: false))
    XCTAssertTrue(MemorySyncPolicy().canSync(cloud, isOptedIn: true))
  }
}
