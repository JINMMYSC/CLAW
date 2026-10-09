import Foundation
import XCTest
@testable import HamsterKit

final class ClawReadOnlyDiagnosticToolsTests: XCTestCase {
  private func emptyCapture() -> ClawDiagnosticCapture {
    ClawDiagnosticsCaptureService.capture(
      hostEvents: [], keyboardEvents: [],
      keyboardState: .missing
    )
  }

  func testMissingEvidenceIsUnknownRatherThanHealthy() {
    let tools = ClawReadOnlyDiagnosticTools(capture: emptyCapture(), version: "8", commit: nil)
    XCTAssertEqual(tools.getAppStatus().status, .unknown)
    XCTAssertEqual(tools.inspectVoice().status, .unknown)
    XCTAssertEqual(tools.inspectSync().status, .unknown)
    XCTAssertEqual(tools.getRecentErrors().status, .unknown)
    XCTAssertEqual(tools.getModuleHealth("keyboard").status, .unknown)
  }

  func testUnknownModuleCannotBeQueried() {
    let tools = ClawReadOnlyDiagnosticTools(capture: emptyCapture())
    XCTAssertEqual(tools.getModuleHealth("arbitraryPrivateText").status, .unavailable)
  }

  func testSelfTestNeverClaimsHealthyModuleBasedOnNoErrors() {
    let tools = ClawReadOnlyDiagnosticTools(capture: emptyCapture())
    let results = tools.runSelfTest()
    XCTAssertEqual(results.count, 8)
    XCTAssertTrue(results.allSatisfy { $0.status != .fault })
    XCTAssertTrue(results.allSatisfy { $0.status != .ok || $0.name == "getAppStatus" })
  }
  func testRealPermissionFaultHasObservedTimestampWithoutFabricatedTrace() {
    let snapshot = ClawDiagnosticCapabilityObservation(status: .fault, message: "用户拒绝麦克风权限")
    let tools = ClawReadOnlyDiagnosticTools(
      capture: emptyCapture(), version: "1", commit: nil,
      voiceObservation: snapshot)
    let result = tools.inspectVoice()
    XCTAssertEqual(result.status, .fault)
    XCTAssertNotNil(result.observedAt)
    XCTAssertTrue(result.evidenceTraceIDs.isEmpty)
  }

  func testSignedCloudCapabilityMissingOverridesNoEventUnknown() {
    let snapshot = ClawDiagnosticCapabilityObservation(status: .fault, message: "没有 CloudDocuments 权限")
    let tools = ClawReadOnlyDiagnosticTools(
      capture: emptyCapture(), version: "1", commit: nil,
      syncObservation: snapshot)
    XCTAssertEqual(tools.inspectSync().status, .fault)
  }

}
