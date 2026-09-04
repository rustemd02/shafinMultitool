# M1-013 — Stale AR/capture failure fencing (owner token + generation)

Task: Fence stale AR/capture failures so an old coordinator cannot revoke or overwrite a newer
recording ownership claim.
Owner boundary: `RecordingOwner`. No production change required — the owner-token design exists
and its deterministic rejection test ran green this session.

## Fencing devices

| Failure source | Owner token / generation fence |
|---|---|
| AR coordinator (ARSceneContainer) | each `Coordinator` holds `recordingSourceOwnerID`; claim/FPS/release all pass it: `claimRecordingSource(ownerID:)`, `updateRecordingSourceFPS(_,ownerID:)` (VM guard: rejects ≠ activeRecordingSourceID), `releaseRecordingSource(ownerID:)` (VM guard: rejects ≠ active) — a stale coordinator's `session(didFailWithError:)` → `releaseRecordingSource()` is therefore a no-op against a newer claim |
| AR session interruptions | `advanceFrameGeneration()` + `handleARSessionInterruption(generation:)` guards `nextGeneration >= expectedARFrameGeneration` — stale interruption callbacks cannot mutate newer state |
| Camera capture failures | `CameraManager.failurePublisher` → `CameraViewModel.handleCameraFailure` guarded by `hasActiveCaptureOrPauseWork` + lifecycle intent token (stale intents discarded after release/replacement) |
| Recorder frame/failure generation | `SerializedMediaRecorder.canAccept(recordingID, generation)` frame fence; `failStart`/append failures bump `activeGeneration` so an old take's failure cannot touch a newer claim |

## Deterministic test (green this session)

`SceneRecordingControllerTests.testRecordingSourceOwnershipRejectsStaleCoordinatorUpdatesAndRelease`:
old owner claims (fps 60) → new owner claims (fps 30) → stale owner's FPS update AND release are
both rejected (fps stays 30, claim survives) → active owner's update/release proceed. This is the
plan's "old-owner failure after new-owner claim deterministic test".

Recorder-side generation fencing: SerializedMediaRecorderTests 23/23 (M1-010 evidence) cover the
frame gate, stale-start rejection, and failure-generation bumps. Camera-side stale failure
suppression is asserted by construction (M1-018 mapping) and CameraManagerLifecycleTests 18/18
(M1-003 evidence, generation fencing).

## Acceptance

Errors publish only when owner token and recording generation match the active claim — satisfied
and test-pinned. No production change.
