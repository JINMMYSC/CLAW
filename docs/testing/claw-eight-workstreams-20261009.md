# CLAW TALK · Eight-workstream release qualification (2026-10-09)

Branch: `work/claw-ux-lightweight-20261009`. This checklist is authoritative for
release qualification; a green CI build cannot replace a physical-iPhone test.

## Delivery ledger (code status != device acceptance)

| Workstream | Source change / contract | Release checks still required |
| --- | --- | --- |
| 1. Keyboard interaction | Three-width toolbar sizing (full/compact/floating), 9-key native routing retained, candidate viewport and expanded-height fixes | 30 minutes continuous real typing, 9-key/26-key/pinyin markedText, candidate expand, AI panels, floating iPad, dark/light, landscape, Dynamic Type and VoiceOver. Zero missing keys or unexpectedly sent messages. |
| 2. Memory write/recall performance | V2 batch transaction; FTS indexed rowid migration replaces unindexed per-write ID scan; old Chinese-recall and FTS replacement regressions | Re-run 100k on final SHA, compare write/retrieval to baseline, profile memory/WAL growth and peak extension memory. |
| 3. Voice | 10-minute expiring keyboard handoff, stale pending failure, host background cancellation with failure result, explicit paste only; new interruption test | Denied/revoked permissions, double tap, call interruption, host killed, application switching, spoken text returned to the *original* field, ten-minute expiration, no background microphone access. |
| 4. Main app/settings | Seven groups with retained keyboard/legacy advanced settings routes, on-screen installation guide | Walk every entry and recovery path on iPhone. Confirm no hidden navigation stack and correct permissions links. |
| 5. Memory isolation/deletion | V2 authoritative over stale legacy, person scope, fullDelete clears V2/version/evidence/audit snapshots, person purge requires typed name | Correct/archive/undo, project-scoped privacy, backup/export propagation, import conflicts and transactional crash recovery. An external/cloud backup is NOT deleted by on-device erase. |
| 6. Screenshot import | OCR review before write; stable same-image and cautious cross-image dedupe; receipt-based on-device undo with person-ownership validation | Real screenshots from 3+ chat apps: avatars/group titles/long screenshots/overlap/short duplicate bubbles/edited attribution; verify unrelated persons stay intact. |
| 7. iCloud/OS compatibility | One sync at a time, explicit destructive restore confirmation, helpful entitlement failure; old RIME bootstrap maintained | Signed entitlement on-device; iOS 15 host & keyboard, iOS 16.1+ widget/live activity; backup/restore and legacy migration on a copy; never overwrite an irreplaceable user backup in testing. |
| 8. Release size/stability | Same-SHA Build Test/Startup Smoke/Signed IPA plus opt-in 100k and 250k tests and composer screenshots | Physical IPA install/upgrade; keyboard 30-minute stability; app/extension peak memory and battery; before/after installed size; crash-free restart. |

## Verified baseline from old source SHA 6abdb640

- Build Test #37879243692: success. 100k V2 write **1235.15 seconds**,
  person-scoped recall **0.0036 seconds**, Chinese query **2.43 seconds**.
  (Previous 1259.65s baseline reported by run #37874443465.)
- 250k conversation rows / 500 people: **56.65 seconds** on macOS CI.
- Startup Smoke #37879233633: success; provides composer state screenshots.
- Signed IPA #37879233631: success; actual `GuruIM-signed.ipa`
  **34,713,076 bytes** (measured from extracted GitHub Action artifact).
  Older signed IPA #37842364549 was **34,688,177 bytes**. Differences
  are not meaningful as app install size, extension RAM or battery figures.
- Those numbers are **not** performance claims for the newer FTS rowid
  implementation or this release's latest SHA.

## Release execution

1. On the final code SHA, require Build Test (including `stress_100k` and
   `stress_250k`), Startup Smoke and signed IPA to **all** succeed.
2. Compare `CLAW_SCALE_100K`, `CLAW_SCALE_250K` and full UIKit screenshot
   artifacts to the baseline. Flag any critical performance regression.
3. Install signed IPA on iPhone 15 Pro Max and oldest supported iOS device.
   Verify Host launch, keyboard extension registration, App Group text return,
   9-key and 26-key composition, candidate expand, 30-minute typing,
   background/foreground interruption, network loss and voice authorization.
4. Repeat the screenshot import/undo and memory delete/export/restore cases
   with **disposable** data. Never delete the user's real personal records to
   test a new workflow.
5. Export signing/CI logs and crash diagnostics without tokens, P12,
   passwords, provisioning profiles or private chat contents.
6. Keep PR Draft until physical acceptance is recorded. No release/merge
   claim from screenshots or automated tests alone.

## Outstanding hardware evidence

- [ ] 30-minute real-world typing on supported iPhone: latency, input loss, crash.
- [ ] Real phone memory usage (keyboard extension, host) and battery impact.
- [ ] Native iOS 15 runtime compatibility and permission flows.
- [ ] Device signing, installation, iCloud entitlement and overlay upgrade.
- [ ] All seven settings destinations work on device, plus VoiceOver.
- [ ] Real voice interruption/host handoff and original-field insertion.
- [ ] Safe restore/delete behavior on a spare backup copy, with evidence.
