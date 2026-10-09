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
}
