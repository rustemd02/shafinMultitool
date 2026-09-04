# M1-010 — Recording state contract (canonical lifecycle)

Task: Define a single serialized recording state machine and eliminate parallel truth between
CameraService, SceneRecordingController, and recorder adapters.
Owner boundary: `RecordingOwner`. Rollback: revert RecorderContracts/SerializedMediaRecorder/
SceneRecordingController/CameraService diff + delete RecordingLifecycleTransitionTests.swift.

## Parallel truth eliminated

| Before | Owner | After |
|---|---|---|
| `RecorderState` (7 states) queue-confined machine | SerializedMediaRecorder | unchanged behavior; every assignment now funnels through `setStateOnQueue` validated against the canonical table (DEBUG assert) |
| private `Lifecycle` (5 states) on `stateQueue` | SceneRecordingController | kept as confined vocabulary; `canonical` projection + `canonicalLifecycleState` reader; every mutation inside `withState` validated against the canonical table (DEBUG assert) |
| `private var isRecording: Bool` stored flag **plus** `recorderStateStorage` | CameraService | flag deleted; `isRecording` is now a derived projection `recorderStateStorage == .recording` (read sites unchanged, all under `recorderLock`) |
| 3 published bools (`isRecording`, `isRecordingStarting`, `isRecordingFinalizing`) | SceneGeneratorViewModel (UI projection) | intentionally kept — MainActor UI projections set around controller calls; not recording-owner truth. Migration to a single canonical subscription is deferred into M1-011/M1-012 which restructure those call paths anyway. |

## Canonical enum

`RecordingLifecycleState` (RecorderContracts.swift): idle, preparing, ready, starting, recording,
stopping, finalizing, promoting, completed, failed, cancelled — plus `released` (owner-cleanup
terminal, beyond the plan's set because both existing owners expose it).

`RecorderState → RecordingLifecycleState` mapping: idle→idle, prepared→ready, recording→recording,
finishing→finalizing, finished→completed, failed→failed, released→released.

## Transition table (adjacency, `released` terminal, no-op rejected)

| from | legal to |
|---|---|
| idle | preparing, ready, starting, recording, failed, cancelled, released |
| preparing | ready, failed, cancelled, released |
| ready | starting, recording, failed, cancelled, released |
| starting | recording, stopping, idle, failed, cancelled, released |
| recording | stopping, finalizing, idle, failed, cancelled, released |
| stopping | finalizing, completed, idle, failed, cancelled, released |
| finalizing | promoting, completed, failed, cancelled, idle, released |
| promoting | completed, failed, cancelled |
| completed | promoting, released |
| failed | finalizing, idle, cancelled, released |
| cancelled | released |
| released | (terminal) |

Coarse edges kept legal because they describe observed owner behavior: `idle→recording` (legacy
CameraService atomic start), `finalizing/failed→idle` (legacy cleanup), `recording/stopping→idle`
(controller between-takes return). Each owner still enforces its own stricter policy on top —
e.g. the serialized recorder rejects start-from-idle at its guard before any assignment.

## SerializedMediaRecorder transition coverage (all asserted legal by DEBUG assert)

idle→ready (prepare), ready→recording (start), ready→failed (failStart, stop-on-prepared),
ready→released (release), recording→finalizing (stop/release beginFinish), recording→failed
(append failure), recording→released (finish with releaseRequested, no writer), failed→finalizing
(pending finish), finalizing→completed/failed/released (finishCompleted), completed→released,
failed→released, idle→released.

## SceneRecordingController transition coverage (validated in `withState`)

idle→starting (start request), starting→recording (performStart confirmed), starting→idle
(start abort/failure), recording→stopping (stop request), recording→idle (stop with no recorder),
stopping→idle (stop task completion — between takes), idle→released (release).

## Narrow verification

- `shafinMultitoolTests/RecordingLifecycleTransitionTests.swift` (6 tests): full 12×12 adjacency
  matrix equality, released-terminal + no-op rejection, RecorderState mapping, recorder rejects
  start/stop from idle with `.invalidTransition`, serialized happy path projects
  idle→ready→recording→completed→released with finalized artifact and cached stop result,
  controller projects idle→recording→idle→released across one real take through the serialized
  recorder.
- Regression: SerializedMediaRecorderTests + SceneRecordingControllerTests — the DEBUG asserts
  validate every real transition exercised by the existing suites.
