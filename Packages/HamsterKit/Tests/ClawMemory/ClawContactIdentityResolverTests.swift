import XCTest
@testable import HamsterKit

final class ClawContactIdentityResolverTests: XCTestCase {
  func testDuplicateAliasRequiresReviewRatherThanChoosingFirstContact() {
    let first = HeartTargetProfile(name: "王一", aliases: ["小王"])
    let second = HeartTargetProfile(name: "王二", aliases: ["小王"])
    let resolver = ClawContactIdentityResolver(profilesProvider: { [first, second] })
    let result = resolver.resolve(displayTitle: "小王", allowCreate: false)
    XCTAssertNil(result.profile)
    XCTAssertFalse(result.created)
    XCTAssertEqual(result.reason, "ambiguous-name-or-alias")
  }

  func testExactNameConflictingWithAnotherPersonsAliasRemainsAmbiguous() {
    let first = HeartTargetProfile(name: "小王")
    let second = HeartTargetProfile(name: "王二", aliases: ["小王"])
    let result = ClawContactIdentityResolver(profilesProvider: { [first, second] })
      .resolve(displayTitle: "小王", allowCreate: false)
    XCTAssertNil(result.profile)
    XCTAssertEqual(result.reason, "ambiguous-name-or-alias")
  }

  func testDuplicateAvatarFingerprintCannotOverrideAmbiguousName() {
    let first = HeartTargetProfile(name: "甲", avatarFingerprint: "same-image")
    let second = HeartTargetProfile(name: "乙", avatarFingerprint: "same-image")
    let result = ClawContactIdentityResolver(profilesProvider: { [first, second] })
      .resolve(displayTitle: "甲", avatarFingerprint: "same-image", allowCreate: false)
    XCTAssertNil(result.profile)
    XCTAssertEqual(result.reason, "ambiguous-avatar")
  }

  func testUniqueAliasStillResolvesWithoutMutatingContacts() {
    let first = HeartTargetProfile(name: "王一", aliases: ["小王"])
    let second = HeartTargetProfile(name: "王二", aliases: ["老王"])
    let beforeSelection = HeartTargetService.shared.selectedProfile?.id
    let resolver = ClawContactIdentityResolver(profilesProvider: { [first, second] })
    let result = resolver.resolve(displayTitle: "小王", allowCreate: false)
    XCTAssertEqual(result.profile?.id, first.id)
    XCTAssertEqual(result.reason, "name-or-alias")
    XCTAssertFalse(result.created)
    XCTAssertEqual(HeartTargetService.shared.selectedProfile?.id, beforeSelection)
  }
}
