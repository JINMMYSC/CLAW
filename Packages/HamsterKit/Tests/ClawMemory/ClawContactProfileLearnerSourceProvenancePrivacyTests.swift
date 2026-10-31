import Foundation
import XCTest
@testable import HamsterKit

final class ClawContactProfileLearnerSourceProvenancePrivacyTests: XCTestCase {
  func testGeneratedAndSystemProvenanceNeverBecomeHumanEvidenceEvenWithHumanSpeaker() {
    let contactID = UUID()
    let rows = [
      ClawConversationMessage(contactID: contactID, speaker: .other,
        content: "Model-authored impersonation", sourceType: "assistant"),
      ClawConversationMessage(contactID: contactID, speaker: .me,
        content: "System content mislabeled as user", sourceType: " SYSTEM "),
      ClawConversationMessage(contactID: contactID, speaker: .other,
        content: "AI-generated reply", sourceType: "AI-generated"),
      ClawConversationMessage(contactID: contactID, speaker: .other,
        content: "Real reviewed reply", sourceType: "screenshot"),
      ClawConversationMessage(contactID: contactID, speaker: .me,
        content: "Real user message", sourceType: "manual")
    ]

    let evidence = ClawContactProfileLearner.humanEvidence(from: rows)
    XCTAssertEqual(evidence.map(\.content), ["Real reviewed reply", "Real user message"])
  }

  func testGeneratedProvenanceCannotSatisfyProfileLearningThreshold() {
    let contactID = UUID()
    let rows = (0..<8).map { index in
      ClawConversationMessage(contactID: contactID, speaker: .other,
        content: "Synthetic reply \(index)", sourceType: "assistant")
    }
    XCTAssertTrue(ClawContactProfileLearner.humanEvidence(from: rows).isEmpty)
  }
  func testNamespacedGeneratedContentCannotImpersonateHumanContactEvidence() {
    let contactID = UUID()
    let generatedSources = [
      "generated:ocr", "generated/ocr", "generated.ocr",
      "generated-ocr", "generated_ocr", " generated : ocr "
    ]
    let rows = generatedSources.map { source in
      ClawConversationMessage(contactID: contactID, speaker: .other,
        content: "Unverified generated text", sourceType: source)
    }
    XCTAssertTrue(ClawContactProfileLearner.humanEvidence(from: rows).isEmpty)
  }

}
