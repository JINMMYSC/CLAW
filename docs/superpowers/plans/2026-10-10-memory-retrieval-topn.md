# Memory Retrieval Top-N Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Follow RED-GREEN-REFACTOR.

**Goal:** Apply subject, project, lifecycle, expiry, scope, and cloud-permission filters before database limits so unrelated rows cannot displace eligible memories.

**Architecture:** Add scoped store queries for contextual recall and typed projections. Preserve the existing unrestricted `searchMemoryV2` for migration and administrative use. `MemoryGuard` remains the final privacy boundary.

**Tech Stack:** Swift, SQLite/FTS5, XCTest, iOS 15.

## Global Constraints

- Base on the PR #19 integration lineage.
- No database migration, dependency, or UI change.
- Do not modify the protected dirty screenshot, AssistantRootView, or rollout-plan files.
- Local projection keeps localOnly/neverSend records visible; cloud context does not.
- Preserve current ranking, Chinese fallback, normalized-key dedupe, and diversification after eligible candidates are fetched.

---

### Task 1: Scope recall candidates before limits

**Files:**
- Modify: `Packages/HamsterKit/Sources/Services/ClawMemoryCore.swift`
- Modify: `Packages/HamsterKit/Sources/Memory/Retrieval/MemoryRouter.swift`
- Modify: `Packages/HamsterKit/Tests/ClawMemory/MemoryRouterTests.swift`

**Interfaces:**

```swift
public func searchContextMemoryV2(
  _ request: MemoryRecallRequest,
  limit: Int,
  cloudEligibleOnly: Bool = false,
  now: Date = Date(),
  includeRecentUnmatched: Bool = true
) throws -> [MemoryV2Record]

public func recall(
  _ request: MemoryRecallRequest,
  cloudEligibleOnly: Bool = false,
  now: Date = Date()
) throws -> [MemoryV2Record]
```

All FTS, substring, empty-query, punctuation, and recent-fallback paths filter eligible state, expiry, person/project ownership, and requested scope before `LIMIT`.

- [ ] Add `limit: 1` tests:
  - `testOtherPeopleCannotDisplaceOlderSelectedPersonBeforeCandidateLimit`
  - `testInactiveRecordsCannotDisplaceOlderActiveRecordBeforeCandidateLimit`
  - `testExpiredRecordsCannotDisplaceOlderUnexpiredRecordBeforeCandidateLimit`
  - `testPersonOwnedGlobalRowsNeverEnterGlobalRecall`
  - `testProjectOwnedGlobalRowsNeverEnterUnscopedRecall`
  - `testFTSFiltersPersonBeforeCandidateLimit`
  - `testChineseSubstringFallbackFiltersPersonBeforeCandidateLimit`
  - `testPunctuationOnlyQueryUsesScopedRecentFallback`
- [ ] Run the first focused test. Expected RED: the target UUID is absent because newer other-person rows consume the candidate budget.
- [ ] Implement scoped SQL bindings while keeping existing `max(80, request.limit * 8)` candidate budget and ranking pipeline.
- [ ] Run all MemoryRouter tests.
- [ ] Commit:

```text
fix(memory): scope recall candidates before database limits
```

### Task 2: Filter cloud permissions before context limits

**Files:**
- Modify: `Packages/HamsterKit/Sources/Memory/MemorySDK.swift`
- Modify: `Packages/HamsterKit/Tests/ClawMemory/MemorySDKTests.swift`
- Reuse the Task 1 store query.

- [ ] Add:
  - `testCloudDeniedRowsCannotDisplaceOlderEligibleContext`
  - `testCloudContextKeepsPrivateCloudEligibleBeforeLimit`
  - `testLocalRecallStillReturnsLocalOnlyRecords`
  - `testTemporaryModeStillRejectsEligibleContext`
- [ ] Observe RED where localOnly/neverSend/temporary rows fill the pre-Guard budget and eligible context is absent.
- [ ] Call `MemoryRouter.recall(..., cloudEligibleOnly: true)` from SDK context. Continue running MemoryGuard and evidence loading.
- [ ] Run MemorySDK, MemoryGuard, and MemoryRouter tests.
- [ ] Commit:

```text
fix(memory): apply cloud permissions before context candidate limits
```

### Task 3: Filter typed projections before limits

**Files:**
- Modify: `Packages/HamsterKit/Sources/Services/ClawMemoryCore.swift`
- Modify: `Packages/HamsterKit/Sources/Memory/MemorySDK.swift`
- Modify: `Packages/HamsterKit/Tests/ClawMemory/MemoryProjectionTests.swift`

**Interface:**

```swift
public func projectionMemoryV2(
  _ kind: MemoryProjectionKind,
  personID: UUID? = nil,
  projectID: UUID? = nil,
  limit: Int = 100,
  now: Date = Date()
) throws -> [MemoryV2Record]
```

- [ ] Add:
  - `testOtherPeopleCannotDisplaceOlderSelectedPersonProjection`
  - `testWrongTypesCannotDisplaceOlderMatchingProjection`
  - `testInactiveRecordsCannotDisplaceOlderActiveProjection`
  - `testExpiredRecordsCannotDisplaceOlderUnexpiredProjection`
  - `testProjectionRetainsLocalOnlyRecordsForLocalDisplay`
  - `testProjectFilterRunsBeforeProjectionLimit`
- [ ] Observe RED where four newer unrelated rows consume the existing `limit * 4` sample.
- [ ] Move kind, state, expiry, person, and project conditions into SQL before `ORDER BY updated_at DESC LIMIT ?`.
- [ ] Run Projection, SDK, Router, Guard, and ContextBuilder scope tests.
- [ ] Commit:

```text
fix(memory): filter typed projections before top-n selection
```

### Verification

Run each focused RED/GREEN with the HamsterKit simulator scheme, then the complete modified test classes and full HamsterKit suite. Verify `git diff --name-only` excludes the four protected files. The final integration SHA requires Build Test, signed IPA, and Startup Smoke.

This batch proves bounded fixture correctness. A 100k stress run, screenshot 250-record overlap strategy, UI, and real-device performance remain separate work.
