# CLAW Unified Optimization Roadmap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this roadmap task-by-task. Each subsystem plan must be completed and reviewed before the next dependent subsystem starts.

**Goal:** Make CLAW keyboard, help-reply, rewrite, voice assistant, screenshot ingestion, and long-term memory operate as one responsive, local-first, evidence-backed Memory OS.

**Architecture:** Keep the existing SQLite/App Group foundation as the source of truth, add an explicit Memory SDK and Router boundary, and move all expensive retrieval, extraction, Dream, and consolidation work into the host app. The keyboard extension becomes a thin UI plus bounded App Group bridge. Voice uses one serialized state machine shared by the keyboard handoff and host app.

**Tech Stack:** Swift/UIKit, SwiftUI, SQLite/FTS5 through the existing `ClawMemoryStore`, Combine, Speech/AVFoundation, App Group `UserDefaults`, Keychain/Secure Enclave where available, GitHub Actions on `macos-15`.

## Global Constraints

- Preserve the existing product behavior already shipped at `5cb1c1bf12ed21a667b765692837c322c43044f8`.
- Keyboard Extension must never run full-database Dream, embedding, graph rebuild, or synchronous network preparation.
- SQLite/structured records remain Source of Truth; Markdown and vectors are projections/indexes only.
- Local First is mandatory: the complete user-owned memory remains available on-device when cloud services are unavailable.
- Every derived memory must retain provenance, evidence, scope, version, and lineage.
- User-explicit correction always outranks inference; model guesses cannot directly become confirmed long-term memory.
- Every production behavior change starts with a failing test or deterministic harness case.
- No data migration may silently delete existing records; migrations must be idempotent and auditable.
- Every release candidate must pass Build Test, Build & Sign IPA, iOS Startup Smoke, and the new regression/performance gates on one SHA.

## Execution Order

1. [Keyboard and voice stability](2026-10-07-claw-input-voice-stability.md)
2. [Memory V2 storage and SDK](2026-10-07-claw-memory-v2-core.md)
3. [Router, lifecycle, People, Intent, and Dream](2026-10-07-claw-memory-intelligence.md)
4. [Privacy, export, sync, and scale validation](2026-10-07-claw-privacy-export-scale.md)

## Release Gates

### Gate A — Input/voice usable

- 30-minute real-device typing session in WeChat has no keyboard restart or visible input loss.
- Help Reply and Super Talk first loading state appears within 100 ms and never blocks the keyboard main thread.
- Microphone and phone actions either enter the documented host-app mode or show an actionable error; neither flashes out of the keyboard.
- Voice state-machine tests pass for start, stop, interruption, duplicate tap, denial, and backgrounding.

### Gate B — One Memory OS

- Existing Memory, Conversation, People, Task, and Skill data migrate without count loss.
- All five product entry points use the same `MemorySDK` and `ContextBuilder` boundary.
- A memory can be traced from raw evidence to derived profile fact and back.
- Scope and privacy checks run before retrieval and before cloud requests.

### Gate C — Long-term intelligence

- Candidate memories require reinforcement or confirmation before promotion.
- Conflicts, stale facts, corrections, and forget requests are reversible and audited.
- Standing Intents fire only when person/context/condition/scope match.
- Dream runs produce an audit users can inspect and undo.

### Gate D — Ship quality

- 100k-memory retrieval benchmark meets the agreed latency budget without running in the keyboard process.
- Export/import round-trip preserves IDs, lineage, evidence, scopes, and attachment hashes.
- Build Test, signed IPA, Startup Smoke, migration, voice, scope, and performance checks are green on one SHA.

## Subsystem Plan Contract

Each linked plan must be implemented in small commits. At the end of every task:

1. Run the task-specific test first.
2. Run the relevant package tests.
3. Record changed schema/version numbers.
4. Commit only the task's files.
5. Re-run the previous gate before starting the next task.
