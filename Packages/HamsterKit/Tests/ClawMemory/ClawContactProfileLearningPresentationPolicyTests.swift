import XCTest
@testable import HamsterKit

final class ClawContactProfileLearningPresentationPolicyTests: XCTestCase {
  func testUnconfirmedContactCannotGrantProfileLearning() {
    XCTAssertFalse(ClawContactProfileLearningPresentationPolicy.canSetConsent(
      to: true, isGroup: false, isConfirmed: false
    ))
  }

  func testGroupCannotGrantProfileLearning() {
    XCTAssertFalse(ClawContactProfileLearningPresentationPolicy.canSetConsent(
      to: true, isGroup: true, isConfirmed: true
    ))
  }

  func testConfirmedIndividualCanGrantProfileLearning() {
    XCTAssertTrue(ClawContactProfileLearningPresentationPolicy.canSetConsent(
      to: true, isGroup: false, isConfirmed: true
    ))
  }

  func testRevocationRemainsPossibleAfterContactBecomesGroupOrUnconfirmed() {
    XCTAssertTrue(ClawContactProfileLearningPresentationPolicy.canSetConsent(
      to: false, isGroup: true, isConfirmed: false
    ))
  }
}
