import CoreFoundation
import Foundation
import XCTest
@testable import HamsterKit

final class ClawSignedCloudEntitlementTests: XCTestCase {
  func testExplicitCLAWContainerIsResolvedOnlyWithBooleanCapability() {
    var requestedIdentifiers: [String] = []
    let gate = ClawICloudAccessGate(
      readCapability: { true },
      resolveContainer: { identifier in
        requestedIdentifiers.append(identifier)
        return URL(fileURLWithPath: "/tmp/claw-icloud")
      }
    )
    XCTAssertEqual(gate.documentsURL()?.lastPathComponent, "Documents")
    XCTAssertEqual(requestedIdentifiers, [HamsterConstants.iCloudID])
  }

  func testAbsentOrNonBooleanCapabilityNeverResolvesCloudContainer() {
    for marker: Any? in [nil, false, "true", NSNumber(value: 1)] {
      var attempted = false
      let gate = ClawICloudAccessGate(
        readCapability: { marker },
        resolveContainer: { _ in
          attempted = true
          return URL(fileURLWithPath: "/tmp/unexpected")
        }
      )
      XCTAssertNil(gate.documentsURL())
      XCTAssertFalse(attempted)
    }
  }

  func testMissingExplicitContainerCannotFallbackToDefault() {
    var requestedIdentifiers: [String] = []
    let gate = ClawICloudAccessGate(
      readCapability: { true },
      resolveContainer: { identifier in
        requestedIdentifiers.append(identifier)
        return nil
      }
    )
    XCTAssertNil(gate.documentsURL())
    XCTAssertEqual(requestedIdentifiers, [HamsterConstants.iCloudID])
  }
}
