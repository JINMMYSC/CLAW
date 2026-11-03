@testable import HamsterKit

import Foundation
import XCTest

final class ClawRimeUserDataBootstrapTests: XCTestCase {
  func testMissingAndEmptyUserDataCanBeSeededWithoutOverwritingExistingFiles() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-rime-userdata-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let userData = root.appendingPathComponent("UserData", isDirectory: true)

    XCTAssertTrue(try FileManager.shouldSeedBundledUserData(at: userData))
    try FileManager.default.createDirectory(at: userData, withIntermediateDirectories: true)
    XCTAssertTrue(try FileManager.shouldSeedBundledUserData(at: userData))

    let customDictionary = userData.appendingPathComponent("custom.userdb")
    try Data("user-owned-rime-state".utf8).write(to: customDictionary)
    XCTAssertFalse(try FileManager.shouldSeedBundledUserData(at: userData))
    XCTAssertEqual(
      try String(contentsOf: customDictionary, encoding: .utf8),
      "user-owned-rime-state"
    )
  }

  func testExistingNonDirectoryIsNotTreatedAsDisposableUserData() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-rime-file-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let userData = root.appendingPathComponent("UserData")
    try Data("preserve-me".utf8).write(to: userData)

    XCTAssertThrowsError(try FileManager.shouldSeedBundledUserData(at: userData))
    XCTAssertEqual(try String(contentsOf: userData, encoding: .utf8), "preserve-me")
  }
}
