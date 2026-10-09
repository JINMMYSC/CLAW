import CoreGraphics
import XCTest
@testable import HamsterKeyboardKit

final class ClawVoiceAndCandidatePolicyTests: XCTestCase {
  func testCompactToolbarHidesSecondaryActionsButPreservesMainAIActions() {
    let width320 = ClawToolbarCompactPolicy.widths(for: 320)
    XCTAssertTrue(width320.hidesSecondary)
    XCTAssertEqual(width320.eye, 0)
    XCTAssertEqual(width320.emoji, 0)
    XCTAssertGreaterThanOrEqual(width320.ai, 32)
    XCTAssertGreaterThanOrEqual(width320.more, 34)
    // Seven gaps, fixed margins and all visible actions should fit 320pt.
    let occupied = width320.contact + width320.reply + width320.rewrite +
      width320.ai + width320.eye + width320.emoji +
      width320.more + width320.dismiss + 31
    XCTAssertLessThanOrEqual(occupied, 320)
  }

  func testWideToolbarRestoresVisiblePrivacyAndEmojiControls() {
    let width430 = ClawToolbarCompactPolicy.widths(for: 430)
    XCTAssertFalse(width430.hidesSecondary)
    XCTAssertEqual(width430.eye, 26)
    XCTAssertEqual(width430.emoji, 26)
    let width300 = ClawToolbarCompactPolicy.widths(for: 300)
    XCTAssertTrue(width300.hidesSecondary)
    XCTAssertLessThanOrEqual(width300.contact + width300.reply + width300.rewrite + width300.ai +
      width300.more + width300.dismiss + 31, 300)
  }

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

  func testVoicePreflightBlocksMissingPermissionBeforeAudioSession() {
    XCTAssertNil(ClawVoiceLaunchPolicy.recordingError(isKeyboardExtension: false, authorization: .authorized))
    XCTAssertNotNil(ClawVoiceLaunchPolicy.recordingError(isKeyboardExtension: false, authorization: .undetermined))
    XCTAssertNotNil(ClawVoiceLaunchPolicy.recordingError(isKeyboardExtension: false, authorization: .denied))
    XCTAssertNotNil(ClawVoiceLaunchPolicy.recordingError(isKeyboardExtension: true, authorization: .authorized))
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
