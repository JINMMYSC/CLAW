import XCTest
@testable import HamsterKit

final class ClawContactProfileLearnerGroupGateTests: XCTestCase {
  func testGroupCannotBeLearnedAsAnIndividualProfile() {
    XCTAssertFalse(ClawContactProfileLearner.isEligibleForIndividualLearning(
      HeartTargetProfile(name: "Project group", isGroup: true)
    ))
    XCTAssertTrue(ClawContactProfileLearner.isEligibleForIndividualLearning(
      HeartTargetProfile(name: "Contact", isGroup: false)
    ))
  }

  func testUnconfirmedAutoCreatedContactCannotBeLearnedAsAnIndividualProfile() {
    let unconfirmed = HeartTargetProfile(
      name: "OCR-only unconfirmed contact", autoCreated: true, isGroup: false
    )
    XCTAssertFalse(ClawContactProfileLearner.isEligibleForIndividualLearning(unconfirmed))
  }

  func testConfirmedIndividualContactRemainsEligibleForLearning() {
    let confirmed = HeartTargetProfile(
      name: "Confirmed contact", autoCreated: false, isGroup: false
    )
    XCTAssertTrue(ClawContactProfileLearner.isEligibleForIndividualLearning(confirmed))
  }
}
