# CLAW Input and Voice Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove keyboard main-thread stalls and make Help Reply, Super Talk, microphone, and phone actions deterministic on real devices.

**Architecture:** The keyboard sends a bounded event and request envelope to the host through the existing App Group bridge. A host-side asynchronous preparation service performs Memory/Skill/Keychain work. Voice operations are owned by one serialized state machine; UI receives main-thread state snapshots only.

**Tech Stack:** Swift/UIKit, SwiftUI, Combine, Speech, AVFoundation, existing `ClawMemoryStore`, `ClawSkillRuntime`, `AIService`.

## Global Constraints

- Do not call `ClawSkillRuntime.prepare`, `ClawMemoryStore`, or Keychain migration synchronously from a key/button event on the extension main thread.
- Keep the current three-panel behavior and current URL schemes, but make failures visible and actionable.
- The extension may not request or directly start microphone capture.
- All UI state mutations happen on the main actor/main queue.

### Task 1: Add regression harnesses before changing behavior

**Files:**
- Create: `Packages/HamsterKeyboardKit/Tests/ClawStability/ClawVoiceStateTests.swift`
- Create: `Packages/HamsterKeyboardKit/Tests/ClawStability/ClawRequestGateTests.swift`
- Modify: `Packages/HamsterKeyboardKit/Package.swift` only if the test target is not already registered.

**Interfaces:**
- `ClawVoiceStateMachine.transition(_:) -> ClawVoiceState`
- `ClawRequestGate.begin(id:) -> Bool`

- [ ] Write tests for: duplicate start is rejected, stop is idempotent, interruption returns idle, extension runtime never enters recording, and an old request cannot publish after cancellation.
- [ ] Run `swift test --package-path Packages/HamsterKeyboardKit` on macOS and verify the new tests fail because the types do not yet exist.
- [ ] Add only the minimal state/test doubles needed to compile the tests.
- [ ] Run the focused tests again and keep them red for the missing production behavior.
- [ ] Commit `test: define keyboard voice and request stability behavior`.

### Task 2: Move Help Reply/Super Talk preparation off the extension main thread

**Files:**
- Create: `Packages/HamsterKit/Sources/Services/ClawAsyncPreparationService.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawSkillRuntime.swift`
- Modify: `Packages/HamsterKit/Sources/Services/AIService.swift`
- Modify: `Packages/HamsterKeyboardKit/Sources/View/ClawPanel/ClawPanelOverlayView.swift`

**Interfaces:**

```swift
public struct ClawPreparedRequest: Sendable {
  public let configuration: AIRequestConfiguration
  public let messages: [AIMessage]
  public let skillID: String
  public let experimentVariantID: String?
}

public func prepareAsync(
  skillID: String,
  trigger: ClawSkillTrigger,
  input: String,
  contactID: UUID?
) async throws -> ClawPreparedRequest
```

- [ ] Add a test that a preparation call does not execute its store/Keychain work on the main queue.
- [ ] Run the focused test and verify it fails against the current synchronous `prepare` path.
- [ ] Implement a utility-priority preparation queue/actor; capture provider/model configuration once and pass immutable values into `AIService.chat`.
- [ ] Change `runAnalysis` to set loading UI, await preparation, then issue the network request without blocking the keyboard event handler.
- [ ] Add cancellation keyed by panel request ID; ignore results for a request that was replaced or dismissed.
- [ ] Run package tests and verify first-loading UI state is immediate in the UI harness.
- [ ] Commit `perf: prepare keyboard AI requests off the main thread`.

### Task 3: Remove duplicate layout and candidate refresh work

**Files:**
- Modify: `Packages/HamsterKeyboardKit/Sources/View/KeyboardToolbarView.swift`
- Modify: `Packages/HamsterKeyboardKit/Sources/View/ClawPanel/ClawPanelOverlayView.swift`
- Modify: `Packages/HamsterKeyboardKit/Sources/View/KeyboardRootView.swift`

- [ ] Add a test for one suggestion publication producing one view-model update.
- [ ] Verify the current duplicate Combine subscriptions fail the test/diagnostic counter.
- [ ] Introduce one `ClawPanelPresentationState` publisher and route toolbar/panel updates through it.
- [ ] Replace unconditional `layoutIfNeeded()` with constraint updates plus one coalesced layout pass per run-loop turn.
- [ ] Rebuild only the changed chat bubble/candidate row; do not remove and recreate all arranged subviews for every status change.
- [ ] Run UI smoke checks for panel open/close, Help Reply, Super Talk, and AI tab.
- [ ] Commit `perf: coalesce CLAW panel rendering updates`.

### Task 4: Make voice behavior explicit and safe

**Files:**
- Create: `Packages/HamsterKeyboardKit/Sources/View/ClawPanel/ClawVoiceStateMachine.swift`
- Modify: `Packages/HamsterKeyboardKit/Sources/View/ClawPanel/ClawVoiceInputService.swift`
- Modify: `Packages/HamsterKeyboardKit/Sources/View/ClawPanel/ClawPanelOverlayView.swift`
- Modify: `Packages/HamsteriOS/Sources/UILayer/ClawTalk/ClawAssistantRootView.swift`
- Modify: `Hamster/SceneDelegate.swift`

**Interfaces:**

```swift
public enum ClawVoiceState: Equatable { case idle, authorizing, listening, stopping, speaking, interrupted, failed(String) }
public enum ClawVoiceEvent { case tapMic, tapCall, permission(Bool), audioInterrupted, speech(Result<String, Error>), stop }
```

- [ ] Run the state tests from Task 1 and verify they fail for the current unguarded service.
- [ ] Serialize `AVAudioEngine` setup/teardown on one dedicated queue; make stop idempotent and never remove a tap twice.
- [ ] Dispatch every `start` completion and streaming callback to the main actor before touching UIKit/SwiftUI state.
- [ ] In the extension, replace the apparent keyboard switch with a clear host-app handoff state and actionable fallback if `extensionContext.open` fails.
- [ ] In the host app, accept one-shot voice and continuous-call deep links exactly once, then clear the launch flag after the view consumes it.
- [ ] Add audio-session interruption and route-change handling.
- [ ] Run voice unit tests, host startup smoke, and a real-device matrix: cold launch, warm launch, permission denied, rapid double tap, phone-to-mic transition, background/foreground.
- [ ] Commit `fix: serialize CLAW voice sessions and host handoff`.

### Task 5: Add real input/voice performance and crash gates

**Files:**
- Create: `tools/verify_claw_input_metrics.py`
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/startup-smoke.yml`
- Modify: `README.md` with the measurement procedure.

- [ ] Define thresholds: main-thread button handler under 100 ms, preparation off-main, no duplicate request IDs, and no unhandled voice state transitions.
- [ ] Run the verifier against a fixture trace and confirm it fails for an intentionally duplicated request.
- [ ] Implement the verifier and include the fixture trace in CI.
- [ ] Run Build Test, Build & Sign IPA, and Startup Smoke on one SHA.
- [ ] Commit `test: gate keyboard responsiveness and voice lifecycle`.

