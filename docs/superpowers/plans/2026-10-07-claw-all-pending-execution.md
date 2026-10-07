# CLAW All Pending Work Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the approved CLAW keyboard, assistant, memory, skills, reset, permissions, extension, signing, and IPA-delivery backlog on `work/claw-productization-20261006`.

**Architecture:** Preserve `ClawMemoryStore` as the transactional source of truth while introducing `MemorySDK`, scope-aware routing, and reversible lifecycle services. Keep the keyboard extension thin; host-app services own database work, RIME deployment, permissions, and background processing. Deliver each independent slice with tests and a commit, then require the three GitHub Actions release workflows to pass on one SHA before downloading the signed IPA.

**Tech Stack:** Swift 5, SwiftUI/UIKit, SQLite, NaturalLanguage, Speech/AVFoundation, WidgetKit/ActivityKit/AppIntents/CoreSpotlight, App Group storage, XCTest, Python signing verification, GitHub Actions macOS 15.

## Global Constraints

- Minimum supported system remains iOS 15; newer APIs require availability guards.
- Preserve API keys and input-schema files during full reset.
- Do not split Memory and Skill into separate top-level pages.
- The structured-memory row opens a real full-list page; the Skills row scrolls within the current page.
- Third-party iOS apps cannot provide always-on background microphone wake-up; expose supported Siri, Shortcut, Widget, Control Center, and Action Button entry points instead.
- No secret, certificate, provisioning profile, or user data may be committed.
- Every production behavior change starts with a failing deterministic test when the behavior can be isolated from UIKit/SwiftUI.
- CI release gates are Build Test, Build & Sign GuruIM IPA, and iOS Startup Smoke on the same commit.

---

### Task 1: Close current keyboard and diagnostics gaps

**Files:**
- Modify: `Packages/HamsteriOS/Sources/UILayer/Compotents/PullDownMenuCell.swift`
- Modify: `Packages/HamsterKeyboardKit/Sources/View/ClawPanel/ClawVoiceInputService.swift`
- Modify: `Packages/HamsteriOS/Sources/ViewModel/iCloud/AppleCloudViewModel.swift`
- Modify: `Packages/HamsterKit/Sources/Services/SmartFreqService.swift`
- Test: `Packages/HamsteriOS/Tests/Settings/PullDownMenuCellTests.swift`
- Test: `Packages/HamsterKit/Tests/Services/LogServiceTests.swift`

- [ ] Add a failing test/harness proving the pull-down action covers the whole content row.
- [ ] Make the menu button fill the cell while retaining right-aligned value text and noninteractive title text.
- [ ] Add privacy-safe `LogService` error entries for voice, iCloud, and SmartFreq failures.
- [ ] Verify the focused tests on macOS CI and commit the slice.

### Task 2: Strengthen signing and artifact validation

**Files:**
- Modify: `scripts/sign_ipa.py`
- Modify: `.github/workflows/build-ipa.yml`
- Create: `scripts/verify_signed_ipa.py`
- Test: `scripts/tests/test_signing_profiles.py`

- [ ] Write failing Python tests for profile/bundle-ID mismatch, missing iCloud container, and per-extension profile selection.
- [ ] Validate every required secret before downloading or signing artifacts.
- [ ] Select provisioning profiles by embedded bundle identifier rather than sharing one profile across all `.appex` bundles.
- [ ] Verify signed entitlements and embedded profiles for the app and every extension before artifact upload.
- [ ] Keep the existing keyboard profile argument compatible and add a Widget profile input.

### Task 3: Finish Memory Center navigation and filtering

**Files:**
- Modify: `Packages/HamsteriOS/Sources/UILayer/ClawTalk/ClawAssistantRootView.swift`
- Create: `Packages/HamsteriOS/Sources/ViewModel/ClawTalk/ClawMemoryFilter.swift`
- Test: `Packages/HamsteriOS/Tests/ClawTalk/ClawMemoryFilterTests.swift`

- [ ] Test content, person, source, type, and scope filtering as a pure function.
- [ ] Add an All Memories child page that renders the complete loaded list with search and filters.
- [ ] Label the recent section with total count and its 30-item display limit.
- [ ] Wrap the existing page in `ScrollViewReader`; make Available Skills scroll to the Skill section ID.
- [ ] Keep pending-confirmation UI hidden until Task 10 provides real candidate records.

### Task 4: NOW data summary and shared keyboard dismissal

**Files:**
- Modify: `Packages/HamsteriOS/Sources/UILayer/ClawTalk/ClawTalkRootView.swift`
- Modify: `Packages/HamsteriOS/Sources/ViewModel/ClawTalk/ClawTalkViewModel.swift`
- Modify: `Packages/HamsteriOS/Sources/UILayer/ClawTalk/ClawAssistantRootView.swift`
- Create: `Packages/HamsteriOS/Sources/UILayer/ClawTalk/View+KeyboardDismissal.swift`
- Test: `Packages/HamsteriOS/Tests/ClawTalk/ClawTalkSummaryTests.swift`

- [ ] Test today-input count and latest collection time across input and clipboard entries.
- [ ] Remove the three duplicate top shortcuts and add the summary plus primary clipboard-record button.
- [ ] Add background-tap dismissal without intercepting controls.
- [ ] Add interactive scroll dismissal on iOS 16+ with an iOS 15 fallback.
- [ ] Apply the shared modifier to assistant, memory, people, and insight editors.

### Task 5: Build safe application reset orchestration

**Files:**
- Create: `Packages/HamsterKit/Sources/Services/ClawResetService.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawMemoryCore.swift`
- Modify: `Packages/HamsterKit/Sources/Services/HeartTargetService.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawChatService.swift`
- Modify: `Packages/HamsteriOS/Sources/ViewModel/About/AboutViewModel.swift`
- Modify: `Packages/HamsteriOS/Sources/UILayer/About/AboutRootView.swift`
- Test: `Packages/HamsterKit/Tests/Services/ClawResetServiceTests.swift`

- [ ] Test that full reset clears all approved data while preserving API keys and input schemas.
- [ ] Test that learning-only reset leaves memory, people, tasks, and conversations untouched.
- [ ] Return a per-step result so partial failure is visible.
- [ ] Add the two About-page actions, destructive confirmation copy, and post-reset navigation refresh.

### Task 6: Add scope-aware global retrieval

**Files:**
- Create: `Packages/HamsterKit/Sources/Memory/Retrieval/ClawQueryPersonResolver.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawContextBuilder.swift`
- Test: `Packages/HamsterKit/Tests/ClawMemory/ClawContextBuilderScopeTests.swift`

- [ ] Test exact display-name and alias matches, ambiguity, unrelated people, protected memory, and task filtering.
- [ ] Resolve at most one person from a global query; relationship labels alone may rank but never uniquely bind.
- [ ] Inject only bounded memory/timeline/task data for the resolved person and label the source in the context pack.
- [ ] Keep ambiguous/no-match queries free of contact memory.

### Task 7: Modernize assistant conversation and attachments

**Files:**
- Modify: `Packages/HamsterKit/Sources/Services/AIService.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawChatService.swift`
- Create: `Packages/HamsterKit/Sources/Services/ClawScreenshotIngestionService.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawContactIdentityResolver.swift`
- Modify: `Packages/HamsteriOS/Sources/UILayer/ClawTalk/ClawAssistantRootView.swift`
- Test: `Packages/HamsterKit/Tests/ClawTalk/ClawChatServiceTests.swift`
- Test: `Packages/HamsterKit/Tests/ClawMemory/ClawScreenshotIngestionTests.swift`

- [ ] Expose cancellation from `AIService.chat` and reject stale completion callbacks.
- [ ] Add stop, regenerate, date grouping, current-context search, jump-to-latest, and persistent trace metadata.
- [ ] Add persistent quick-prompt chips.
- [ ] Extract screenshot ingestion and return identity candidates with confidence.
- [ ] Add Photos, Files, and Clipboard attachment choices; route selected-person imports directly and ask on low-confidence global imports.
- [ ] Replace the composer with keyboard/voice toggle, bounded multiline field, attachment button, send button, and hold/release/slide-to-cancel voice interaction.

### Task 8: Complete Today and People workflows

**Files:**
- Modify: `Packages/HamsteriOS/Sources/UILayer/ClawTalk/ClawAssistantRootView.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawMemoryCore.swift`
- Modify: `Packages/HamsterKit/Sources/Services/HeartTargetService.swift`
- Delete after migration: `Packages/HamsteriOS/Sources/UILayer/Settings/HeartTargetSettingsViewController.swift`
- Test: `Packages/HamsterKit/Tests/ClawMemory/ClawTodayGroupingTests.swift`
- Test: `Packages/HamsterKit/Tests/ClawMemory/HeartTargetServiceTests.swift`

- [ ] Add manual task creation, custom snooze, four task groups, and persisted reminder strategy settings.
- [ ] Add avatar editing to the assistant People editor before removing the duplicate settings page and routing.
- [ ] Add recent-interaction sorting, open-task detail, pinyin/initial search, filters, inline-action cleanup, delete confirmation, merge/split, and dependent-record handling.

### Task 9: Establish Memory SDK and V2 write path

**Detailed plan:** `docs/superpowers/plans/2026-10-07-claw-memory-v2-core.md`

- [ ] Add V2 model/store tests and transactional constraints.
- [ ] Implement `MemorySDK` and route new writes through it with a safe legacy compatibility projection.
- [ ] Migrate existing data idempotently and verify count/ID/evidence preservation.
- [ ] Remove direct store writes only after all call sites use the SDK.

### Task 10: Implement Memory lifecycle, router, intents, and Dream

**Detailed plan:** `docs/superpowers/plans/2026-10-07-claw-memory-intelligence.md`

- [ ] Add FTS5 plus bounded lexical/semantic ranking and MMR.
- [ ] Add candidate promotion, conflicts, stale decay, TTL, correction priority, and reversible forget.
- [ ] Connect real candidate/conflict data to the Memory Center pending-confirmation section.
- [ ] Add Standing Intent, Memory Flush, staged Dream, audit records, and rollback.
- [ ] Add relationship/project/episode/knowledge/communication projections behind SDK interfaces.

### Task 11: Close the SmartFreq-to-RIME loop

**Files:**
- Create: `Packages/HamsterKit/Sources/Services/SmartFreqValidator.swift`
- Modify: `Packages/HamsterKit/Sources/Services/SmartFreqService.swift`
- Create: `Packages/HamsteriOS/Sources/Services/SmartFreqApplyService.swift`
- Modify: `Packages/HamsteriOS/Sources/UILayer/SmartFreq/SmartFreqRootView.swift`
- Test: `Packages/HamsterKit/Tests/SmartFreq/SmartFreqTests.swift`

- [ ] Test encoding format, deterministic pinyin, polyphones, term legality, observed count, duplicates, and conflicts.
- [ ] Produce accepted/pending/rejected drafts; never write unvalidated AI output to RIME.
- [ ] Patch the selected schema so RIME actually consumes the generated custom phrase table.
- [ ] Snapshot, apply, deploy, display changes, and support one-click rollback.
- [ ] Add new-term discovery, cross-schema encoding, opt-in person/context suggestions, stale-term cleanup, budget, and idle/charging scheduling.

### Task 12: Add supported permissions and system surfaces

**Files:**
- Modify: `Hamster/Info.plist`
- Modify: `Hamster/AppDelegete.swift`
- Modify: `Hamster/SceneDelegate.swift`
- Modify: `Hamster/Shortcuts/IntentProvider.swift`
- Create: `Packages/HamsteriOS/Sources/Services/ClawPermissionCoordinator.swift`
- Create: `Packages/HamsteriOS/Sources/Services/ClawSpotlightIndexer.swift`
- Create: `ClawWidgets/` WidgetKit extension sources
- Modify: `Hamster.xcodeproj/project.pbxproj`

- [ ] Add an ordered, skippable permission guide for contacts, calendars, reminders, location, notifications, microphone, and speech.
- [ ] Add BGTask registration and permitted identifiers.
- [ ] Add App Intents/Shortcuts and Spotlight indexing/deep links.
- [ ] Add home/lock-screen widgets backed by App Group snapshots.
- [ ] Add Live Activity states and guarded actions for recording, calls, and reminders.
- [ ] Do not implement unsupported always-on microphone behavior.

### Task 13: Privacy, encryption, exchange, and scale

**Detailed plan:** `docs/superpowers/plans/2026-10-07-claw-privacy-export-scale.md`

- [ ] Encrypt the database/attachments or document the supported equivalent with migrations.
- [ ] Preserve V2 IDs, provenance, evidence, lineage, scopes, and hashes across export/import.
- [ ] Add multi-device sync conflict rules.
- [ ] Add 100k-record retrieval and migration performance gates outside the keyboard process.

### Task 14: Release, CI, and IPA handoff

- [ ] Commit the existing AutoInsight dark-mode gradient after diff review.
- [ ] Run static checks and every locally runnable Python test.
- [ ] Push `work/claw-productization-20261006` without force.
- [ ] Wait for Build Test, Build & Sign GuruIM IPA, and iOS Startup Smoke on the same SHA.
- [ ] Inspect failed job steps/logs, fix, push, and repeat until all required jobs are green.
- [ ] Download `guru-signed-ipa`, verify its nested bundle signatures and entitlements, and copy `GuruIM-signed.ipa` to the task outputs directory.

## External Release Inputs

- A replacement `PROFILE_MAIN_B64` must contain `iCloud.dev.fuxiao.app.hamsterapp`; repository code cannot manufacture this entitlement.
- A new Widget bundle ID and provisioning profile are required before the signed IPA can include the Widget/Live Activity extension. Store it as `PROFILE_WIDGET_B64` after the signing workflow supports bundle-specific profiles.
- The P12 and every profile must belong to the same current Apple Developer team and cover the intended test device/distribution channel.

