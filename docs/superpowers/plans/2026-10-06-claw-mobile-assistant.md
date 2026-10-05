# CLAW Mobile Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the current CLAW TALK build into a mobile-first personal assistant foundation with unified memory, contact timelines, improved keyboard AI surfaces, a host-app assistant home, skills/evolution foundations, and memory interchange.

**Architecture:** Add a deep `ClawMemoryStore` module in HamsterKit backed by SQLite and expose focused interfaces for memories, conversation entries, tasks, feedback, and skills. Add `ClawContextBuilder` and reuse `ClawChatService` as the shared assistant conversation seam. Rework host and keyboard presentation around these shared modules without changing RIME fundamentals.

**Tech Stack:** Swift 5.8, UIKit, SwiftUI, Combine, Vision, SQLite3, existing HamsterKit/HamsterKeyboardKit/HamsteriOS packages.

## Global Constraints

- Minimum deployment target remains iOS 15.
- Do not change existing signing identifiers, entitlements, RIME engine behavior, or App Group.
- Do not download or execute arbitrary Swift/native code as skills.
- Keep keyboard AI overlay at approximately 140/175/210pt adaptive heights so host chat remains visible.
- Phone CLAW is the memory source of truth; desktop CLAW is out of scope.

### Task 1: Unified Memory Core

**Files:** create memory models/store/context/exchange files in `Packages/HamsterKit/Sources/Services/`; modify `Packages/HamsterKit/Package.swift` to link sqlite3; add unit tests under `Packages/HamsterKit/Tests/ClawMemory/`.

- [ ] Add SQLite schema and migrations for memory items, conversation messages, tasks, feedback, and skills.
- [ ] Add typed CRUD/query interfaces and contact-scoped timeline retrieval.
- [ ] Add Markdown/JSON/JSONL exchange parser/exporter.
- [ ] Add context builder that produces global/contact/task context packs.
- [ ] Run HamsterKit tests.

### Task 2: Contact Timeline and Screenshot Ingestion

**Files:** modify `HeartTargetService.swift`, `VisionOCRService.swift`, and keyboard panel screenshot flow; add screenshot parser.

- [ ] Extend contact profile compatibly with relationship/learned fields.
- [ ] Return positioned OCR observations and parse chat screenshot rows.
- [ ] Deduplicate and persist screenshot-derived messages to the selected contact timeline.
- [ ] Preserve raw OCR as evidence metadata, not as the canonical timeline format.

### Task 3: Shared Assistant Conversation and Context

**Files:** modify `ClawChatService.swift`; add assistant-facing context helpers.

- [ ] Fix persisted auto-speak default.
- [ ] Stop globally mutating provider/model for a request where practical.
- [ ] Inject Memory Core context into assistant requests.
- [ ] Persist assistant conversation as a shared host/keyboard conversation.

### Task 4: Keyboard AI UX

**Files:** modify `KeyboardToolbarView.swift`, `ClawPanelOverlayView.swift`, and suggestion helpers.

- [ ] Add contact selector to the high-frequency toolbar/context surface.
- [ ] Replace fixed 150pt height with adaptive 140/175/210pt heights.
- [ ] Make screenshot action explicit on 帮你回.
- [ ] Make 帮你回 return compact actionable reply choices and direct insert.
- [ ] Make 超会说 expose replace/insert-oriented output and style intent.
- [ ] Keep AI keyboard view short and point long conversations to host app.

### Task 5: Host App Assistant Home

**Files:** replace `ClawTalkRootView.swift` presentation with assistant-first navigation while retaining data-management subviews; reuse `ClawTalkViewModel` where appropriate.

- [ ] Add assistant chat home using shared ClawChatService.
- [ ] Add Today/Secretary, People, Memory, and Data Exchange tabs/sections.
- [ ] Keep privacy, raw records, AI settings, AutoInsight, SmartFreq, and backup reachable.

### Task 6: Skill and Evolution Foundations

**Files:** add skill registry/evolution feedback models and store methods; expose basic host-app visibility.

- [ ] Seed declarative built-in skills for 帮你回, 超会说, screenshot understanding, contact profile, task extraction, and daily secretary.
- [ ] Record accept/edit/regenerate feedback events.
- [ ] Expose skill versions and simple performance counters without executable-code mutation.

### Task 7: Verification, GitHub and IPA

- [ ] Run package tests/static checks available on the local machine.
- [ ] Review final diff against this spec.
- [ ] Commit and push the target branch.
- [ ] Verify GitHub Actions run for the pushed commit.
- [ ] Download the successful workflow IPA artifact and return it to the user.
Process exited with code 0.