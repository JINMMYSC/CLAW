# CLAW Memory V2 Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Evolve the existing SQLite memory foundation into one structured, provenance-aware Memory OS without losing current data.

**Architecture:** `ClawMemoryStore` remains the transactional Source of Truth. New typed records and migrations live behind a `MemorySDK`; feature modules no longer call database tables directly. Raw events and evidence are immutable, while derived memories are versioned and reversible.

**Tech Stack:** Swift Codable models, SQLite through the existing store, FTS5, App Group storage, XCTest.

## Global Constraints

- Existing Memory, Conversation, Task, People, Skill, and exchange data must migrate idempotently.
- Raw evidence is append-only except for explicit user deletion/forget workflows.
- Derived data always stores provenance, evidence IDs, scope, confidence, trust, and lineage.
- Existing public APIs remain source-compatible until all callers migrate to `MemorySDK`.
- The V2 taxonomy explicitly includes Raw Memory, Working Memory, Episodic Memory, Semantic Memory, People Memory, Communication Memory, Preference Memory, Project Memory, Task Memory, Intent Memory, and Knowledge Memory.

### Task 1: Define V2 typed models and schema versioning

**Files:**
- Create: `Packages/HamsterKit/Sources/Memory/Core/MemoryV2Models.swift`
- Create: `Packages/HamsterKit/Sources/Memory/Core/MemoryScope.swift`
- Create: `Packages/HamsterKit/Sources/Memory/Core/MemoryProvenance.swift`
- Create: `Packages/HamsterKit/Sources/Memory/Core/MemoryLineage.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawMemoryCore.swift`
- Test: `Packages/HamsterKit/Tests/ClawMemory/MemoryV2ModelTests.swift`

**Interfaces:**

```swift
public enum MemoryScope: String, Codable { case global, person, relationship, group, project, app, session, localOnly }
public enum MemoryState: String, Codable { case candidate, active, confirmed, stale, archived, invalidated }
public enum MemoryType: String, Codable { case raw, working, episodic, semantic, people, communication, preference, project, task, intent, knowledge }
public struct MemoryProvenance: Codable, Equatable { let originType: String; let sourceApp: String?; let sourcePersonID: UUID?; let sourceSessionID: UUID?; let trustLevel: Int; let observedAt: Date; let ingestionMethod: String }
public struct MemoryEvidence: Codable, Equatable { let rawEventID: UUID; let locator: String?; let excerpt: String? }
```

- [ ] Write Codable round-trip tests for scope, state, provenance, evidence, and lineage.
- [ ] Run focused tests and verify new types fail before implementation.
- [ ] Add schema version `v2` and migration metadata without changing existing rows.
- [ ] Implement the models and migration registry.
- [ ] Run focused tests plus current `ClawMemoryCoreTests`.
- [ ] Commit `feat: add provenance-aware Memory V2 models`.

### Task 2: Add raw events, evidence, versions, and lineage tables

**Files:**
- Modify: `Packages/HamsterKit/Sources/Services/ClawMemoryCore.swift`
- Create: `Packages/HamsterKit/Sources/Memory/Storage/MemoryV2Store.swift`
- Test: `Packages/HamsterKit/Tests/ClawMemory/MemoryV2StoreTests.swift`

- [ ] Write tests for append-only raw events, evidence links, version creation, and lineage traversal.
- [ ] Verify tests fail against the current schema.
- [ ] Add migrations for `raw_events`, `memory_evidence`, `memory_versions`, and `memory_lineage` with indexes on source, scope, person, project, and observed time.
- [ ] Implement transactional insert/read methods and idempotency keys.
- [ ] Test rollback on a failed transaction and repeat migration twice.
- [ ] Commit `feat: persist raw evidence and memory lineage`.

### Task 3: Build the single Memory SDK boundary

**Files:**
- Create: `Packages/HamsterKit/Sources/Memory/MemorySDK.swift`
- Create: `Packages/HamsterKit/Sources/Memory/MemoryContext.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawContextBuilder.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawMemoryExchangeService.swift`
- Test: `Packages/HamsterKit/Tests/ClawMemory/MemorySDKTests.swift`

**Interfaces:**

```swift
public protocol MemorySDK {
  func remember(_ item: MemoryItem, evidence: [MemoryEvidence]) throws
  func recall(_ request: MemoryRecallRequest) throws -> [MemoryItem]
  func context(_ request: MemoryContextRequest) throws -> MemoryContext
  func correct(id: UUID, replacement: MemoryItem) throws
  func forget(id: UUID, mode: ForgetMode) throws
  func createTask(_ task: ClawSecretaryTask) throws
  func createIntent(_ intent: StandingIntent) throws
  func flush(_ session: MemoryFlushSession) throws
}
```

- [ ] Write tests proving all operations preserve scope/provenance and that forget records an audit entry.
- [ ] Verify direct feature access is not required by the tests.
- [ ] Implement the adapter over `ClawMemoryStore` and `MemoryV2Store`.
- [ ] Route `ClawContextBuilder` and exchange export through the SDK.
- [ ] Add compile-time call-site inventory for remaining direct writes.
- [ ] Commit `feat: introduce unified CLAW Memory SDK`.

### Task 4: Migrate existing data and add round-trip verification

**Files:**
- Create: `Packages/HamsterKit/Sources/Memory/Storage/MemoryMigrationV2.swift`
- Create: `Packages/HamsterKit/Tests/ClawMemory/MemoryMigrationV2Tests.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawMemoryExchangeService.swift`

- [ ] Build fixtures containing current conversations, memories, tasks, profiles, skills, screenshots, and feedback.
- [ ] Verify migration tests fail before the migration adapter exists.
- [ ] Implement idempotent migration with per-table counts and a manifest hash.
- [ ] Run migration twice and assert identical counts, IDs, evidence, and links.
- [ ] Test interrupted migration resumes without duplication.
- [ ] Commit `feat: migrate existing CLAW data into Memory V2`.
