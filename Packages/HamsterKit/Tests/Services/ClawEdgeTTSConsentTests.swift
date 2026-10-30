import XCTest
@testable import HamsterKit

final class ClawEdgeTTSConsentTests: XCTestCase {
  func testCloudTextUploadRequiresExplicitTrue() {
    XCTAssertFalse(ClawEdgeTTSConsentPolicy.permitsUpload(nil))
    XCTAssertFalse(ClawEdgeTTSConsentPolicy.permitsUpload(false))
    XCTAssertFalse(ClawEdgeTTSConsentPolicy.permitsUpload("true"))
    XCTAssertFalse(ClawEdgeTTSConsentPolicy.permitsUpload(1))
    XCTAssertTrue(ClawEdgeTTSConsentPolicy.permitsUpload(true))
  }
}
