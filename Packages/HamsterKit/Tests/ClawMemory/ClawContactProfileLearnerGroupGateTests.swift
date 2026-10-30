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
}
