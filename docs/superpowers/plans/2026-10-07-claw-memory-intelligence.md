# CLAW Memory Intelligence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add scope-aware retrieval, people/relationship resolution, memory lifecycle, Standing Intent, Memory Flush, and Dream auditing on top of Memory V2.

**Architecture:** The Router resolves intent/entity/scope before retrieval. Lifecycle engines operate on candidates and evidence in the host app. Dream runs are staged (`Light`, `REM`, `Deep`, `Audit`) and every mutation is a reversible transaction.

**Tech Stack:** Swift, SQLite FTS5, existing People/Task/Screenshot services, host-app utility tasks, XCTest.

## Global Constraints

- No Dream or full retrieval runs in the keyboard extension.
- Scope and privacy filtering happen before ranking and before prompt construction.
- User corrections and explicit forget operations are never overwritten by inference.
- Every Dream mutation has an audit record and rollback data.

### Task 1: Identity and relationship normalization

**Files:**
- Create: `Packages/HamsterKit/Sources/Memory/People/PersonIdentityResolverV2.swift`
- Create: `Packages/HamsterKit/Sources/Memory/People/RelationshipGraphStore.swift`
- Modify: `Packages/HamsterKit/Sources/Services/HeartTargetService.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawScreenshotChatParser.swift`
- Test: `Packages/HamsterKit/Tests/ClawMemory/PersonIdentityResolverV2Tests.swift`

- [ ] Write fixtures for same-name people, renamed profiles, multiple accounts, group aliases, and avatar changes.
- [ ] Verify resolver tests fail against the current name-only matching behavior.
- [ ] Implement stable person IDs, identity candidates, confidence, and manual merge/split operations.
- [ ] Store relationship edges with source event, strength, observed time, and version.
- [ ] Re-run screenshot parsing tests and verify one person ID is reused only when evidence supports it.
- [ ] Commit `feat: normalize CLAW person identity and relationships`.

### Task 2: Scope-aware Memory Router and hybrid retrieval

**Files:**
- Create: `Packages/HamsterKit/Sources/Memory/Retrieval/MemoryRouter.swift`
- Create: `Packages/HamsterKit/Sources/Memory/Retrieval/HybridMemoryRetriever.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawContextBuilder.swift`
- Modify: `Packages/HamsterKit/Sources/Memory/MemorySDK.swift`
- Test: `Packages/HamsterKit/Tests/ClawMemory/MemoryRouterTests.swift`

**Interfaces:**

```swift
public struct MemoryRecallRequest { let query: String; let personID: UUID?; let projectID: UUID?; let scope: MemoryScope; let limit: Int }
public struct MemoryRankFactors { let lexical: Double; let semantic: Double; let graph: Double; let recency: Double; let importance: Double; let confidence: Double; let trust: Double }
```

- [ ] Write tests proving private-person memory cannot appear in an unrelated group scope and repeated results are removed by MMR.
- [ ] Verify tests fail against current unrestricted context building.
- [ ] Implement intent/entity resolution, scope guard, privacy guard, FTS retrieval, timeline retrieval, and rank fusion.
- [ ] Add vector/graph provider protocols with a local no-op fallback until indexes exist.
- [ ] Build bounded Context Builder sections (`USER`, `PERSON`, `CURRENT CONTEXT`, `EVENTS`, `MEMORY`, `TASK`, `INTENT`, `EVIDENCE`).
- [ ] Commit `feat: add scoped hybrid Memory Router`.

### Task 3: Promotion, conflict, stale memory, and lineage forget

**Files:**
- Create: `Packages/HamsterKit/Sources/Memory/Intelligence/MemoryPromotionEngine.swift`
- Create: `Packages/HamsterKit/Sources/Memory/Intelligence/MemoryConflictResolver.swift`
- Create: `Packages/HamsterKit/Sources/Memory/Intelligence/MemoryForgetEngine.swift`
- Modify: `Packages/HamsterKit/Sources/Memory/MemorySDK.swift`
- Test: `Packages/HamsterKit/Tests/ClawMemory/MemoryLifecycleTests.swift`

- [ ] Write tests for candidate reinforcement, user correction priority, stale decay, conflict queueing, and lineage deletion.
- [ ] Verify tests fail against current immediate-write behavior.
- [ ] Implement `Observed → Candidate → Reinforced → Promoted → Confirmed` transitions using trust, frequency, recency, diversity, and confirmation.
- [ ] Implement version chains and a user-reviewable conflict record.
- [ ] Implement forget modes: remove evidence, invalidate derived facts, archive, or full delete.
- [ ] Commit `feat: add reversible Memory lifecycle and forget`.

### Task 4: Tasks, Standing Intent, and Memory Flush

**Files:**
- Create: `Packages/HamsterKit/Sources/Memory/Intelligence/StandingIntentStore.swift`
- Create: `Packages/HamsterKit/Sources/Memory/Intelligence/MemoryFlushService.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawSecretaryExtractor.swift`
- Modify: `Packages/HamsteriOS/Sources/UILayer/ClawTalk/ClawAssistantRootView.swift`
- Test: `Packages/HamsterKit/Tests/ClawMemory/StandingIntentTests.swift`

- [ ] Write tests for person/context/condition matching, expiration, cancellation, and flush extraction.
- [ ] Verify tests fail before Standing Intent and Flush exist.
- [ ] Implement intent fields: trigger, person, context, condition, action, expiration, status.
- [ ] Call Flush at voice end, session close, context reset, and host-app task switch.
- [ ] Store extracted decisions, promises, tasks, events, preferences, and intents with evidence.
- [ ] Commit `feat: add Standing Intent and Memory Flush`.

### Task 5: Staged Dream engine and audit UI data

**Files:**
- Create: `Packages/HamsterKit/Sources/Memory/Dream/ClawDreamEngine.swift`
- Create: `Packages/HamsterKit/Sources/Memory/Dream/ClawDreamAudit.swift`
- Modify: `Packages/HamsteriOS/Sources/UILayer/ClawTalk/ClawAssistantRootView.swift`
- Test: `Packages/HamsterKit/Tests/ClawMemory/ClawDreamEngineTests.swift`

- [ ] Write deterministic fixtures where Light identifies events, REM finds reinforcement, Deep proposes changes, and Audit records them.
- [ ] Verify the staged tests fail before the engine exists.
- [ ] Implement utility-priority host execution with a time/energy budget and no keyboard invocation.
- [ ] Require audit acceptance for low-trust promotions; auto-apply only safe, evidence-backed consolidation.
- [ ] Add rollback from audit records and expose “what CLAW learned” data to the host UI.
- [ ] Commit `feat: add staged CLAW Dream consolidation and audit`.

