import Foundation
import XCTest
@testable import HamsterKit

/// P0: passive input collection must never be enabled by absence or malformed consent.
final class ClawTalkPrivacyDefaultDenyTests: XCTestCase {
  private func defaults() throws -> (UserDefaults, String) {
    let suite = "claw-privacy-optin-\(UUID().uuidString)"
    return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
  }

  func testFreshInstallDoesNotCollectUntilExplicitOptIn() throws {
    let (storage, suite) = try defaults()
    defer { storage.removePersistentDomain(forName: suite) }
    let privacy = ClawTalkPrivacyService(defaults: storage)
    XCTAssertFalse(privacy.isCollectionEnabled)
    privacy.isCollectionEnabled = true
    XCTAssertTrue(privacy.isCollectionEnabled)
    privacy.isCollectionEnabled = false
    XCTAssertFalse(privacy.isCollectionEnabled)
  }

  func testMalformedCurrentValuesCannotGrantCollection() throws {
    let (storage, suite) = try defaults()
    defer { storage.removePersistentDomain(forName: suite) }
    let privacy = ClawTalkPrivacyService(defaults: storage)
    storage.set(1, forKey: "clawTalk_collection_enabled")
    XCTAssertFalse(privacy.isCollectionEnabled)
    storage.set("true", forKey: "clawTalk_collection_enabled")
    XCTAssertFalse(privacy.isCollectionEnabled)
  }

  func testLegacyNumericConsentCannotSilentlyEnableCollection() throws {
    let (storage, suite) = try defaults()
    defer { storage.removePersistentDomain(forName: suite) }
    storage.set(1, forKey: "guru_collection_enabled")
    let privacy = ClawTalkPrivacyService(defaults: storage)
    XCTAssertFalse(privacy.isCollectionEnabled)
    XCTAssertNil(storage.object(forKey: "guru_collection_enabled"))
  }

  func testLegacyExplicitBooleanOptInIsPreserved() throws {
    let (storage, suite) = try defaults()
    defer { storage.removePersistentDomain(forName: suite) }
    storage.set(true, forKey: "guru_collection_enabled")
    let privacy = ClawTalkPrivacyService(defaults: storage)
    XCTAssertTrue(privacy.isCollectionEnabled)
  }
}
