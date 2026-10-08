@testable import HamsterKit
import XCTest

final class SmartFreqMaintenancePolicyTests: XCTestCase {
  func testOnlySchedulesEnabledChargingWorkOutsideLowPowerMode() {
    let policy = SmartFreqMaintenancePolicy()
    XCTAssertTrue(policy.shouldSchedule(isEnabled: true, isLowPowerMode: false, hasExternalPower: true))
    XCTAssertFalse(policy.shouldSchedule(isEnabled: false, isLowPowerMode: false, hasExternalPower: true))
    XCTAssertFalse(policy.shouldSchedule(isEnabled: true, isLowPowerMode: true, hasExternalPower: true))
    XCTAssertFalse(policy.shouldSchedule(isEnabled: true, isLowPowerMode: false, hasExternalPower: false))
  }

  func testCleanupKeepsPinnedAndRecentObservedPhrasesWithinBudget() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func item(_ word: String, days: Double, count: Int, pinned: Bool = false) -> SmartFreqPhraseObservation {
      .init(
        phrase: .init(code: word.lowercased(), word: word, weight: 100),
        lastObservedAt: now.addingTimeInterval(-days * 86_400),
        observationCount: count,
        isPinned: pinned
      )
    }
    let retained = SmartFreqMaintenancePolicy(staleAfter: 30 * 86_400).retained([
      item("old", days: 100, count: 8),
      item("weak", days: 1, count: 1),
      item("recent", days: 2, count: 3),
      item("pinned", days: 200, count: 1, pinned: true),
    ], now: now, budget: 2)
    XCTAssertEqual(retained.map(\.phrase.word), ["pinned", "recent"])
  }
}
