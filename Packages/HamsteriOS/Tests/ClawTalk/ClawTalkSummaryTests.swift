import Foundation
import HamsterKit
@testable import HamsteriOS
import XCTest

final class ClawTalkSummaryTests: XCTestCase {
  func testCountsTodayInputAndClipboardEntriesAndUsesLatestCollectionTime() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = date(2026, 10, 7, 12, 0, calendar: calendar)
    let latest = date(2026, 10, 7, 11, 45, calendar: calendar)

    let inputEntries = [
      ClawTalkEntry(startTime: date(2026, 10, 7, 8, 0, calendar: calendar), text: "today", context: nil, appContext: "test"),
      ClawTalkEntry(startTime: date(2026, 10, 6, 23, 59, calendar: calendar), text: "yesterday", context: nil, appContext: "test"),
    ]
    let clipboardEntries = [
      ClipboardEntry(timestamp: latest, content: "latest", contentType: .text),
      ClipboardEntry(timestamp: date(2026, 10, 8, 0, 1, calendar: calendar), content: "tomorrow", contentType: .text),
    ]

    let summary = ClawTalkSummary.make(
      inputEntries: inputEntries,
      clipboardEntries: clipboardEntries,
      now: now,
      calendar: calendar
    )

    XCTAssertEqual(summary.todayInputCount, 2)
    XCTAssertEqual(summary.latestCollectionTime, latest)
  }

  func testEmptyTodayHasNoLatestCollectionTime() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = date(2026, 10, 7, 12, 0, calendar: calendar)

    let summary = ClawTalkSummary.make(
      inputEntries: [
        ClawTalkEntry(startTime: date(2026, 10, 6, 12, 0, calendar: calendar), text: "old", context: nil, appContext: "test"),
      ],
      clipboardEntries: [],
      now: now,
      calendar: calendar
    )

    XCTAssertEqual(summary.todayInputCount, 0)
    XCTAssertNil(summary.latestCollectionTime)
  }

  private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    _ minute: Int,
    calendar: Calendar
  ) -> Date {
    calendar.date(from: DateComponents(
      timeZone: calendar.timeZone,
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute
    ))!
  }
}
