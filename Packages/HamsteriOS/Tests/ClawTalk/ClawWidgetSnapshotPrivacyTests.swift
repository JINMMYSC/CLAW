import Foundation
@testable import HamsteriOS
import XCTest

final class ClawWidgetSnapshotPrivacyTests: XCTestCase {
  func testWidgetSnapshotDoesNotExposePrivateTaskTitle() {
    let sensitiveTitle = "私人约谈与医疗事项"
    let snapshot = ClawWidgetSnapshot(
      generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
      summary: sensitiveTitle,
      openTaskCount: 2
    )

    // Home Screen and Lock Screen widgets must be safe by default.
    XCTAssertEqual(snapshot.summary, "打开 CLAW 查看今日")
    XCTAssertEqual(snapshot.openTaskCount, 2)
  }
}
