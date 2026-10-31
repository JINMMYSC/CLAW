import Foundation
import XCTest
@testable import HamsterKit

final class ClawVoiceHandoffRecordPrivacyTests: XCTestCase {
  private let key = "claw_voice_dictation_handoff_v1"

  private func makeStoredRecord(state: String, text: String) throws
    -> (ClawVoiceDictationHandoff, UserDefaults, String) {
    let suite = "claw-voice-record-privacy-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let record: [String: Any] = [
      "id": UUID().uuidString,
      "createdAt": Date().timeIntervalSinceReferenceDate,
      "state": state,
      "text": text,
    ]
    defaults.set(try JSONSerialization.data(withJSONObject: record), forKey: key)
    return (ClawVoiceDictationHandoff(defaults: defaults), defaults, suite)
  }

  func testFailedRecordWithTranscriptIsPurgedBeforeKeyboardSnapshot() throws {
    let (handoff, defaults, suite) = try makeStoredRecord(
      state: "failed", text: "private speech from an invalid failed record")
    defer { defaults.removePersistentDomain(forName: suite) }

    XCTAssertEqual(handoff.snapshot.state, .idle)
    XCTAssertNil(handoff.snapshot.text)
    XCTAssertNil(handoff.snapshot.error)
    XCTAssertNil(defaults.data(forKey: key))
  }

  func testIdleRecordWithTranscriptIsPurgedBeforeKeyboardSnapshot() throws {
    let (handoff, defaults, suite) = try makeStoredRecord(
      state: "idle", text: "private speech from an invalid idle record")
    defer { defaults.removePersistentDomain(forName: suite) }

    XCTAssertEqual(handoff.snapshot.state, .idle)
    XCTAssertNil(handoff.snapshot.text)
    XCTAssertNil(defaults.data(forKey: key))
  }

  func testPendingRecordWithTranscriptIsPurgedBeforeKeyboardSnapshot() throws {
    let (handoff, defaults, suite) = try makeStoredRecord(
      state: "pending", text: "private transcript must not appear")
    defer { defaults.removePersistentDomain(forName: suite) }

    let snapshot = handoff.snapshot
    XCTAssertEqual(snapshot.state, .idle)
    XCTAssertNil(snapshot.text)
    XCTAssertNil(defaults.data(forKey: key))
  }

  func testReadyRecordWithWhitespaceTranscriptIsPurgedBeforeConsume() throws {
    let (handoff, defaults, suite) = try makeStoredRecord(
      state: "ready", text: "   \n  ")
    defer { defaults.removePersistentDomain(forName: suite) }

    XCTAssertEqual(handoff.snapshot.state, .idle)
    XCTAssertNil(handoff.consume())
    XCTAssertNil(defaults.data(forKey: key))
  }
}
