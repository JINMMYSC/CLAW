import Foundation
import XCTest
@testable import HamsterKit

/// P0: learning a person's private chat history requires per-contact opt-in.
final class ClawContactProfileLearningConsentGateTests: XCTestCase {
  func testAbsentMalformedAndLegacyNumericConsentCannotAuthorizeLearning() {
    let suite = "claw-profile-consent-tests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
      XCTFail("Unable to create isolated test defaults")
      return
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    let consent = ClawContactProfileLearningConsentStore(defaults: defaults)
    let contactID = UUID()
    let key = "claw_contact_profile_learning_consent_" + contactID.uuidString.lowercased()

    XCTAssertFalse(consent.isGranted(for: contactID))
    XCTAssertFalse(ClawContactProfileLearner.isAuthorizedForLearning(profileID: contactID, consentStore: consent))

    defaults.set(1, forKey: key)
    XCTAssertFalse(consent.isGranted(for: contactID))
    defaults.set("true", forKey: key)
    XCTAssertFalse(consent.isGranted(for: contactID))

    consent.setGranted(true, for: contactID)
    XCTAssertTrue(consent.isGranted(for: contactID))
    XCTAssertTrue(ClawContactProfileLearner.isAuthorizedForLearning(profileID: contactID, consentStore: consent))
  }

  func testRevocationInvalidatesInFlightConsentSession() {
    let suite = "claw-profile-consent-session-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
      XCTFail("Unable to create isolated test defaults")
      return
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    let consent = ClawContactProfileLearningConsentStore(defaults: defaults)
    let contactID = UUID()

    consent.setGranted(true, for: contactID)
    guard let oldToken = consent.authorizationToken(for: contactID) else {
      XCTFail("Expected a token after explicit opt-in")
      return
    }
    consent.setGranted(false, for: contactID)
    XCTAssertFalse(consent.isGranted(for: contactID))
    XCTAssertFalse(consent.performIfGranted(for: contactID, authorizationToken: oldToken) {})

    consent.setGranted(true, for: contactID)
    XCTAssertNotEqual(consent.authorizationToken(for: contactID), oldToken)
    XCTAssertFalse(consent.performIfGranted(for: contactID, authorizationToken: oldToken) {})
  }
}
