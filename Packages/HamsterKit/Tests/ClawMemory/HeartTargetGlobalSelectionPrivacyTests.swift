import Foundation
import XCTest
@testable import HamsterKit

/// Adding a contact must not silently switch the keyboard out of global mode.
final class HeartTargetGlobalSelectionPrivacyTests: XCTestCase {
  private func isolatedService() -> (HeartTargetService, UserDefaults, String) {
    let suite = "claw-heart-global-mode-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    return (HeartTargetService(defaults: defaults), defaults, suite)
  }

  func testFirstContactCreationPreservesExplicitGlobalMode() {
    let (service, defaults, suite) = isolatedService()
    defer { defaults.removePersistentDomain(forName: suite) }
    service.clearSelection()
    XCTAssertNil(service.selectedProfile)

    let person = service.upsert(HeartTargetProfile(name: "Private person"))
    XCTAssertNotNil(service.profile(id: person.id))
    XCTAssertNil(service.selectedProfile, "Creating a contact must not select it without user action")
  }

  func testExplicitSelectionStillWorksAfterAddingContact() {
    let (service, defaults, suite) = isolatedService()
    defer { defaults.removePersistentDomain(forName: suite) }
    service.clearSelection()
    let person = service.upsert(HeartTargetProfile(name: "Explicitly selected"))
    service.select(id: person.id)
    XCTAssertEqual(service.selectedProfile?.id, person.id)
  }

  func testAddingSecondContactAfterClearSelectionPreservesGlobalMode() {
    let (service, defaults, suite) = isolatedService()
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = service.upsert(HeartTargetProfile(name: "First person"))
    service.select(id: first.id)
    service.clearSelection()
    XCTAssertNil(service.selectedProfile)

    let second = service.upsert(HeartTargetProfile(name: "Second person"))
    XCTAssertNotNil(service.profile(id: first.id))
    XCTAssertNotNil(service.profile(id: second.id))
    XCTAssertNil(service.selectedProfile, "Adding another person must not reactivate an old private context")
  }
}
