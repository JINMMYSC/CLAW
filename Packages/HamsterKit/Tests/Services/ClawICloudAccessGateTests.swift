import Foundation
import XCTest
@testable import HamsterKit

final class ClawICloudAccessGateTests: XCTestCase {
  func testFalseCapabilityBlocksBeforeContainerResolution() {
    var resolutions = 0
    let gate = ClawICloudAccessGate(
      readCapability: { false },
      resolveContainer: { _ in
        resolutions += 1
        return URL(fileURLWithPath: "/unused")
      }
    )

    XCTAssertThrowsError(try gate.documentsURL()) {
      XCTAssertEqual($0 as? ClawICloudAccessError, .missingSigningCapability)
    }
    XCTAssertEqual(resolutions, 0)
  }

  func testUnknownCapabilityBlocksBeforeContainerResolution() {
    var resolutions = 0
    let gate = ClawICloudAccessGate(
      readCapability: { nil },
      resolveContainer: { _ in
        resolutions += 1
        return URL(fileURLWithPath: "/unused")
      }
    )

    XCTAssertThrowsError(try gate.documentsURL()) {
      XCTAssertEqual($0 as? ClawICloudAccessError, .unknownSigningCapability)
    }
    XCTAssertEqual(resolutions, 0)
  }

  func testEntitledBuildResolvesConfiguredContainerIdentifier() throws {
    let container = URL(fileURLWithPath: "/configured-cloud", isDirectory: true)
    var identifier: String?
    let gate = ClawICloudAccessGate(
      readCapability: { true },
      resolveContainer: {
        identifier = $0
        return container
      }
    )

    XCTAssertEqual(
      try gate.documentsURL(),
      container.appendingPathComponent("Documents", isDirectory: true)
    )
    XCTAssertEqual(identifier, HamsterConstants.iCloudID)
  }

  func testUnavailableContainerThrowsBeforeFileMutation() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-gate-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sentinel = root.appendingPathComponent("local.txt")
    let original = Data("keep-local-data".utf8)
    try original.write(to: sentinel)
    let gate = ClawICloudAccessGate(
      readCapability: { true },
      resolveContainer: { _ in nil }
    )

    XCTAssertThrowsError(try gate.documentsURL()) {
      XCTAssertEqual($0 as? ClawICloudAccessError, .containerUnavailable)
    }
    XCTAssertEqual(try Data(contentsOf: sentinel), original)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["local.txt"])
  }

  func testDocumentsURLUsesOneContainerResolution() throws {
    let first = URL(fileURLWithPath: "/first-container", isDirectory: true)
    let second = URL(fileURLWithPath: "/changed-container", isDirectory: true)
    var resolutions = 0
    var capabilityReads = 0
    let gate = ClawICloudAccessGate(
      readCapability: {
        capabilityReads += 1
        return true
      },
      resolveContainer: { _ in
        resolutions += 1
        return resolutions == 1 ? first : second
      }
    )

    XCTAssertEqual(
      try gate.documentsURL(),
      first.appendingPathComponent("Documents", isDirectory: true)
    )
    XCTAssertEqual(capabilityReads, 1)
    XCTAssertEqual(resolutions, 1)
  }

  func testMissingOrNonBooleanBundleStampIsUnknown() throws {
    for stamp in [nil, "true"] as [String?] {
      let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClawGate-" + UUID().uuidString + ".bundle", isDirectory: true)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      var info: [String: Any] = [
        "CFBundleIdentifier": "test.claw.gate." + UUID().uuidString,
        "CFBundleName": "ClawGate",
        "CFBundlePackageType": "BNDL",
        "CFBundleVersion": "1",
      ]
      if let stamp { info["ClawICloudContainerEntitled"] = stamp }
      let data = try PropertyListSerialization.data(
        fromPropertyList: info, format: .xml, options: 0
      )
      try data.write(to: root.appendingPathComponent("Info.plist"))
      let bundle = try XCTUnwrap(Bundle(url: root))
      var resolutions = 0
      let gate = ClawICloudAccessGate(
        readCapability: {
          bundle.object(forInfoDictionaryKey: "ClawICloudContainerEntitled") as? Bool
        },
        resolveContainer: { _ in
          resolutions += 1
          return URL(fileURLWithPath: "/unused")
        }
      )

      XCTAssertThrowsError(try gate.documentsURL()) {
        XCTAssertEqual($0 as? ClawICloudAccessError, .unknownSigningCapability)
      }
      XCTAssertEqual(resolutions, 0)
    }
  }
}
