import Foundation
import XCTest
@testable import HamsterKit

final class ClawSignedCloudEntitlementTests: XCTestCase {
  func testCloudDocumentsCannotBeAuthorizedWithoutSignedServicesAndContainer() {
    let expected = "iCloud.dev.fuxiao.app.hamsterapp"
    XCTAssertFalse(ClawRuntimeCapabilityInspector.cloudDocumentsEntitlement(
      services: nil, containers: [expected], expectedContainer: expected
    ))
    XCTAssertFalse(ClawRuntimeCapabilityInspector.cloudDocumentsEntitlement(
      services: ["CloudDocuments"], containers: nil, expectedContainer: expected
    ))
    XCTAssertFalse(ClawRuntimeCapabilityInspector.cloudDocumentsEntitlement(
      services: ["CloudKit"], containers: [expected], expectedContainer: expected
    ))
    XCTAssertFalse(ClawRuntimeCapabilityInspector.cloudDocumentsEntitlement(
      services: ["CloudDocuments"], containers: ["iCloud.other.container"], expectedContainer: expected
    ))
    XCTAssertTrue(ClawRuntimeCapabilityInspector.cloudDocumentsEntitlement(
      services: ["CloudDocuments", "CloudKit"], containers: [expected], expectedContainer: expected
    ))
  }
}
