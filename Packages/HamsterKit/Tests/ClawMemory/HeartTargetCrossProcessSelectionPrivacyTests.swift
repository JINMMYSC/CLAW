import Foundation
import XCTest
@testable import HamsterKit

final class HeartTargetCrossProcessSelectionPrivacyTests: XCTestCase {
  private func services() -> (HeartTargetService, HeartTargetService, UserDefaults, String) {
    let suite = "claw-heart-selection-\(UUID().uuidString)"
    let first = UserDefaults(suiteName: suite)!
    let second = UserDefaults(suiteName: suite)!
    return (HeartTargetService(defaults: first), HeartTargetService(defaults: second), first, suite)
  }

  func testOtherProcessDeletionRevokesCachedSelectedPerson() {
    let (writer, reader, defaults, suite) = services()
    defer { defaults.removePersistentDomain(forName: suite) }
    let person = writer.upsert(HeartTargetProfile(name: "Private"))
    writer.select(id: person.id)
    reader.reload()
    XCTAssertEqual(reader.selectedProfile?.id, person.id)

    writer.delete(id: person.id)
    XCTAssertNil(reader.selectedProfile)
  }

  func testStaleWriterDoesNotEraseOtherProcessContact() {
    let (first, stale, defaults, suite) = services()
    defer { defaults.removePersistentDomain(forName: suite) }
    let alice = first.upsert(HeartTargetProfile(name: "Alice"))
    let bob = stale.upsert(HeartTargetProfile(name: "Bob"))

    let fresh = HeartTargetService(defaults: defaults)
    XCTAssertNotNil(fresh.profile(id: alice.id))
    XCTAssertNotNil(fresh.profile(id: bob.id))
  }

  func testStaleDisplayedIndexDoesNotSelectReorderedStranger() throws {
    let (writer, reader, defaults, suite) = services()
    defer { defaults.removePersistentDomain(forName: suite) }
    let alice = writer.upsert(HeartTargetProfile(name: "Alice"))
    let bob = writer.upsert(HeartTargetProfile(name: "Bob"))
    reader.reload()

    defaults.set(try JSONEncoder().encode([bob, alice]), forKey: "heart_target_profiles")
    reader.select(at: 0)
    let fresh = HeartTargetService(defaults: defaults)
    XCTAssertEqual(fresh.selectedProfile?.id, alice.id)
    XCTAssertEqual(fresh.profiles.map(\.id), [bob.id, alice.id])
  }

  func testMissingSelectionKeyDoesNotImplicitlySelectFirstPerson() throws {
    let (writer, _, defaults, suite) = services()
    defer { defaults.removePersistentDomain(forName: suite) }
    let person = writer.upsert(HeartTargetProfile(name: "Private"))
    defaults.removeObject(forKey: "heart_target_selected")
    let fresh = HeartTargetService(defaults: defaults)
    XCTAssertNotNil(fresh.profile(id: person.id))
    XCTAssertNil(fresh.selectedProfile)
  }

  func testClearingStaleSelectionDoesNotEraseNewlySavedContact() {
    let (writer, reader, defaults, suite) = services()
    defer { defaults.removePersistentDomain(forName: suite) }
    let alice = writer.upsert(HeartTargetProfile(name: "Alice"))
    reader.reload()
    let bob = writer.upsert(HeartTargetProfile(name: "Bob"))

    reader.clearSelection()
    let fresh = HeartTargetService(defaults: defaults)
    XCTAssertNotNil(fresh.profile(id: alice.id))
    XCTAssertNotNil(fresh.profile(id: bob.id))
    XCTAssertNil(fresh.selectedProfile)
  }
}
