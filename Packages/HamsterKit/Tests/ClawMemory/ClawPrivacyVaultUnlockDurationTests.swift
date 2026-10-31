import Foundation
import XCTest
@testable import HamsterKit

final class ClawPrivacyVaultUnlockDurationTests: XCTestCase {
  func testUnlockDurationIsFiniteAndBoundedToFiveMinutes() {
    XCTAssertEqual(ClawPrivacyVaultService.boundedUnlockDuration(60 * 60), 5 * 60)
    XCTAssertEqual(ClawPrivacyVaultService.boundedUnlockDuration(.infinity), 5 * 60)
    XCTAssertEqual(ClawPrivacyVaultService.boundedUnlockDuration(.nan), 5 * 60)
    XCTAssertEqual(ClawPrivacyVaultService.boundedUnlockDuration(-1), 30)
    XCTAssertEqual(ClawPrivacyVaultService.boundedUnlockDuration(120), 120)
  }
}
