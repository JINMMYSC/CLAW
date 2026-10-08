# CLAW TALK lightweight UX rollout (2026-10-09)

## Product constraints

- Reuse the existing Hamster/RIME, Apple Speech, Vision OCR, SQLite/FTS5, Memory SDK, SwiftUI/UIKit, and App Group bridge.
- Do **not** import new third-party apps, model runtimes, OCR engines, or large frameworks.
- Prioritize normal typing reliability over AI features. Keep expensive work out of the keyboard extension's main thread.
- Preserve existing host, keyboard, widget targets, identifiers, signing behavior, personal records, and API configuration.
- Every UX change needs a recovery path; no unconfirmed OCR result may silently create a person or become durable memory.
- Record before/after IPA size, installation footprint, keyboard peak memory and user-visible latency at release qualification; do not claim performance gains from a code diff alone.

## Phase A — immediate, safe changes

1. **Screenshot identity boundary:** unknown screenshot titles go to review without creating or selecting a new contact. Fuzzy matches are treated as suggestions. Confirmed selected contacts continue importing. Add a regression test.
2. **Assistant toolbar:** keep search and context selection visible; move low-frequency regenerate/new conversation actions to an accessible menu. Make destructive chat-history clearing deliberate.
3. Validate the first two changes on an isolated branch, run static checks, then rely on macOS CI for actual Swift compilation and XCTest. Do not mark device QA complete until tested on an iPhone.

## Phase B — keyboard and voice (P0, not yet completed)

1. Preserve the agreed empty-input action bar / active-composition candidate bar behavior, fixed-right dismiss control, dynamic hidden-button layout, and multiple-row candidate expansion.
2. Coalesce duplicate Combine-driven layout requests. Measure keyboard startup latency, per-key UI latency, and peak extension memory before changing behavior.
3. Keep RIME composition state intact when entering/exiting the AI, Help Reply, and Super Talk panels; test 9-key, full Pinyin, light/dark and narrow screens.
4. Consolidate voice start/stop/interruption/cancellation and App Group text handoff. Keyboard extension must not assume it can access the microphone or always launch the host.
5. Protect typed drafts and pending AI requests when panel state changes; no automatic external-app sending.

## Phase C — host navigation and interaction (P0, not yet completed)

1. Remove the nested settings-first navigation in favor of Assistant / Today / People / Memory / Settings as top-level destinations, preserving iPad behavior and deep links.
2. Keep one People editor. Preserve avatar editing, aliases, group flag, and all existing records; do not recategorize a deleted person's memories as global.
3. Simplify chat composition: text/voice switching, a reusable attachments action, send-state clarity, separate dictation and hands-free conversation.
4. Group Settings into Keyboard, Appearance, AI & Voice, Data & Privacy, Sync & Backup, Advanced, and Diagnostics.
5. Make permission and iCloud failures specific and actionable. Avoid opening host functionality from keyboard without a fallback.

## Phase D — unified intelligence (P0/P1, not yet completed)

1. Consolidate legacy context access behind Memory SDK/Router with correctly scoped global/person/project queries.
2. Add Chinese retrieval and person-alias regression fixtures; test recall correctness and bounded context under 2k and 100k records.
3. Screenshot review with explicit person assignment, bubble attribution correction, duplicate detection, and undo.
4. Connect confirmed tasks, Today, person timeline, Help Reply and Super Talk; avoid promoting uncertain inferences into confirmed memories.
5. Enforce retention controls, export/import integrity, source tracing and forgetting semantics.

## Release gates

| Gate | Acceptance criteria |
|---|---|
| Source | diff check, focused tests, no new heavy dependency |
| CI | build and test + signed IPA + startup smoke for the same SHA |
| Keyboard | 30-minute real-device typing, no input loss, no keyboard crash or unexpected model work |
| Voice | permission denial, double tap, interruption, cold launch and handoff |
| Memory | unknown screenshot title cannot auto-create/select; no unconfirmed persistence; person context isolation |
| UX | narrow/wide screens, Dynamic Type, VoiceOver labels, portrait/landscape, light/dark modes |
| Footprint | report before/after IPA, installed size, memory and battery measurements; reject regressions without justified user value |

## Status

- Phase A: source changes started on `work/claw-ux-lightweight-20261009`; Swift/Xcode and iPhone verification pending.
- Phases B–D: tracked work, **not implemented by this document**. Re-evaluate against latest source before coding to avoid duplicating prior fixes.

## Implementation batch 2 (same branch)
- Keyboard: adapt fixed action widths for 320pt devices and expose emoji in the overflow menu without adding a framework.
- Host composer: persistent attachment entry even with nonempty text; emoji available from the existing attachment panel; send action independent.
- Host navigation: fifth tab now opens a Settings hub, with raw input records nested under Data & Privacy; legacy keyboard settings remain accessible via their existing URL.
- Memory recall: FTS5 miss uses a bounded full-table substring fallback rather than scanning only recent records, with an old-Chinese-memory regression fixture.
- Privacy: replace raw private-memory Spotlight entries with a generic CLAW shortcut and clear previously indexed raw memory content.
- Voice: one-shot dictation appends text to the draft; explicit press-and-hold voice send behavior remains unchanged.
- Verification: Swift XCTest, UI smoke, signed IPA, and real-device keyboard/voice QA remain required on the final commit. No performance gain is claimed without device measurements.

## Phase 1–5 incremental delivery (2026-10-09 continuation)

| Workstream | Implemented in feature branch | Still required |
|---|---|---|
| Input method | Compact 320pt toolbar, candidate viewport calculation, reduced duplicate layout refresh | Full 9-key/landscape/device matrix; theme refresh on-device; composition retention |
| Host | Assistant/Today/People/Memory/Settings tabs, simplified action menu, attachment + and editable one-shot voice drafts | Full settings migration, keyboard installation guidance, all screen flows |
| Memory | Chinese substring fallback, screenshot person/speaker/wording review before write, person-to-global scope promotion blocked | Memory V2 legacy read consolidation, scalable dedup, transactional record deletion, import undo |
| Voice and privacy | Host one-shot draft, voice request IDs preserved, Spotlight private memory cleanup, iCloud entitlement guidance | 30-minute real-device mic/keyboard switching, connectivity interruptions |
| Verification | Screenshot review tests, person scope tests, Chinese recall and composer tests | Same SHA Build Test + Startup Smoke + signed IPA, 100k memory stress, real iPhone QA |

All user-facing success claims must be gated on matching SHA CI; earlier intermediate pushes are expected to be cancelled by workflow concurrency. No third-party frameworks have been imported.
