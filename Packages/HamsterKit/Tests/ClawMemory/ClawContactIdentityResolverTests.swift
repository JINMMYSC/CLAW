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

  // An observed avatar that conflicts with a previously stored fingerprint
  // cannot silently attach screenshot text to a name or alias match.
  func testPreviewExactNameRejectsConflictingObservedAvatar() {
    let profile = HeartTargetProfile(name: "李四", avatarFingerprint: "saved-avatar")
    let result = ClawContactIdentityResolver(profilesProvider: { [profile] })
      .resolve(displayTitle: "李四", avatarFingerprint: "different-avatar", allowCreate: false)
    XCTAssertNil(result.profile)
    XCTAssertFalse(result.created)
    XCTAssertEqual(result.reason, "avatar-title-conflict")
  }

  func testPreviewAliasRejectsConflictingObservedAvatar() {
    let profile = HeartTargetProfile(
      name: "李四", aliases: ["阿四"], avatarFingerprint: "saved-avatar"
    )
    let result = ClawContactIdentityResolver(profilesProvider: { [profile] })
      .resolve(displayTitle: "阿四", avatarFingerprint: "different-avatar", allowCreate: false)
    XCTAssertNil(result.profile)
    XCTAssertEqual(result.reason, "avatar-title-conflict")
  }

  func testPreviewExactNameAllowsObservedAvatarWhenNoStoredFingerprint() {
    let profile = HeartTargetProfile(name: "李四")
    let result = ClawContactIdentityResolver(profilesProvider: { [profile] })
      .resolve(displayTitle: "李四", avatarFingerprint: "new-avatar", allowCreate: false)
    XCTAssertEqual(result.profile?.id, profile.id)
  }

  func testPreviewExactNameAllowsMatchingStoredAvatar() {
    let profile = HeartTargetProfile(name: "李四", avatarFingerprint: "same-avatar")
    let result = ClawContactIdentityResolver(profilesProvider: { [profile] })
      .resolve(displayTitle: "李四", avatarFingerprint: "same-avatar", allowCreate: false)
    XCTAssertEqual(result.profile?.id, profile.id)
  }

  // A resolver-created suggestion is not an explicit request to switch the
  // keyboard from global memory into one person's private context.
  func testAutoCreatedResolverProfilePreservesGlobalMode() {
    let service = HeartTargetService.shared
    let previouslySelectedID = service.selectedProfile?.id
    service.clearSelection()
    let title = "AutoGlobal" + String(UUID().uuidString.prefix(8))
    let result = ClawContactIdentityResolver.shared.resolve(
      displayTitle: title, allowCreate: true
    )
    defer {
      if let id = result.profile?.id { service.delete(id: id) }
      if let previouslySelectedID {
        service.select(id: previouslySelectedID)
      } else {
        service.clearSelection()
      }
    }
    XCTAssertTrue(result.created)
    XCTAssertNotNil(result.profile)
    XCTAssertNil(service.selectedProfile,
                 "An OCR-created profile must not activate private keyboard context")
  }
}
