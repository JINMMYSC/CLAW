# Voice Session Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Follow RED-GREEN-REFACTOR.

**Goal:** Make streaming stop resolve exactly once and prevent callbacks from an old recording generation from mutating a restarted session.

**Architecture:** Extract an internal deterministic lifecycle object that owns generation, partial text, callbacks, watchdog, and terminal arbitration. `ClawVoiceInputService` remains responsible for Speech and AVAudioSession resources. A manual scheduler makes timeout and cancellation races testable without sleeping.

**Tech Stack:** Swift, Speech, AVFoundation, XCTest, iOS 15.

## Global Constraints

- Preserve public `start`, `startStreaming`, and `stop` signatures.
- Never log transcript text.
- A terminal path captures callbacks, invalidates the generation, clears state, cancels work, tears down resources, then invokes the captured callback.
- Audio interruption and route-change recovery are second-batch work.

---

### Task 1: Streaming stop watchdog single terminal

**Files:**
- Create: `Packages/HamsterKeyboardKit/Sources/View/ClawPanel/ClawVoiceSessionLifecycle.swift`
- Create: `Packages/HamsteriOS/Tests/ClawTalk/ClawVoiceSessionLifecycleTests.swift`
- Create: `Packages/HamsteriOS/Tests/ClawTalk/Support/ClawVoiceManualScheduler.swift`
- Modify: `Packages/HamsterKeyboardKit/Sources/View/ClawPanel/ClawVoiceInputService.swift`

**Interfaces:**

```swift
protocol ClawVoiceScheduledWork { func cancel() }

final class ClawVoiceSessionLifecycle {
  enum Callbacks {
    case oneShot((Result<String, Error>) -> Void)
    case streaming(
      onPartial: (String) -> Void,
      onSegment: (String) -> Void,
      onError: (Error) -> Void
    )
  }

  typealias Schedule =
    (TimeInterval, @escaping () -> Void) -> ClawVoiceScheduledWork

  init(
    stopTimeout: TimeInterval = 6,
    schedule: @escaping Schedule,
    onTeardown: @escaping (_ generation: UInt, _ cancelTask: Bool) -> Void
  )

  var isRecording: Bool { get }
  @discardableResult func begin(_ callbacks: Callbacks) -> UInt
  @discardableResult func markRecording(generation: UInt) -> Bool
  func receive(generation: UInt, text: String?, isFinal: Bool, error: Error?)
  @discardableResult func stop(generation: UInt) -> Bool
  func cancel()
}
```

- [ ] Add tests:
  - `testStreamingStopTimeoutDeliversLatestNonemptyPartialOnce`
  - `testStreamingStopTimeoutWithoutTranscriptDeliversErrorOnce`
  - `testStreamingFinalBeforeTimeoutSuppressesWatchdog`
  - `testStreamingErrorBeforeTimeoutSuppressesWatchdog`
  - `testStreamingLateFinalAfterTimeoutDoesNotDeliverAgain`
  - `testRepeatedStopKeepsOriginalWatchdogDeadline`
  - `testOneShotStopTimeoutKeepsExistingPartialFallback`
- [ ] Mechanically extract enough current behavior to compile while intentionally retaining the missing streaming fallback.
- [ ] Run the first focused test. Expected RED: segments is empty instead of `["你好"]`.
- [ ] Implement `idle/preparing/recording/finalizing`, trimmed partial retention, and a common terminal path. No-text timeout returns `noTranscriptAfterStop`.
- [ ] Route main-queue Speech events into lifecycle; resource teardown must not clear the next generation.
- [ ] Run lifecycle and existing `ClawVoiceAndCandidatePolicyTests`.
- [ ] Commit:

```text
fix(voice): complete streaming stop watchdog exactly once
```

### Task 2: Rapid restart generation isolation

**Files:**
- Modify: `Packages/HamsteriOS/Tests/ClawTalk/ClawVoiceSessionLifecycleTests.swift`
- Modify only if tests expose a gap: `ClawVoiceSessionLifecycle.swift`

- [ ] Add tests:
  - `testRestartIgnoresPreviousSessionPartial`
  - `testRestartIgnoresPreviousSessionFinal`
  - `testRestartIgnoresPreviousSessionError`
  - `testRestartIgnoresCancelledPreviousSessionWatchdog`
  - `testRestartIgnoresPreviousSessionStop`
  - `testOldTerminalDoesNotTearDownCurrentSession`
  - `testTerminalCallbackCanStartNextSession`
  - `testRapidStartStopCyclesDeliverOnlyCurrentSession`
- [ ] Explicitly execute a cancelled A watchdog after B starts. Assert B remains recording and receives no A terminal/teardown.
- [ ] Run 100 deterministic rapid cycles without sleeps.
- [ ] If existing generation logic already passes, record these as regression coverage and do not invent a red result. If a test fails, make the smallest lifecycle correction.
- [ ] Run the whole lifecycle and policy suites.
- [ ] Commit:

```text
test(voice): guard rapid restart against stale session events
```

### Verification

Use the HamsteriOS simulator scheme and focused `-only-testing:HamsteriOSTests/ClawVoiceSessionLifecycleTests/<method>` for RED/GREEN. Final verification includes complete HamsteriOS tests with existing CloudKit skip, Release device build, Build Test, signed IPA, and Startup Smoke on the exact integration SHA.

Real-device acceptance must still exercise repeated partial→stop→final/watchdog cycles, rapid start/stop, and one insertion only. It does not prove call/Siri/Bluetooth interruption recovery, which remains batch two.
