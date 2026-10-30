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

  func testInterruptedHostRequestCanRecoverWithoutReplacingActiveRecording() {
    let (handoff, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }
    // Use a relative clock: complete() and dismissFailure() validate against Date().
    let started = Date().addingTimeInterval(-181)
    let id = handoff.begin(at: started)
    XCTAssertFalse(handoff.failStalePending(olderThan: 180, at: started.addingTimeInterval(179)))
    XCTAssertEqual(handoff.snapshot(at: started.addingTimeInterval(179)).state, .pending)
    XCTAssertTrue(handoff.failStalePending(olderThan: 180, at: started.addingTimeInterval(181)))
    let state = handoff.snapshot(at: started.addingTimeInterval(181))
    XCTAssertEqual(state.state, .failed)
    XCTAssertEqual(state.id, id)
    XCTAssertFalse(handoff.complete(id: id, text: "迟到的结果"))
    XCTAssertNil(handoff.beginIfIdle(at: started.addingTimeInterval(182)))
    handoff.dismissFailure()
    XCTAssertEqual(handoff.snapshot.state, .idle)
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


  func testUnavailableAppGroupRejectsRecordingAndNeverWritesFallbackTranscript() {
    let suite = "claw-voice-unavailable-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let unavailable = ClawVoiceDictationHandoff(defaults: defaults, isSharedAvailable: false)

    XCTAssertNil(unavailable.beginIfIdle(), "A keyboard without its App Group must not start a recorder")
    let id = unavailable.begin()
    XCTAssertEqual(unavailable.snapshot.state, .idle)
    XCTAssertFalse(unavailable.complete(id: id, text: "不可跨进程传递的语音"))
    XCTAssertFalse(unavailable.fail(id: id, reason: "共享容器不可用"))
    XCTAssertNil(defaults.data(forKey: "claw_voice_dictation_handoff_v1"))
  }

  func testUnavailableAppGroupClearsPreviouslyPersistedLegacyFallbackText() {
    let suite = "claw-voice-legacy-fallback-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let legacy = ClawVoiceDictationHandoff(defaults: defaults)
    let id = legacy.begin()
    XCTAssertTrue(legacy.complete(id: id, text: "历史残留转写"))

    let unavailable = ClawVoiceDictationHandoff(defaults: defaults, isSharedAvailable: false)
    XCTAssertEqual(unavailable.snapshot.state, .idle)
    XCTAssertNil(unavailable.consume())
    XCTAssertNil(defaults.data(forKey: "claw_voice_dictation_handoff_v1"))
  }


  func testCorruptSharedHandoffRecordIsPurgedBeforeAnotherRequest() {
    let (handoff, defaults, suite) = makeStore()
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "claw_voice_dictation_handoff_v1"
    // A partial record may retain private dictation text even when decoding fails.
    defaults.set(Data(#"{"text":"private transcript","state":"ready"}"#.utf8), forKey: key)
    XCTAssertEqual(handoff.snapshot.state, .idle)
    XCTAssertNil(defaults.data(forKey: key), "Unreadable transcript bytes must not remain in App Group defaults")
    XCTAssertNotNil(handoff.beginIfIdle())
  }

}
