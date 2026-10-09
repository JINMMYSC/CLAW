import Foundation
import XCTest
@testable import HamsterKeyboardKit

final class ClawVoiceSessionLifecycleTests: XCTestCase {
  private final class Harness {
    let scheduler = ClawVoiceManualScheduler()
    var partials: [String] = []
    var segments: [String] = []
    var errors: [Error] = []
    var oneShotResults: [Result<String, Error>] = []
    var teardowns: [(generation: UInt, cancelTask: Bool)] = []
    lazy var lifecycle = ClawVoiceSessionLifecycle(
      schedule: { [unowned self] interval, action in
        self.scheduler.schedule(after: interval, action: action)
      },
      onTeardown: { [unowned self] generation, cancelTask in
        self.teardowns.append((generation, cancelTask))
      }
    )

    func beginStreaming() -> UInt {
      let generation = lifecycle.begin(.streaming(
        onPartial: { [unowned self] in self.partials.append($0) },
        onSegment: { [unowned self] in self.segments.append($0) },
        onError: { [unowned self] in self.errors.append($0) }
      ))
      _ = lifecycle.markRecording(generation: generation)
      return generation
    }

    func partial(_ text: String, generation: UInt) {
      lifecycle.receive(generation: generation, text: text, isFinal: false, error: nil)
    }

    func final(_ text: String, generation: UInt) {
      lifecycle.receive(generation: generation, text: text, isFinal: true, error: nil)
    }
  }

  func testStreamingStopTimeoutDeliversLatestNonemptyPartialOnce() {
    let h = Harness()
    let generation = h.beginStreaming()
    h.partial("旧文本", generation: generation)
    h.partial(" 你好 ", generation: generation)
    h.partial(" \n ", generation: generation)
    XCTAssertTrue(h.lifecycle.stop(generation: generation))
    h.scheduler.advance(by: 5.9)
    XCTAssertTrue(h.segments.isEmpty)
    h.scheduler.advance(by: 0.1)
    XCTAssertEqual(h.segments, ["你好"])
    XCTAssertTrue(h.errors.isEmpty)
    XCTAssertFalse(h.lifecycle.isRecording)
    XCTAssertEqual(h.teardowns.count, 1)
    XCTAssertTrue(h.teardowns[0].cancelTask)
    h.scheduler.advance(by: 10)
    XCTAssertEqual(h.segments, ["你好"])
  }

  func testStreamingStopTimeoutWithoutTranscriptDeliversErrorOnce() {
    let h = Harness()
    let generation = h.beginStreaming()
    h.partial(" \n ", generation: generation)
    XCTAssertTrue(h.lifecycle.stop(generation: generation))
    h.scheduler.advance(by: 6)
    XCTAssertTrue(h.segments.isEmpty)
    XCTAssertEqual(h.errors.count, 1)
    if let error = h.errors.first as? ClawVoiceError {
      guard case .noTranscriptAfterStop = error else { return XCTFail("Unexpected timeout error") }
    } else {
      XCTFail("Expected noTranscriptAfterStop")
    }
    h.scheduler.advance(by: 6)
    XCTAssertEqual(h.errors.count, 1)
    XCTAssertEqual(h.teardowns.count, 1)
  }

  func testStreamingFinalBeforeTimeoutSuppressesWatchdog() {
    let h = Harness()
    let generation = h.beginStreaming()
    h.partial("中间", generation: generation)
    XCTAssertTrue(h.lifecycle.stop(generation: generation))
    let watchdog = h.scheduler.jobs[0]
    h.final("最终", generation: generation)
    h.scheduler.executeEvenIfCancelled(watchdog)
    XCTAssertEqual(h.segments, ["最终"])
    XCTAssertTrue(h.errors.isEmpty)
    XCTAssertEqual(h.teardowns.count, 1)
    XCTAssertFalse(h.teardowns[0].cancelTask)
  }

  func testStreamingErrorBeforeTimeoutSuppressesWatchdog() {
    let h = Harness()
    let generation = h.beginStreaming()
    h.partial("中间", generation: generation)
    XCTAssertTrue(h.lifecycle.stop(generation: generation))
    let watchdog = h.scheduler.jobs[0]
    let error = NSError(domain: "VoiceLifecycleTest", code: 42)
    h.lifecycle.receive(generation: generation, text: nil, isFinal: false, error: error)
    h.scheduler.executeEvenIfCancelled(watchdog)
    XCTAssertTrue(h.segments.isEmpty)
    XCTAssertEqual(h.errors.count, 1)
    XCTAssertEqual(h.errors.first.map { ($0 as NSError).code }, 42)
    XCTAssertEqual(h.teardowns.count, 1)
  }

  func testStreamingLateFinalAfterTimeoutDoesNotDeliverAgain() {
    let h = Harness()
    let generation = h.beginStreaming()
    h.partial("兜底", generation: generation)
    XCTAssertTrue(h.lifecycle.stop(generation: generation))
    h.scheduler.advance(by: 6)
    h.final("迟到最终", generation: generation)
    h.lifecycle.receive(
      generation: generation, text: nil, isFinal: false,
      error: NSError(domain: "VoiceLifecycleTest", code: 43)
    )
    XCTAssertEqual(h.segments, ["兜底"])
    XCTAssertTrue(h.errors.isEmpty)
    XCTAssertEqual(h.teardowns.count, 1)
  }

  func testRepeatedStopKeepsOriginalWatchdogDeadline() {
    let h = Harness()
    let generation = h.beginStreaming()
    h.partial("首个截止时间", generation: generation)
    XCTAssertTrue(h.lifecycle.stop(generation: generation))
    h.scheduler.advance(by: 3)
    XCTAssertFalse(h.lifecycle.stop(generation: generation))
    h.scheduler.advance(by: 3)
    XCTAssertEqual(h.segments, ["首个截止时间"])
    XCTAssertEqual(h.teardowns.count, 1)
  }

  func testOneShotStopTimeoutKeepsExistingPartialFallback() {
    let h = Harness()
    let generation = h.lifecycle.begin(.oneShot { h.oneShotResults.append($0) })
    XCTAssertTrue(h.lifecycle.markRecording(generation: generation))
    h.partial(" 单次结果 ", generation: generation)
    XCTAssertTrue(h.lifecycle.stop(generation: generation))
    h.scheduler.advance(by: 6)
    XCTAssertEqual(h.oneShotResults.count, 1)
    guard case .success(let text)? = h.oneShotResults.first else {
      return XCTFail("Expected one-shot partial fallback")
    }
    XCTAssertEqual(text, "单次结果")
    XCTAssertEqual(h.teardowns.count, 1)
  }
}

