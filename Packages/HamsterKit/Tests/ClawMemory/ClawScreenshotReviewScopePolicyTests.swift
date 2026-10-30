import Foundation
import XCTest
@testable import HamsterKit

final class ClawScreenshotReviewScopePolicyTests: XCTestCase {
  func testReviewCannotReassignAnotherContactsScreenshotMessage() {
    let selected = UUID()
    let other = UUID()
    let foreign = ClawConversationMessage(
      contactID: other, speaker: .other, content: "Another person's private chat",
      sourceType: "screenshot"
    )
    XCTAssertFalse(ClawScreenshotReviewScopePolicy.permits(foreign, for: selected))
  }

  func testAssistantAndSystemRowsCannotMasqueradeAsReviewedHumanBubbles() {
    let selected = UUID()
    for speaker: ClawConversationSpeaker in [.assistant, .system, .unknown] {
      let message = ClawConversationMessage(
        contactID: selected, speaker: speaker, content: "Generated text",
        sourceType: "screenshot"
      )
      XCTAssertFalse(ClawScreenshotReviewScopePolicy.permits(message, for: selected))
    }
  }

  func testExplicitlyReviewedHumanScreenshotBubblesRemainEligible() {
    let selected = UUID()
    for speaker: ClawConversationSpeaker in [.me, .other] {
      let message = ClawConversationMessage(
        contactID: nil, speaker: speaker, content: "Confirmed human text",
        sourceType: "screenshot"
      )
      XCTAssertTrue(ClawScreenshotReviewScopePolicy.permits(message, for: selected))
    }
  }
}
