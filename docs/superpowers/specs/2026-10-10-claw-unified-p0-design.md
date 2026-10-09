# CLAW TALK Unified P0 Design

**Date:** 2026-10-10  
**Integration base:** `de61bee5989736e2c332b49d64a325ed432b7249` (PR #19)  
**Integration branch:** `work/claw-unified-p0-20261010`

## Objective

Turn the existing Draft PR stack into one testable candidate without discarding or silently rewriting the current diagnostics, iCloud, voice, startup, privacy, UI, or memory work.

## Global constraints

- iOS deployment minimum remains iOS 15.
- Never log or export typed text, transcripts, contacts, API keys, private memory contents, signing secrets, profiles, or certificates.
- Host and Keyboard data remain isolated unless an explicit App Group contract exists.
- No automatic sending, uploading, cloud restore, or memory write without the existing user authorization boundary.
- A passing simulator build is not evidence of real Speech, AVAudioSession, iCloud, keyboard-extension, or device UI correctness.
- Every behavioral fix begins with a failing test and is committed independently.
- Existing Draft PRs stay Draft. No merge to `main` before same-SHA CI and real-device acceptance.
- Do not touch the detached dirty worktree at `C:\Users\Administrator\.devspace\worktrees\_repo-43bba7e3`.

## Branch topology

All new implementation branches start at the fixed PR #19 SHA and target the unified integration branch:

1. `work/claw-p0-code-aware-20261010`
2. `work/claw-p0-icloud-transaction-20261010`
3. `work/claw-p0-voice-lifecycle-20261010`
4. `work/claw-p0-memory-retrieval-20261010`

The integration branch receives reviewed commits in that order. Code-Aware is file-isolated. iCloud and memory both touch storage code and therefore merge serially. Voice is logically independent but still lands through the same review gate.

## Workstream designs

### Code-Aware integration

Bring the fail-closed offline resolver and tests from PR #10 into the verified PR #19 lineage. Preserve exact-build SHA validation, bounded input sizes, filename ambiguity refusal, line validation, and diagnostic field sanitization. Do not claim dynamic call graphs or verified root causes.

### iCloud and local restore safety

Introduce a directory transaction service that stages both SharedSupport and UserData before replacing either destination. A failed validation or second-directory commit restores the original directories and configuration. The runtime gate proceeds only when the embedded capability marker is the Boolean value `true` and the requested ubiquity container is available.

Apple Developer capability changes and real iCloud read/write remain an external acceptance track, not something app code can fabricate.

### Voice lifecycle

Move session completion arbitration into a deterministic single-terminal state machine. A streaming session that has partial text but receives no final/error after stop must resolve exactly once through the partial fallback. A no-text timeout fails exactly once. Late callbacks and timers from generation A cannot modify generation B.

Audio interruption recovery, route changes, weak-network behavior, and on-device recognition are subsequent batches after this lifecycle seam is tested.

### Memory retrieval correctness

Apply subject, project, permission, lifecycle, and supersession filters before the result limit. Other people’s memories, pending candidates, expired records, and superseded records must not consume the target person’s retrieval budget. Existing MemoryGuard and privacy behavior remain authoritative.

### UI and real-device acceptance

The first automated UI batch adds tests and acceptance fixtures only; it does not modify the protected dirty AssistantRootView or screenshot-ingestion files. Real-device acceptance covers five-tab navigation, keyboard/composer transitions, candidate/AI panels, Dynamic Type, dark mode, VoiceOver, screenshot review/undo, and extended typing.

## Verification gates

Each workstream requires:

1. A test observed failing for the intended reason.
2. The minimal implementation.
3. Focused tests passing.
4. Relevant package or simulator suite passing.
5. A distinct commit and review.
6. GitHub Build Test success for the exact commit.
7. Signed IPA and Startup Smoke for each integration candidate.
8. Real-device evidence for Speech, iCloud, keyboard extension, and UI claims.

## External acceptance dependencies

The user must provide or operate:

- Apple Developer App ID/container capability and matching provisioning profile.
- A real iPhone installation of the exact signed artifact.
- Permission-denied and Settings-recovery scenarios.
- Network interruption, audio interruption, keyboard-host handoff, screenshots, recordings, and privacy inspection.

The project remains incomplete until these external gates are recorded against an exact source SHA.
