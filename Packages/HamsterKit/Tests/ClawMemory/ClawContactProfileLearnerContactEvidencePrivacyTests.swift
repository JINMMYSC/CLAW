import Foundation
import XCTest
@testable import HamsterKit

final class ClawContactProfileLearnerContactEvidencePrivacyTests: XCTestCase {
  func testSelfOnlyMessagesCannotTriggerLearningAboutAnotherPerson() {
    let contactID = UUID()
    let rows = (0..<6).map { index in
      ClawConversationMessage(contactID: contactID, speaker: .me,
        content: "My own statement \(index)", sourceType: "manual")
    }
    let evidence = ClawContactProfileLearner.humanEvidence(from: rows)

    XCTAssertFalse(ClawContactProfileLearner.hasSufficientContactEvidence(
      evidence, minimumMessages: 6))
  }

  func testAtLeastTwoRealContactRepliesAreRequiredWithSixTotalMessages() {
    let contactID = UUID()
    let selfMessages = (0..<4).map { index in
      ClawConversationMessage(contactID: contactID, speaker: .me,
        content: "My statement \(index)", sourceType: "manual")
    }
    let contactMessages = (0..<2).map { index in
      ClawConversationMessage(contactID: contactID, speaker: .other,
        content: "Contact reply \(index)", sourceType: "manual")
    }

    let validEvidence = ClawContactProfileLearner.humanEvidence(from: selfMessages + contactMessages)
    XCTAssertTrue(ClawContactProfileLearner.hasSufficientContactEvidence(
      validEvidence, minimumMessages: 6))

    let insufficientContactEvidence = ClawContactProfileLearner.humanEvidence(from:
      selfMessages + [selfMessages[0], contactMessages[0]])
    XCTAssertFalse(ClawContactProfileLearner.hasSufficientContactEvidence(
      insufficientContactEvidence, minimumMessages: 6))
  }
}
