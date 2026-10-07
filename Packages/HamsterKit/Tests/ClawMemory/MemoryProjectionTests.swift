import XCTest
@testable import HamsterKit

final class MemoryProjectionTests: XCTestCase {
  func testSDKBuildsTypedProjectionsWithoutCrossPersonLeakage() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("memory-projection-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ClawMemoryStore(databaseURL: root.appendingPathComponent("memory.sqlite"))
    let sdk = DefaultMemorySDK(store: store)
    let selected = UUID(), other = UUID()
    try sdk.remember(MemoryV2Record(type: .communication, state: .active, scope: .person, content: "小王偏好直说", personID: selected, provenance: .init(originType: .userExplicit, ingestionMethod: "test")))
    try sdk.remember(MemoryV2Record(type: .communication, state: .active, scope: .person, content: "小李偏好寒暄", personID: other, provenance: .init(originType: .userExplicit, ingestionMethod: "test")))

    let projection = try sdk.projection(.communication, personID: selected, projectID: nil, limit: 20)

    XCTAssertEqual(projection.records.map(\.content), ["小王偏好直说"])
  }
}
