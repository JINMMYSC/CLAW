import XCTest
@testable import HamsterKit

/// OCR titles and blank profile aliases are untrusted input. Tests use only
/// in-memory fixtures and never write real contacts or App Group preferences.
final class ClawContactIdentityUnverifiedTitleFallbackTests: XCTestCase {
  func testBlankNameAndAliasesNeverMatchAnEmptyOCRTitle() {
    let unnamed = HeartTargetProfile(name: "", aliases: ["", "  "])
    XCTAssertFalse(unnamed.matches(displayTitle: ""))
    XCTAssertFalse(unnamed.matches(displayTitle: "  \n  "))
  }

  func testUnverifiedTitlesRequireReviewInsteadOfResolvingAContact() {
    let contact = HeartTargetProfile(name: "已知联系人")
    let resolver = ClawContactIdentityResolver(profilesProvider: { [contact] })
    for title: String? in [nil, "微信", "  "] {
      let result = resolver.resolve(displayTitle: title, allowCreate: false)
      XCTAssertNil(result.profile, "unverified OCR title must not select a person")
      XCTAssertFalse(result.created)
    }
  }

  func testExactKnownNameStillResolvesInPreviewWithoutCreatingProfile() {
    let contact = HeartTargetProfile(name: "已知联系人")
    let resolver = ClawContactIdentityResolver(profilesProvider: { [contact] })
    let result = resolver.resolve(displayTitle: contact.name, allowCreate: false)
    XCTAssertEqual(result.profile?.id, contact.id)
    XCTAssertFalse(result.created)
    XCTAssertEqual(result.reason, "name-or-alias")
  }
}
