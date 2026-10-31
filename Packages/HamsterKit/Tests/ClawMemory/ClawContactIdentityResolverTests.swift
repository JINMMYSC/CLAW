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

  // OCR preview-only resolution must not treat a machine-created or group
  // profile as a confirmed person, even if its title matches exactly.
  func testPreviewOnlyExactNameRejectsAutoCreatedProfile() {
    let unconfirmed = HeartTargetProfile(name: "未确认OCR对象", autoCreated: true)
    let result = ClawContactIdentityResolver(profilesProvider: { [unconfirmed] })
      .resolve(displayTitle: "未确认OCR对象", allowCreate: false)
    XCTAssertNil(result.profile)
    XCTAssertFalse(result.created)
  }

  func testPreviewOnlyExactNameRejectsGroupProfile() {
    let group = HeartTargetProfile(name: "群聊示例", isGroup: true)
    let result = ClawContactIdentityResolver(profilesProvider: { [group] })
      .resolve(displayTitle: "群聊示例", allowCreate: false)
    XCTAssertNil(result.profile)
    XCTAssertFalse(result.created)
  }

  func testPreviewOnlyAvatarMatchRejectsUnconfirmedProfile() {
    let unconfirmed = HeartTargetProfile(
      name: "未确认头像对象", autoCreated: true, avatarFingerprint: "ocr-avatar-fixture"
    )
    let result = ClawContactIdentityResolver(profilesProvider: { [unconfirmed] })
      .resolve(displayTitle: "未确认头像对象",
               avatarFingerprint: "ocr-avatar-fixture", allowCreate: false)
    XCTAssertNil(result.profile)
    XCTAssertFalse(result.created)
  }

  func testPreviewOnlyConfirmedIndividualStillResolves() {
    let confirmed = HeartTargetProfile(name: "已确认人物")
    let result = ClawContactIdentityResolver(profilesProvider: { [confirmed] })
      .resolve(displayTitle: "已确认人物", allowCreate: false)
    XCTAssertEqual(result.profile?.id, confirmed.id)
  }
}
