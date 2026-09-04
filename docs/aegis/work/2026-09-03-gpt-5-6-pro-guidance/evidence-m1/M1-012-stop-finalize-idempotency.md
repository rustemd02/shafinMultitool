# M1-012 — Stop/finalize idempotency and concurrent-caller sharing

Task: Make stop/finalize idempotent and shared by all concurrent callers.
Owner boundary: `RecordingOwner`. No production change required — the existing single-flight
design is complete and covered by deterministic tests executed green this session.

## Mechanism

| Layer | Idempotency device |
|---|---|
| SceneGeneratorViewModel | `requestStopRecording` guards `recordingStopTask == nil` — user/interruption/route stops coalesce into one finalize task; `performStopRecording` cancels + awaits the in-flight start task before stopping (M1-011 barrier tests) |
| SceneRecordingController | `stop()` decision enum: idle/released → cached `lastStopResult`; starting → `waitForStart`; stopping → `waitForStop`; recording → creates ONE `stopTask`, later callers join it |
| SerializedMediaRecorder | `handleStopOnQueue`: `.recording` appends `stopWaiters` then `beginFinishOnQueue` (guarded by `finishInFlight`); `.finishing` joins waiters; terminal states return cached `lastStopResult`; writer `finishWriting` completion runs once (`finishCompletedOnQueue` guards `finishInFlight`); `releaseRequested` folds release into the same finish |
| Promotion | `RENAME_EXCL` + committed-transaction idempotency (M1-014): at most one terminal artifact per recording ID |

## Coverage (tests executed green this session)

- testConcurrentStopsShareOneFinalizationResult — concurrent controller stops share one finalize
- testConcurrentStopSharesOneFinishAndResult / testConcurrentStopAndReleaseShareOneFinishAndExactResult
- testRepeatedStopAfterCompletionReturnsCachedResultWithoutSecondFinish — repeated stop, no second finish
- testDuplicateWriterCallbackResolvesWaitersOnceAndKeepsStableResult — duplicate delegate completion
- testReleaseRecordingAwaitsOneFinish / testCancelledStopWaiterDoesNotCancelCleanup / testCancelledReleaseWaiterDoesNotCancelCleanup
- M1-011 race tests: stop joins parked start; teardown stop coalesces with user stop path
- SerializedMediaRecorderTests 23/23 (M1-010 run) — recorder-level stop/finish matrix

Interruption stop maps to the same `requestStopRecording(.interruption)` entry as user stop
(SceneGeneratorViewModel.swift:4563), and route stop to `stopRecordingAndWait(.routeExit)` in the
teardown coordinator — both therefore share the identical single-flight device verified above.

## Acceptance

Repeated stop, interruption stop, route stop, and user stop await one finalize operation and
produce at most one terminal artifact — satisfied and test-pinned. No production change.
