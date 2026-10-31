import Foundation
import XCTest
@testable import HamsterKit

/// OCR preview must never silently select a different private contact.
final class ClawContactIdentityConflictPrivacyTests: XCTestCase {
  func testAvatarFingerprintCannotOverrideConflictingExactTitle() {
    let avatarPerson = HeartTargetProfile(name: "Alice", avatarFingerprint: "avatar-alice")
    let titlePerson = HeartTargetProfile(name: "Bob")
    let resolver = ClawContactIdentityResolver(profilesProvider: { [avatarPerson, titlePerson] })

    let result = resolver.resolve(
      displayTitle: "Bob",
      avatarFingerprint: "avatar-alice",
      allowCreate: false
    )
    XCTAssertNil(result.profile)
    XCTAssertFalse(result.created)
    XCTAssertEqual(result.reason, "avatar-title-conflict")
  }

  func testFuzzyOCRTitleRequiresManualPersonSelection() {
    let person = HeartTargetProfile(name: "Private Contact")
    let resolver = ClawContactIdentityResolver(profilesProvider: { [person] })

    let result = resolver.resolve(displayTitle: "Private", allowCreate: false)
    XCTAssertNil(result.profile)
    XCTAssertFalse(result.created)
    XCTAssertEqual(result.reason, "fuzzy-title-requires-review")
  }
}
