# M7-016 — A/V sync measurement

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

The serialized recorder now emits a typed synchronization measurement over
the one session timeline established by M7-006:

- `RecordingSyncReport` (payload-free): `startDeltaSeconds`
  (`firstAudio − firstVideo`), `endDeltaSeconds` (`lastAudio − lastVideo`),
  `monotonicityFaultCount` (invalid-timestamp, non-monotonic, and pre-origin
  audio rejections), and `discontinuityCount`.
- `SerializedMediaRecorder.syncReport()` produces the queue-consistent
  measurement from the bounded timebase report; the derivation is a pure
  static function so the release criterion is table-testable.
- **Release criterion encoded:** `satisfiesReleaseCriterion()` — absolute
  sync error ≤ 80 ms at start and end with zero monotonicity faults. A
  video-only take has nothing to measure and passes only with a fault-free
  timeline.

## Acceptance criteria evidence

| Criterion | Evidence |
|---|---|
| Sync measured from first/last PTS | `testSyncReportMeasuresStartAndEndDeltasAgainstTheEightyMillisecondCriterion` (start/end deltas asserted to 1e-9). |
| ≤ 80 ms release criterion | Same test passes at 0.080 s and fails at a 0.01 s bound; `testSyncReportRejectsTimelineBeyondEightyMilliseconds` (0.2 s start delta fails). |
| No monotonicity fault | `testSyncReportFailsOnMonotonicityFaultsEvenWithSmallDeltas` (small deltas + one out-of-order audio sample ⇒ fail). |
| Video-only semantics | `testVideoOnlyTakeSatisfiesSyncCriterionWithoutAudioEvidence`. |

## Narrow verification

Package C focused run: **70/70 PASS, 0 failures** (`SerializedMediaRecorderTests`,
`RecordingPreflightTests`, `PendingRecordingJournalTests`,
`RecordingArtifactPromotionTests`; xcresult
`/private/tmp/m7-pkgC-tests.xcresult`). `git diff --check` clean.

## Honest boundaries

Physical clap/flash content-marker validation (the tracker's second evidence
column) is M13 device work; this lane delivers the recorder-side measurement
schema and the deterministic release criterion over synthetic timelines.
