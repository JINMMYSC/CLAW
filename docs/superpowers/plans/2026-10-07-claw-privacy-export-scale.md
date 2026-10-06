# CLAW Privacy, Export, Sync, and Scale Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the Memory OS user-owned, scope-safe, encrypted where possible, exportable, recoverable, and measurable at realistic data sizes.

**Architecture:** Memory Guard and Scope Guard sit before Context Builder and cloud requests. The export package is a projection of the structured database with evidence and hashes. Sync is added only after local migration and conflict semantics are tested.

**Tech Stack:** Swift, Keychain/Secure Enclave, existing `ClawSecureStore` and `ClawPrivacyVaultService`, ZIP/JSON/Markdown export, XCTest, Python CI verifiers.

## Global Constraints

- No secret, certificate, provisioning profile, or API key is committed or exported unintentionally.
- Local data remains usable when cloud services are unavailable.
- The database encryption target is SQLCipher or an equivalent encrypted SQLite implementation; attachments use AES-256-GCM.
- Export/import must preserve IDs, versions, scopes, evidence, lineage, and attachment hashes.
- Encryption failures fail closed for `NEVER_SEND` and `LOCAL_ONLY` content.
- Sync is opt-in and must never silently overwrite a newer user correction.

### Task 1: Scope and Memory Guard enforcement

**Files:**
- Create: `Packages/HamsterKit/Sources/Memory/Privacy/MemoryGuard.swift`
- Create: `Packages/HamsterKit/Sources/Memory/Privacy/ScopeGuard.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawMemoryPolicyService.swift`
- Modify: `Packages/HamsterKit/Sources/Services/AIService.swift`
- Test: `Packages/HamsterKit/Tests/ClawMemory/MemoryGuardTests.swift`

- [ ] Write tests for `LOCAL_ONLY`, `NEVER_SEND`, `TEMPORARY`, person scope, project scope, and PII redaction.
- [ ] Verify tests fail because AI requests currently accept caller-built context without a central guard.
- [ ] Implement guard decisions returning allowed records plus a reason/audit code.
- [ ] Make `AIService` accept only a guarded request envelope for Memory-backed calls.
- [ ] Verify API-key and request logging never include protected content.
- [ ] Commit `feat: enforce Memory scope and cloud request guards`.

### Task 2: Local encryption and privacy vault integration

**Files:**
- Modify: `Packages/HamsterKit/Sources/Services/ClawSecureStore.swift`
- Modify: `Packages/HamsterKit/Sources/Services/ClawPrivacyVaultService.swift`
- Create: `Packages/HamsterKit/Sources/Memory/Privacy/EncryptedAttachmentStore.swift`
- Modify: `Hamster/Info.plist` only for verified permission copy.
- Test: `Packages/HamsterKit/Tests/ClawMemory/EncryptionStoreTests.swift`

- [ ] Write tests for encrypt/decrypt round-trip, wrong-key failure, protected record exclusion, and lock/unlock behavior.
- [ ] Verify tests fail against plaintext attachment writes.
- [ ] Implement AES-GCM attachment encryption using a Keychain-managed key; use Secure Enclave-backed wrapping when available.
- [ ] Gate protected database reads behind Face ID/user unlock without changing ordinary keyboard startup.
- [ ] Add migration for existing attachments with checksums and recoverable failure handling.
- [ ] Commit `feat: encrypt protected CLAW memory attachments`.

### Task 3: Complete export, import, backup, and forget propagation

**Files:**
- Modify: `Packages/HamsterKit/Sources/Services/ClawMemoryExchangeService.swift`
- Create: `Packages/HamsterKit/Sources/Memory/Export/ClawMemoryArchiveManifest.swift`
- Create: `Packages/HamsterKit/Tests/ClawMemory/MemoryArchiveRoundTripTests.swift`

- [ ] Write a fixture round-trip test covering users, People, Episodes, Tasks, Intents, Projects, evidence, lineage, attachments, graph edges, vectors, and audit records.
- [ ] Verify the current exchange format fails to preserve the new V2 fields.
- [ ] Implement `CLAW_MEMORY.zip` with `manifest.json`, schema version, per-file SHA-256, structured JSON, Markdown projections, raw attachments, and audit records.
- [ ] Validate manifest before import; stage imports transactionally; report conflicts without overwriting user corrections.
- [ ] Add a forget/export test proving deleted data is removed from derived projections and the manifest.
- [ ] Commit `feat: make CLAW memory archive complete and verifiable`.

### Task 4: Define opt-in sync conflict semantics

**Files:**
- Create: `Packages/HamsterKit/Sources/Memory/Sync/MemorySyncEngine.swift`
- Create: `Packages/HamsterKit/Sources/Memory/Sync/MemorySyncConflict.swift`
- Test: `Packages/HamsterKit/Tests/ClawMemory/MemorySyncEngineTests.swift`

- [ ] Write tests for add/add, update/update, user-correction-vs-inference, delete/update, and offline replay conflicts.
- [ ] Verify tests fail before the sync engine exists.
- [ ] Implement append-only event sync with version vectors and explicit conflict records.
- [ ] Apply user corrections and full deletes with highest precedence; never merge protected scopes into public scopes.
- [ ] Keep the first release local-only behind a feature flag until two-device fixtures pass.
- [ ] Commit `feat: add opt-in conflict-aware Memory sync`.

### Task 5: Scale, performance, and release verification

**Files:**
- Create: `tools/benchmark_claw_memory.py`
- Create: `tools/verify_claw_memory_archive.py`
- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/startup-smoke.yml`
- Modify: `README.md` with device test instructions.

- [ ] Generate deterministic datasets of 2k, 50k, and 100k memories, 250k conversations, 500 people, and 10k evidence links.
- [ ] Verify the benchmark fails when retrieval or export exceeds the agreed budgets.
- [ ] Add FTS/index/transaction benchmarks; keep vector/graph work out of the keyboard target.
- [ ] Add archive verification and migration checks to CI.
- [ ] Run real-device tests for cold start, keyboard memory peak, 30-minute typing, weak network, audio interruption, and battery sampling.
- [ ] Commit `test: add CLAW Memory scale and archive verification`.
