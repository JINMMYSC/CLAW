import Foundation
import XCTest
@testable import HamsterKit

final class ClawScreenshotEvidencePathSafetyTests: XCTestCase {
  func testUntrustedSourceRefCannotEscapeEncryptedEvidenceDirectory() throws {
    let store = ClawScreenshotEvidenceStore.shared
    let files = FileManager.default
    let group = files.containerURL(forSecurityApplicationGroupIdentifier: HamsterConstants.appGroupName)
    let fallback = files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? files.temporaryDirectory
    let evidence = (group ?? fallback)
      .appendingPathComponent("ClawMemory", isDirectory: true)
      .appendingPathComponent("Evidence", isDirectory: true)
    let filename = UUID().uuidString
    let outside = evidence.appendingPathComponent(filename + ".clawenc")
    let encrypted = evidence.deletingLastPathComponent()
      .appendingPathComponent("EncryptedEvidence", isDirectory: true)
    let invalidID = "invalid-" + UUID().uuidString
    let invalidName = encrypted.appendingPathComponent(invalidID + ".clawenc")
    let validID = UUID().uuidString
    let validName = encrypted.appendingPathComponent(validID + ".clawenc")
    try files.createDirectory(at: evidence, withIntermediateDirectories: true)
    try files.createDirectory(at: encrypted, withIntermediateDirectories: true)
    try Data("path-safety-fixture".utf8).write(to: outside, options: .atomic)
    try Data("invalid-name-fixture".utf8).write(to: invalidName, options: .atomic)
    try Data("valid-name-fixture".utf8).write(to: validName, options: .atomic)
    defer { try? files.removeItem(at: outside) }
    defer { try? files.removeItem(at: invalidName) }
    defer { try? files.removeItem(at: validName) }

    let traversal = "screenshot-evidence:../Evidence/" + filename
    XCTAssertNil(store.url(for: traversal), "A source reference must never resolve outside EncryptedEvidence")
    XCTAssertNil(store.url(for: "screenshot-evidence:../"))
    XCTAssertNil(store.url(for: "screenshot-evidence:" + invalidID))
    XCTAssertEqual(store.url(for: "screenshot-evidence:" + validID)?.standardizedFileURL,
                   validName.standardizedFileURL)
  }
}
