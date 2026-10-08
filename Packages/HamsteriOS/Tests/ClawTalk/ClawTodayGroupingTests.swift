import Foundation
import HamsterKit
@testable import HamsteriOS
import XCTest

final class ClawTodayGroupingTests: XCTestCase {
  func testGroupsOpenTasksIntoFourStableSections() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12))!
    let tasks = [
      task("overdue", dueAt: now.addingTimeInterval(-24 * 3600)),
      task("today", dueAt: now.addingTimeInterval(3600)),
      task("upcoming", dueAt: now.addingTimeInterval(24 * 3600)),
      task("unscheduled", dueAt: nil),
    ]

    let groups = ClawTodayTaskGrouping.group(tasks, now: now, calendar: calendar)

    XCTAssertEqual(groups[.overdue]?.map(\.title), ["overdue"])
    XCTAssertEqual(groups[.today]?.map(\.title), ["today"])
    XCTAssertEqual(groups[.upcoming]?.map(\.title), ["upcoming"])
    XCTAssertEqual(groups[.unscheduled]?.map(\.title), ["unscheduled"])
  }

  func testSortsEachGroupByDueDateThenCreationDate() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let later = task("later", dueAt: now.addingTimeInterval(7200), createdAt: now)
    let sooner = task("sooner", dueAt: now.addingTimeInterval(3600), createdAt: now.addingTimeInterval(10))

    let groups = ClawTodayTaskGrouping.group([later, sooner], now: now)

    XCTAssertEqual(groups[.today]?.map(\.title), ["sooner", "later"])
  }

  private func task(_ title: String, dueAt: Date?, createdAt: Date = .distantPast) -> ClawSecretaryTask {
    ClawSecretaryTask(title: title, dueAt: dueAt, createdAt: createdAt, sourceType: "manual")
  }
}
