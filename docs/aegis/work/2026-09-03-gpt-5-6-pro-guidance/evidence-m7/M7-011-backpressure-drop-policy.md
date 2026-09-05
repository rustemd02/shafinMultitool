# M7-011 — backpressure / dropped frames

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

Writer backpressure is now bounded accounting plus an explicit failure
policy:

- Writer `.dropped` results (input `isReadyForMoreMediaData == false`) are
  counted per stream (`droppedVideoCount`, `droppedAudioCount` in the timebase
  report). A committed append resets the consecutive-drop streak.
- **Explicit failure policy (video):** `maxConsecutiveDroppedFrames`
  (production default 900 ≈ 15 s at 60 fps; configurable for fixtures)
  continuous video drops fail the take with the typed
  `.videoAppendFailed`. The policy threshold is deliberately far above any
  transient stall so a single dropped frame never ends a take.
- **Audio:** audio backpressure is counted but does not fail the take — AAC
  input pressure degrades sound without corrupting the timeline; the video
  policy is the explicit trigger.
- **Capture queues never wait:** submission is nonblocking
  (`enqueueVideo`/`enqueueAudio` only enqueue work), the recorder queue makes
  the admit/append decision, and the Apple adapter polls input readiness
  without blocking. `markAppendFailureOnQueue` stops the audio driver and
  fails the state machine without joining any capture callback.
- Diagnostics feed M7-030: drops, streak-triggered failures, and admission
  rejections all land in the bounded per-take report.

## Acceptance criteria evidence

| Criterion | Evidence |
|---|---|
| Bounded drop accounting | `testConsecutiveWriterBackpressureDropsTriggerExplicitFailurePolicy` (exact drop counts in the report); `testDroppedVideoDoesNotFailOrCountAsAcceptedFrame` (transient drops stay green — regression rerun in this lane). |
| Explicit failure policy | Same test: at the injected limit the take fails typed `.videoAppendFailed` with no recoverable artifact; the post-boundary sample is counted inactive. |
| Capture queues never wait indefinitely | Concurrency regression `testConcurrentAppendSubmissionsStayOnOneRecorderQueueAndFinishAfterAppends` (8 producer threads, single recorder queue, one concurrent append) green in this lane. |

## Narrow verification

Package B focused run: **79/79 PASS, 0 failures** (xcresult
`/private/tmp/m7-pkgB-tests-r2.xcresult`). `git diff --check` clean.

## Honest boundaries

Sustained real-encoder backpressure behavior (thermal, 4K writes to a real
flash device) is physical-device qualification (M13); the simulator lane
proves the policy and accounting deterministically.
