# M7-006 — master timebase

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

`SerializedMediaRecorder` now owns one monotonic media timebase per take
(`RecordingMediaTimebase`, queue-confined inside the recorder). The previously
scattered `firstVideoTimestamp`/`lastVideoTimestamp`/`acceptedVideoCount`
fields were folded into it, so admission, derived duration, and the new report
have a single source of truth.

Documented timestamp conversion (code comment on the type):

1. Producers deliver host seconds; the audio driver retimes capture-clock
   sample buffers to the host clock (`CMSyncConvertTime`) before enqueue.
2. The first admitted video sample establishes the session origin
   (`RecordingTimeOrigin.firstAcceptedVideoOrigin`, frozen in M7-001).
3. The Apple adapter converts admitted seconds to `CMTime` (timescale 600) and
   subtracts the first appended timestamp, so written presentation timestamps
   are session-relative and start at zero; audio timing entries are normalized
   with the same origin. Both streams share one session timeline.

Policy (`RecordingStreamTimePolicy.strictPerStreamMonotonic`):

- Non-finite timestamps are rejected and counted, never appended, and can no
  longer fail the take (previously a non-finite video timestamp reached the
  writer and surfaced as `.videoAppendFailed`).
- A sample whose timestamp is not strictly greater than its stream's last
  *admitted* timestamp is rejected and counted. The admission fence is
  separate from the committed timestamp so a backpressure drop cannot let an
  older sample produce decreasing PTS in the file.
- Audio samples before the established video origin are rejected and counted
  (negative session time is not representable).
- Forward gaps above 2.0 s are tolerated as counted discontinuities; backwards
  motion is never tolerated.
- `timebaseReport()` exposes a bounded, payload-free
  `RecordingTimebaseReport` (origin, per-stream accepted/rejected counts,
  discontinuity count, last timestamps) — the foundation for M7-016 sync
  measurement and M7-030 diagnostics.

## Acceptance criteria evidence

| Criterion | Evidence (SerializedMediaRecorderTests) |
|---|---|
| First accepted sample establishes session time | `testFirstAdmittedVideoSampleEstablishesSessionOrigin` (origin == first video sample; audio after origin accepted). |
| Audio/video timestamps are monotonic | `testNonMonotonicVideoSampleIsRejectedAndCountedWithoutFailingTheTake`, `testAudioBeforeOriginAndOutOfOrderAudioIsRejectedAndCounted` (faulted samples never reach the writer; take still finalizes). |
| Discontinuities are detected and handled | `testLargeForwardGapIsCountedAsDiscontinuityWhileStayingMonotonic` (counted, timeline continues, duration derived correctly). |
| Invalid timestamps rejected, never appended | `testNonFiniteVideoTimestampIsRejectedAndCountedNeverAppended`. |

Pre-existing `testConcurrentAppendSubmissionsStayOnOneRecorderQueueAndFinishAfterAppends`
was updated: fixed 32/64 counts are unreachable by design under strict
per-stream monotonicity when multiple producer threads interleave arrivals.
The test now asserts the invariants that must hold — queue confinement (one
queue token, one concurrent append), all admitted samples agree exactly with
writer append counts, appends precede mark/finish events — and documents the
policy change. The production AR path is unaffected: `SceneRecordingController`
already gated submissions with `shouldAccept(timestamp:)` (strictly
increasing) before enqueue.

## Narrow verification

Same focused run as M7-005: **93/93 PASS, 0 failures** on iPhone Air simulator
iOS 26.5 (xcresult `/private/tmp/m7-pkgA-tests-r3.xcresult`).
`git diff --check` clean.

## Honest boundaries

- Conversion correctness on real capture clocks (Bluetooth mic latency, clock
  drift) is physical-device work (M13 / M7-032); this lane proves the policy
  on synthetic timelines only.
