import Foundation
import HamsterKit
@testable import HamsteriOS
import XCTest

final class ClawPeopleWorkflowTests: XCTestCase {
  func testSearchMatchesPinyinInitialsAndAlias() {
    let wang = HeartTargetProfile(name: "王小明", aliases: ["老王"])
    let li = HeartTargetProfile(name: "李雷")

    XCTAssertEqual(ClawPeoplePresentation.filtered([wang, li], query: "wxm", filter: .all).map(\.id), [wang.id])
    XCTAssertEqual(ClawPeoplePresentation.filtered([wang, li], query: "老王", filter: .all).map(\.id), [wang.id])
  }

  func testFiltersGroupsAndSortsByRecentInteraction() {
    let old = HeartTargetProfile(name: "旧联系人", lastSeenAt: Date(timeIntervalSince1970: 100))
    let recentGroup = HeartTargetProfile(name: "项目群", isGroup: true, lastSeenAt: Date(timeIntervalSince1970: 300))
    let recentPerson = HeartTargetProfile(name: "新联系人", lastSeenAt: Date(timeIntervalSince1970: 200))

    XCTAssertEqual(
      ClawPeoplePresentation.filtered([old, recentGroup, recentPerson], query: "", filter: .all).map(\.id),
      [recentGroup.id, recentPerson.id, old.id]
    )
    XCTAssertEqual(
      ClawPeoplePresentation.filtered([old, recentGroup, recentPerson], query: "", filter: .groups).map(\.id),
      [recentGroup.id]
    )
  }
}
