import XCTest
@testable import HamsterKit

final class ClawVoiceDictationHandoffTests: XCTestCase {
  private func makeStore() -> (ClawVoiceDictationHandoff, UserDefaults, String) {
    let suite = "claw-voice-handoff-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    return (ClawVoiceDictationHandoff(defaults: defaults), defaults, suite)
  }

  func testHostToKeyboardResultRequiresMatchingRequestAndIsConsumedOnlyOnce() {
    let (store, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }
    let id = store.begin()
    XCTAssertEqual(store.snapshot.state, .pending)
    XCTAssertFalse(store.complete(id: UUID(), text: "错误请求"))
    XCTAssertTrue(store.complete(id: id, text: " 你好世界 "))
    XCTAssertEqual(store.snapshot.state, .ready)
    XCTAssertEqual(store.consume(), "你好世界")
    XCTAssertNil(store.consume())
    XCTAssertEqual(store.snapshot.state, .idle)
  }

  func testExpiredAndCancelledDictationMustNotInsertText() {
    let (store, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }
    let id = store.begin(at: Date(timeIntervalSince1970: 100))
    XCTAssertEqual(store.snapshot(at: Date(timeIntervalSince1970: 701)).state, .idle)
    XCTAssertFalse(store.complete(id: id, text: "过期"))

    let second = store.begin()
    store.cancel(id: second)
    XCTAssertFalse(store.complete(id: second, text: "取消以后"))
    XCTAssertNil(store.consume())
  }

  func testFailedResultShowsFailureInsteadOfInsertingIntoKeyboard() {
    let (store, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }
    let id = store.begin()
    XCTAssertTrue(store.fail(id: id, reason: "语音权限未开启"))
    XCTAssertEqual(store.snapshot.state, .failed)
    XCTAssertEqual(store.snapshot.error, "语音权限未开启")
    XCTAssertNil(store.consume())
  }

  func testSecondProcessReadsSameAppGroupResultAndNewRequestInvalidatesOldOne() {
    let (keyboard, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }
    let host = ClawVoiceDictationHandoff(defaults: UserDefaults(suiteName: suite)!)
    let superseded = keyboard.begin()
    let current = keyboard.begin()
    XCTAssertFalse(host.complete(id: superseded, text: "旧任务"))
    XCTAssertTrue(host.complete(id: current, text: "新的语音文字"))
    XCTAssertEqual(keyboard.consume(), "新的语音文字")
    XCTAssertNil(host.consume())
  }

  func testRepeatedKeyboardMicTapDoesNotOverwriteRecordingRequest() {
    let (keyboard, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }
    let host = ClawVoiceDictationHandoff(defaults: UserDefaults(suiteName: suite)!)
    guard let first = keyboard.beginIfIdle() else {
      return XCTFail("An idle keyboard must be able to create a recording request")
    }
    XCTAssertNil(keyboard.beginIfIdle())
    XCTAssertEqual(host.snapshot.id, first)
    XCTAssertTrue(host.complete(id: first, text: "语音文字"))
    XCTAssertNil(keyboard.beginIfIdle())
    XCTAssertEqual(keyboard.consume(), "语音文字")
    XCTAssertNotNil(keyboard.beginIfIdle())
  }

}
