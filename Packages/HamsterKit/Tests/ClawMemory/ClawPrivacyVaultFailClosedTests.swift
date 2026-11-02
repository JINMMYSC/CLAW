import XCTest
@testable import HamsterKit

final class ClawPrivacyVaultFailClosedTests: XCTestCase {
  func testMalformedProtectedMemoryIndexNeverMakesMemoriesVisibleToAI() {
    let key = "claw_privacy_vault_memory_ids_v1"
    guard let defaults = UserDefaults(suiteName: HamsterConstants.appGroupName) else {
      XCTFail("App Group preferences unavailable in test environment")
      return
    }
    let previous = defaults.object(forKey: key)
    defer {
      if let previous {
        defaults.set(previous, forKey: key)
      } else {
        defaults.removeObject(forKey: key)
      }
      ClawPrivacyVaultService.shared.lockNow()
    }

    ClawPrivacyVaultService.shared.lockNow()
    defaults.set(["malformed-uuid"], forKey: key)
    let item = ClawMemoryItem(kind: .fact, content: "test-only", sourceType: "test")

    XCTAssertTrue(ClawPrivacyVaultService.shared.isProtected(item))
    XCTAssertFalse(ClawPrivacyVaultService.shared.isVisibleToAI(item))
  }
}
