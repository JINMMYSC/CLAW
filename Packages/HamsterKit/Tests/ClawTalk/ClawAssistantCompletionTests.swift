import XCTest
@testable import HamsterKit

final class ClawAssistantCompletionTests: XCTestCase {
  func testConversationGroupingAndSearchStayInsideCurrentContext() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = Date(timeIntervalSince1970: 1_800_000_000)
    let messages = [
      ClawChatMessage(role: "user", content: "项目方案", date: day),
      ClawChatMessage(role: "assistant", content: "收到", date: day.addingTimeInterval(60)),
      ClawChatMessage(role: "user", content: "买咖啡", date: day.addingTimeInterval(86_400)),
    ]

    XCTAssertEqual(ClawConversationPresentation.group(messages, calendar: calendar).count, 2)
    XCTAssertEqual(ClawConversationPresentation.search(messages, query: "方案").map(\.content), ["项目方案"])
  }

  func testQuickPromptsPersistAndCanBeReordered() {
    let suite = "quick-prompts-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = ClawQuickPromptStore(defaults: defaults, key: "test")

    store.replace(["提醒我今天的待办", "帮我总结"])
    store.move(from: 1, to: 0)

    XCTAssertEqual(ClawQuickPromptStore(defaults: defaults, key: "test").prompts, ["帮我总结", "提醒我今天的待办"])
  }

  func testVoiceGestureCancelsWhenFingerSlidesUp() {
    var gesture = ClawVoiceGestureState()
    gesture.begin()
    gesture.update(verticalTranslation: -72)
    XCTAssertEqual(gesture.finish(), .cancel)

    gesture.begin()
    gesture.update(verticalTranslation: -10)
    XCTAssertEqual(gesture.finish(), .submit)
  }
}
