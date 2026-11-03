@testable import HamsterKit

import Foundation
import XCTest

final class ClawFirstLaunchResourcePreservationTests: XCTestCase {
  func testMissingAndEmptyDirectoriesRequireInitialization() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-first-launch-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let missing = root.appendingPathComponent("missing", isDirectory: true)
    XCTAssertTrue(FileManager.shouldInitializeBundledDirectory(at: missing))

    let empty = root.appendingPathComponent("empty", isDirectory: true)
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    XCTAssertTrue(FileManager.shouldInitializeBundledDirectory(at: empty))
  }

  func testNonemptyUserDataAndBackupsMustNeverBeReinitialized() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-first-launch-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    for directory in ["user-data", "backup", "shared-support"] {
      let destination = root.appendingPathComponent(directory, isDirectory: true)
      try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
      let existing = destination.appendingPathComponent("user-owned-data")
      try Data("preserve-me".utf8).write(to: existing)
      XCTAssertFalse(FileManager.shouldInitializeBundledDirectory(at: destination))
      XCTAssertEqual(try Data(contentsOf: existing), Data("preserve-me".utf8))
    }
  }
}
