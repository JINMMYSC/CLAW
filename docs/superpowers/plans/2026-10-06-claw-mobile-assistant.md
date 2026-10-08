# CLAW Mobile Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the current CLAW TALK-focused build into a mobile-first personal assistant foundation while preserving the keyboard as a primary output surface.

**Architecture:** Add deep shared modules in HamsterKit for memory, timeline, context, assistant conversations, skills/evolution feedback, and import/export. Then adapt the keyboard and host app to consume those interfaces instead of creating more feature-specific state.

**Tech Stack:** Swift 5.8, iOS 15+, SwiftUI/UIKit, Foundation, App Group storage, existing HamsterKit/HamsterKeyboardKit/HamsteriOS packages.

## Global Constraints

- Minimum deployment target remains iOS 15.
- Branch baseline is `work/claw-voice-keyboard-bg` at `2513275e9c85f93858e8208d306e53f430a3deae`.
- Keyboard AI panel heights target compact 140 pt, standard 175 pt, expanded maximum 210 pt.
- The host app and keyboard share the same assistant conversation state.
- Contact memories and timelines must not leak across contacts.
- Internal memory is structured; Markdown is not the canonical database.
- Import/export supports Markdown, JSON/JSONL, and .clawmemory package metadata.
- No credentials, Apple signing assets, provisioning profiles, or passwords are committed.

---

### Task 1: Shared assistant foundation

**Files:**
- Create: `Packages/HamsterKit/Sources/Models/ClawMemoryModels.swift`
- Create: `Packages/HamsterKit/Sources/Services/ClawMemoryCore.swift`
- Create: `Packages/HamsterKit/Sources/Services/ClawContextBuilder.swift`
- Create: `Packages/HamsterKit/Tests/ClawMemory/ClawMemoryCoreTests.swift`

- [ ] Add tests for scoped memory upsert/search, provenance, and contact isolation.
- [ ] Implement the smallest shared Memory Core interface needed by keyboard and host.
- [ ] Add context-pack construction from global + selected-contact memories.
- [ ] Run HamsterKit tests.

### Task 2: Person conversation timeline and screenshot ingestion seam

**Files:**
- Modify: `Packages/HamsterKit/Sources/Services/HeartTargetService.swift`
- Create: `Packages/HamsterKit/Sources/Models/ClawConversationModels.swift`
- Create: `Packages/HamsterKit/Sources/Services/ClawConversationTimelineService.swift`
- Create: `Packages/HamsterKit/Sources/Services/ClawScreenshotIngestionService.swift`
- Create: `Packages/HamsterKit/Tests/ClawMemory/ClawConversationTimelineTests.swift`

- [ ] Add tests for per-contact append, dedupe, ordering, and source evidence.
- [ ] Extend heart-target profiles with non-breaking assistant metadata.
- [ ] Add a screenshot-ingestion interface that accepts structured OCR observations and resolves them to timeline messages.
- [ ] Run HamsterKit tests.

### Task 3: Shared assistant conversation, skills, and evolution feedback

**Files:**
- Modify: `Packages/HamsterKit/Sources/Services/ClawChatService.swift`
- Create: `Packages/HamsterKit/Sources/Models/ClawSkillModels.swift`
- Create: `Packages/HamsterKit/Sources/Services/ClawSkillService.swift`
- Create: `Packages/HamsterKit/Sources/Services/ClawEvolutionService.swift`
- Create: `Packages/HamsterKit/Tests/ClawMemory/ClawSkillEvolutionTests.swift`

- [ ] Add tests for skill versioning and feedback aggregation.
- [ ] Keep one shared conversation store usable from keyboard and host.
- [ ] Add non-code skill definitions and adoption/edit feedback.
- [ ] Run HamsterKit tests.

### Task 4: Memory exchange

**Files:**
- Create: `Packages/HamsterKit/Sources/Services/ClawMemoryExchangeService.swift`
- Create: `Packages/HamsterKit/Tests/ClawMemory/ClawMemoryExchangeTests.swift`

- [ ] Add failing tests for Markdown export, JSON round-trip, and duplicate import preview.
- [ ] Implement import preview with add/update/conflict/duplicate counts.
- [ ] Implement export for Markdown and JSON/JSONL plus .clawmemory manifest data.
- [ ] Run HamsterKit tests.

### Task 5: Keyboard toolbar and three AI panels

**Files:**
- Modify: `Packages/HamsterKeyboardKit/Sources/View/KeyboardToolbarView.swift`
- Modify: `Packages/HamsterKeyboardKit/Sources/View/ClawPanel/ClawPanelOverlayView.swift`
- Modify: `Packages/HamsterKeyboardKit/Sources/View/ClawPanel/ClawSuggestionEngine.swift`

- [ ] Replace one fixed panel height with compact/standard/expanded height selection.
- [ ] Make contact/context state visible in the panel.
- [ ] Make screenshot ingestion an explicit help-reply action.
- [ ] Make help-reply and super-talk layouts semantically distinct.
- [ ] Keep AI quick chat compact and expose continuation in host app.
- [ ] Run package/build checks.

### Task 6: Host app assistant home

**Files:**
- Modify: `Packages/HamsteriOS/Sources/UILayer/ClawTalk/ClawTalkRootView.swift`
- Modify: `Packages/HamsteriOS/Sources/UILayer/ClawTalk/ClawTalkViewController.swift`
- Create: `Packages/HamsteriOS/Sources/UILayer/ClawTalk/ClawAssistantHomeView.swift`
- Create: `Packages/HamsteriOS/Sources/ViewModel/ClawTalk/ClawAssistantViewModel.swift`

- [ ] Make assistant chat the primary CLAW screen.
- [ ] Surface today/people/memory/data-management entry points.
- [ ] Reuse shared assistant conversation state.
- [ ] Keep existing data-management functions reachable.
- [ ] Run package/build checks.

### Task 7: Integration and verification

**Files:**
- Modify only files required by compiler/test findings.

- [ ] Run Swift package tests that are available on the current host.
- [ ] Run repository static/build validation scripts.
- [ ] Commit all changes on the CLAW feature branch.
- [ ] Push branch and trigger GitHub Actions signing workflow.
- [ ] Verify CI is green for the exact pushed SHA.
- [ ] Download and return the IPA artifact.

