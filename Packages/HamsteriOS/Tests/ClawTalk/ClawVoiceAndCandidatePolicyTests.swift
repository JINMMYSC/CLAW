import CoreGraphics
import XCTest
@testable import HamsterKeyboardKit

final class ClawVoiceAndCandidatePolicyTests: XCTestCase {
  func testKeyboardExtensionRoutesMicToHostApp() {
    XCTAssertEqual(
      ClawVoiceLaunchPolicy.action(isKeyboardExtension: true, authorization: .authorized),
      .openHostDictation
    )
  }

  func testHostRuntimeCanRecordWhenAuthorized() {
    XCTAssertEqual(
      ClawVoiceLaunchPolicy.action(isKeyboardExtension: false, authorization: .authorized),
      .recordLocally
    )
  }

  func testOneShotDictationKeepsPartialTranscriptForStopFallback() {
    XCTAssertTrue(ClawVoiceInputService.makeOneShotRequest().shouldReportPartialResults)
  }

  func testExpandedCandidateHeightUsesRootHeightWhenKeyboardBoundsAreNotReady() {
    XCTAssertEqual(
      CandidateExpandedLayoutMetrics.toolbarHeight(
        rootHeight: 291,
        collapsedToolbarHeight: 55,
        keyboardBoundsHeight: 0
      ),
      291
    )
  }

  func testExpandedCandidateHeightIncludesMeasuredKeyboardArea() {
    XCTAssertEqual(
      CandidateExpandedLayoutMetrics.toolbarHeight(
        rootHeight: 291,
        collapsedToolbarHeight: 55,
        keyboardBoundsHeight: 236
      ),
      291
    )
  }
}
