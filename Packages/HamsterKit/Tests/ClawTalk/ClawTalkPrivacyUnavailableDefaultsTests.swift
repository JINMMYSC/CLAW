import Foundation
import XCTest
@testable import HamsterKit

/// The keyboard must never claim input collection is enabled without shared storage.
final class ClawTalkPrivacyUnavailableDefaultsTests: XCTestCase {
  func testToggleFailsClosedWhenAppGroupDefaultsAreUnavailable() {
    let service = ClawTalkPrivacyService(defaults: nil)

    XCTAssertFalse(service.toggle())
    XCTAssertFalse(service.isCollectionEnabled)
  }
}
