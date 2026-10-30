import Foundation
import XCTest
@testable import HamsteriOS

final class ClawICloudCapabilityStampTests: XCTestCase {
  func testOnlyActualBooleanTrueEnablesCloudCopyAndRestore() {
    XCTAssertTrue(hasExplicitTrueBoolean(NSNumber(value: true)))
    XCTAssertFalse(hasExplicitTrueBoolean(NSNumber(value: false)))
    XCTAssertFalse(hasExplicitTrueBoolean(NSNumber(value: 1)))
    XCTAssertFalse(hasExplicitTrueBoolean(NSNumber(value: 0)))
    XCTAssertFalse(hasExplicitTrueBoolean("true"))
    XCTAssertFalse(hasExplicitTrueBoolean(nil))
  }
}
