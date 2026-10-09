@testable import HamsterKit

import Foundation
import XCTest

final class FileManagerTest: XCTestCase {
  func testIncrementalCopyDoesNotSilentlyPassMissingSourceOrDestination() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-filetest-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let src = root.appendingPathComponent("source", isDirectory: true)
    let dst = root.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
    XCTAssertThrowsError(try FileManager.incrementalCopy(src: src, dst: dst))
    try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    try FileManager.default.removeItem(at: dst)
    XCTAssertThrowsError(try FileManager.incrementalCopy(src: src, dst: dst))
  }

  func testIncrementalCopyReplacesFileAndNeverLeavesStagingFile() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("claw-atomic-copy-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let src = root.appendingPathComponent("src", isDirectory: true)
    let dst = root.appendingPathComponent("dst", isDirectory: true)
    try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
    let sourceFile = src.appendingPathComponent("word.txt")
    let destinationFile = dst.appendingPathComponent("word.txt")
    try Data("new".utf8).write(to: sourceFile)
    try Data("old".utf8).write(to: destinationFile)
    try FileManager.incrementalCopy(src: src, dst: dst)
    XCTAssertEqual(try String(contentsOf: destinationFile, encoding: .utf8), "new")
    let names = try FileManager.default.contentsOfDirectory(atPath: dst.path)
    XCTAssertEqual(names, ["word.txt"])
  }

  func testResolveAppGroupContainerUsesSharedContainerWhenAvailable() {
    let sharedURL = URL(fileURLWithPath: "/shared")
    let fallbackURL = URL(fileURLWithPath: "/fallback")

    XCTAssertEqual(
      FileManager.resolveAppGroupContainerURL(sharedURL, fallbackURL: fallbackURL),
      sharedURL
    )
  }

  func testResolveAppGroupContainerUsesFallbackWhenUnavailable() {
    let fallbackURL = URL(fileURLWithPath: "/fallback")

    XCTAssertEqual(
      FileManager.resolveAppGroupContainerURL(nil, fallbackURL: fallbackURL),
      fallbackURL
    )
  }
}
