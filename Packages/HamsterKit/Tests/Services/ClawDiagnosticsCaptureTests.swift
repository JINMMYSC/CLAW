import Foundation
import XCTest
@testable import HamsterKit

final class ClawDiagnosticsCaptureTests: XCTestCase {
  func testMergesBothProcessesInTimestampOrderWithoutDeclaringMissingKeyboardHealthy() throws {
    let host = ClawDiagnosticsCore(storageURL: nil, processName: "host")
    let keyboard = ClawDiagnosticsCore(storageURL: nil, processName: "keyboard")
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

  func testExportContainsOnlyRedactedEvents() throws {
    let logger = ClawDiagnosticsCore(storageURL: nil, processName: "host")
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
