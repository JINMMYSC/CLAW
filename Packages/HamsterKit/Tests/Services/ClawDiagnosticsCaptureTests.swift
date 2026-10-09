import Foundation
import XCTest
@testable import HamsterKit

final class ClawDiagnosticsCaptureTests: XCTestCase {
  func testMergesBothProcessesInTimestampOrderWithoutDeclaringMissingKeyboardHealthy() throws {
    let host = ClawDiagnosticsCore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), processName: "host")
    let keyboard = ClawDiagnosticsCore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), processName: "keyboard")
    host.record(module: "ui", action: "assistant_appeared")
    keyboard.record(module: "keyboard", action: "candidate_expanded")
    let capture = ClawDiagnosticsCaptureService.capture(
      hostEvents: host.recent(),
      keyboardEvents: keyboard.recent(),
      keyboardState: .stale
    )
    XCTAssertEqual(capture.events.count, 2)
    XCTAssertEqual(capture.hostState, .recent)
    XCTAssertEqual(capture.keyboardState, .stale)
    XCTAssertEqual(capture.events.map(\.process).sorted(), ["host", "keyboard"])
  }

  func testUnavailableAndCorruptKeyboardHaveExplicitStatuses() throws {
    XCTAssertEqual(ClawDiagnosticsCaptureService.readKeyboard(at: nil).state, .unavailable)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    XCTAssertEqual(ClawDiagnosticsCaptureService.readKeyboard(at: file).state, .missing)
    try Data("not json".utf8).write(to: file)
    XCTAssertEqual(ClawDiagnosticsCaptureService.readKeyboard(at: file).state, .corrupted)
  }

  func testDiagnosticExportCleanupOnlyDeletesExpiredArchives() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    func create(_ name: String, modified: Date) throws -> URL {
      let folder = root.appendingPathComponent(name, isDirectory: true)
      try fm.createDirectory(at: folder, withIntermediateDirectories: true)
      try Data("safe".utf8).write(to: folder.appendingPathComponent("CLAW-Diagnostics.zip"))
      try fm.setAttributes([.modificationDate: modified], ofItemAtPath: folder.path)
      return folder
    }
    let now = Date(timeIntervalSince1970: 2_000_000)
    let old = try create("claw-report-" + UUID().uuidString, modified: now.addingTimeInterval(-100_000))
    let fresh = try create("claw-report-" + UUID().uuidString, modified: now.addingTimeInterval(-10))
    let unrelated = try create("other-report-" + UUID().uuidString, modified: now.addingTimeInterval(-100_000))
    ClawDiagnosticsCaptureService.pruneOldExports(in: root, now: now)
    XCTAssertFalse(fm.fileExists(atPath: old.path))
    XCTAssertTrue(fm.fileExists(atPath: fresh.path))
    XCTAssertTrue(fm.fileExists(atPath: unrelated.path))
  }

  func testExportContainsOnlyRedactedEvents() throws {
    let logger = ClawDiagnosticsCore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), processName: "host")
    logger.record(
      module: "voice", action: "session_failed", severity: "error",
      error: NSError(domain: "AVAudioSessionErrorDomain", code: 1,
                     userInfo: [NSLocalizedDescriptionKey: "SECRET_PRIVATE_CHAT"])
    )
    let capture = ClawDiagnosticsCaptureService.capture(
      hostEvents: logger.recent(),
      keyboardEvents: [],
      keyboardState: .unavailable
    )
    let url = try ClawDiagnosticsCaptureService.exportZip(capture: capture)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    XCTAssertGreaterThan(try Data(contentsOf: url).count, 100)
    XCTAssertEqual(capture.incidents.count, 1)
    XCTAssertEqual(capture.incidents[0].errorDomain, "AVAudioSessionErrorDomain")
    let json = try JSONEncoder().encode(capture)
    XCTAssertFalse(String(decoding: json, as: UTF8.self).contains("SECRET_PRIVATE_CHAT"))
  }
}
