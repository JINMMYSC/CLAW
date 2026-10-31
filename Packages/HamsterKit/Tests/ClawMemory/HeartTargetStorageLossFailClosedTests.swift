import Foundation
import XCTest
@testable import HamsterKit

/// Loss or corruption of shared storage must not resurrect a cached private contact.
final class HeartTargetStorageLossFailClosedTests: XCTestCase {
  private func isolatedDefaults() -> (UserDefaults, String) {
    let suite = "claw-heart-storage-loss-\(UUID().uuidString)"
    return (UserDefaults(suiteName: suite)!, suite)
  }

  func testRemovedSharedProfileDataClearsCachedContactAndSelection() {
    let (defaults, suite) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = HeartTargetService(defaults: defaults)
    let contact = service.upsert(HeartTargetProfile(name: "Private contact"))
    service.select(id: contact.id)
    XCTAssertEqual(service.selectedProfile?.id, contact.id)

    defaults.removeObject(forKey: "heart_target_profiles")
    defaults.removeObject(forKey: "heart_target_selected")
    service.reload()

    XCTAssertTrue(service.profiles.isEmpty)
    XCTAssertEqual(service.selectedIndex, -1)
    XCTAssertNil(service.selectedProfile)
    XCTAssertNil(service.profile(id: contact.id))
  }

  func testMalformedSharedProfileDataCannotLeavePrivateContactCached() {
    let (defaults, suite) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = HeartTargetService(defaults: defaults)
    let contact = service.upsert(HeartTargetProfile(name: "Private contact"))
    service.select(id: contact.id)

    defaults.set(Data("invalid-json".utf8), forKey: "heart_target_profiles")
    service.reload()

    XCTAssertTrue(service.profiles.isEmpty)
    XCTAssertEqual(service.selectedIndex, -1)
    XCTAssertNil(service.selectedProfile)
    XCTAssertNil(service.profile(id: contact.id))
  }
}
