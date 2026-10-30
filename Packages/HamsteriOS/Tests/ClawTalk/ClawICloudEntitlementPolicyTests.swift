import CoreFoundation
import Foundation
import XCTest
@testable import HamsteriOS

final class ClawICloudEntitlementPolicyTests: XCTestCase {
  func testOnlyExplicitBooleanTrueAuthorizesCloudCopyAndRestore() {
    XCTAssertTrue(ClawICloudEntitlementPolicy.isAuthorized(NSNumber(value: true)))
    XCTAssertFalse(ClawICloudEntitlementPolicy.isAuthorized(NSNumber(value: false)))
    XCTAssertFalse(ClawICloudEntitlementPolicy.isAuthorized(nil))
    XCTAssertFalse(ClawICloudEntitlementPolicy.isAuthorized(NSNull()))
    XCTAssertFalse(ClawICloudEntitlementPolicy.isAuthorized("true"))
    XCTAssertFalse(ClawICloudEntitlementPolicy.isAuthorized(NSNumber(value: 1)))
  }
}
