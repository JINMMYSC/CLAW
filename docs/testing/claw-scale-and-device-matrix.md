# CLAW scale and real-device qualification

The optional 100k gate is implemented as `ClawScaleGateTests.testOptInHundredThousandMemoriesAndPersonIsolation`.
To trigger it, open the **Build Test** workflow in GitHub Actions, choose **Run workflow**
on the UX branch, and enable **stress_100k**. Normal push CI skips this expensive
test. Inspect the `CLAW_SCALE_100K` line in the macOS test logs and record actual
durations; no benchmark is considered passed until the job finishes successfully.
The 100k test verifies scoped retrieval and discovery of an old Chinese record
surrounded by newer memories belonging to another person. It does **not** yet
cover 250k messages, 500 contacts or peak RAM: those require separate gates.

CI gates every change with a deterministic 2,000-record V2 write/recall budget and the V2 archive checksum round trip. Release qualification additionally runs the opt-in 100,000-memory test with `CLAW_STRESS_TEST=1` and records results for these fixed fixture sizes:

| Fixture | Rows |
| --- | ---: |
| Memory V2 | 2,000 / 50,000 / 100,000 |
| Conversation messages | 250,000 |
| People | 500 |
| Evidence events | 10,000 |

The release owner records write time, p95 recall time, archive size, export time, verified import time, and peak memory. The 2,000-row CI budgets are 30 seconds for transactional writes and 3 seconds for one recall on the oldest supported simulator.

Real-device checks use the oldest supported iPhone on iOS 15 for the host and keyboard, plus an iOS 16.1 or newer device for WidgetKit and Live Activities. Verify permission steps can each be denied or skipped, BG refresh reschedules, SmartFreq only requests processing with external power and outside Low Power Mode, Spotlight opens CLAW, widget snapshots use the App Group, and recording/call Live Activities start and end. Test encrypted migration with a copy of legacy data, then export, hash-verify, import, correct, delete, and confirm lineage and forget propagation.

The Widget is built on every CI archive. Signed distribution embeds it only when `PROFILE_WIDGET_B64` contains a profile for `app.lgm.7517.widget`; otherwise the signing job removes only that extension and still produces the host IPA.

## Conversation import gate
Build Test now offers a separate `stress_250k` workflow_dispatch flag to
exercise 250,000 conversation messages spread over 500 people, importing 1,000
messages per SQLite transaction. The gate is opt-in and reports the measured
write duration as `CLAW_SCALE_250K`. It also asserts person-scoped lookup.
It is **not** an iPhone peak-memory measurement or permission for release.

## Repeatable final-SHA stress gate

Ordinary pushes skip the expensive 100k and 250k fixtures. To run both on a
specific final source SHA, include `[claw-stress]` in that commit's message on
the UX branch. The Build Test workflow will run both opt-in tests on that push;
manual `workflow_dispatch` input flags continue to work independently. When
a stress run is queued or running, do not claim it passed. Record both
`CLAW_SCALE_100K` and `CLAW_SCALE_250K` from the final completed job logs.
