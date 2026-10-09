import Foundation
import XCTest
@testable import HamsterKit

final class ClawDiagnosticsCoreTests: XCTestCase {
  func testPrivateContentIsRejectedByIdentifierWhitelist() {
    XCTAssertEqual(ClawDiagnosticsCore.identifier("voice.session_failed"), "voice.session_failed")
    XCTAssertEqual(ClawDiagnosticsCore.identifier("聊天 张三"), "redacted")
    XCTAssertEqual(ClawDiagnosticsCore.identifier("key=secret"), "redacted")
  }

  func testCustomNSErrorDomainsCannotLeakPrivateText() {
    XCTAssertEqual(ClawDiagnosticsCore.safeErrorDomain("AVAudioSessionErrorDomain"), "AVAudioSessionErrorDomain")
    XCTAssertEqual(ClawDiagnosticsCore.safeErrorDomain("CONTACT_SECRET_123"), "unrecognized_error_domain")
    XCTAssertEqual(ClawDiagnosticsCore.safeErrorDomain("CKErrorDomain"), "CKErrorDomain")
  }

  func testUnderlyingErrorCodeIsRecordedWithoutLocalizedDescription() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let recorder = ClawDiagnosticsCore(storageURL: url, processName: "host")
    let error = NSError(domain: "AVAudioSessionErrorDomain", code: -50,
                        userInfo: [NSLocalizedDescriptionKey: "SECRET_PRIVATE_CHAT"])
    recorder.record(module: "voice", action: "activation_failed", severity: "error", error: error)
    let events = recorder.recent()
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0].errorDomain, "AVAudioSessionErrorDomain")
    XCTAssertEqual(events[0].errorCode, -50)
    XCTAssertTrue(events[0].file.contains("ClawDiagnosticsCoreTests"))
    let json = try XCTUnwrap(recorder.exportJSON())
    XCTAssertFalse(String(decoding: json, as: UTF8.self).contains("SECRET_PRIVATE_CHAT"))
  }

  func testBoundedRingAndUnknownInformation() {
    let recorder = ClawDiagnosticsCore(storageURL: URL(fileURLWithPath: "/dev/null"), processName: "keyboard")
    for _ in 0..<2_010 { recorder.record(module: "keyboard", action: "layout") }
    XCTAssertEqual(recorder.recent(limit: 2_100).count, 2_000)
    XCTAssertEqual(recorder.recent(limit: 1).count, 1)
    XCTAssertTrue(ClawDiagnosticInspector.report(events: []).contains("不代表软件所有功能正常"))
  }
}
