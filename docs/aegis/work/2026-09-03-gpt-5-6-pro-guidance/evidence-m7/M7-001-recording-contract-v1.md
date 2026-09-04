# M7-001 — recording contract v1

Status: **implemented in the isolated recording contract lane; fix-first audit
corrections applied; awaiting Sol review and coordinator integration**.

## Scope and boundary

`RecordingContractV1` is a platform-neutral, immutable schema for one Camera
Coach or AR Workspace take. It adds no AVFoundation/UIKit import, runtime
owner, writer adapter, audio-session policy, or persistence behavior. M1-010's
`RecordingLifecycleState` and transition table remain the single state
authority; M7-002…M7-032 own runtime adoption.

The implementation is limited to:

- `shafinMultitool/Services/Recording/RecorderContracts.swift`
- `shafinMultitoolTests/RecordingContractV1Tests.swift`
- this evidence file

## Frozen dimensions and downstream status

| Frozen dimension | v1 contract | Current status | Downstream M7 owner | Evidence boundary |
|---|---|---|---|---|
| Source ownership | `RecordingWorkspaceSource.cameraCoach` / `.arWorkspace` inside a nonzero `RecordingOwnerToken` with owner UUID, `RecordingID`, and generation | Frozen and pure-validated; no runtime source selection changed | M7-002 `RecordingOwner` | No claim that Camera and AR producers are already exclusive at runtime |
| State | Reuses all `RecordingLifecycleState` cases and `isLegalTransition(from:to:)` from M1-010 | Frozen by reference; no duplicate transition table | M7-009, M7-012, M7-013 | Existing M1 lifecycle tests remain the behavioral evidence |
| Audio | Existing `RecordingAudioMode` plus typed unavailable behavior; `.required` accepts only `failRecording`, while `.disabled` is an explicit choice | Frozen; no implicit required→disabled downgrade is representable as valid | M7-003, M7-004 | No microphone permission, AVAudioSession, or device success claim |
| Media format | Explicit QuickTime movie container, H.264/HEVC codec, nonzero pixel-format FourCC, positive dimensions and FPS | Frozen and pure-validated | M7-005 `MediaEncodingOwner` | No claim that either codec is supported by every device |
| Orientation | Four capture orientations, mirrored flag, and typed track-transform metadata strategy | Frozen as metadata; no per-frame rotation added | M7-007 `MediaEncodingOwner` | No upright playback or physical orientation claim |
| Timebase | Host monotonic clock, first accepted video origin, strict per-stream monotonic ordering | Frozen as explicit typed policy | M7-006 `MediaTimingOwner` | No A/V sync measurement or discontinuity handling claim |
| Promotion target | App-local or identified nonzero scene-project UUID | Frozen and pure-validated; finalized app-local takes preserve local media, while finalized scene-project takes use durable journal → idempotent promotion | M7-019, M7-020 `MediaLifecycleOwner` | No journal write, atomic move, or project attach claim |
| Terminal outcome | Exhaustive table: finalized, recoverable failure, unrecoverable failure, cancelled precommit, promoted project-owned | Canonical one-entry-per-outcome mapping is target-aware; `.promotedProjectOwned` is explicitly not applicable for an app-local target | M7-013, M7-018…M7-024 | Matrix is a contract only; it does not prove crash-point recovery |
| Terminal obligation | App-local preservation; Pending→durable journal→idempotent scene-project promotion; recovery journal; clean task partials; preserve project-owned media | Each outcome maps to exactly one expected obligation for the selected target; incompatible target/disposition pairs are typed violations | M7-019…M7-024 | No claim that any obligation is executed by this package |
| Terminal artifact/error relation | Finalized and promoted require `RecordingArtifact` and no failure; recoverable failure requires a recoverable artifact plus typed `RecorderFailure`; unrecoverable failure forbids an artifact and requires typed `RecorderFailure`; cancelled precommit forbids an artifact and carries a typed `RecordingStopReason` | Canonical rows expose required/forbidden artifact presence and typed failure/cancellation relation; pure `accepts(...)` checks observations without introducing runtime state | M7-013, M7-018…M7-024 | No claim that current runtime owners already emit every v1 relation |

`CameraService` is legacy and nonconforming for v1: it currently bypasses
`RecordingContractV1` and lacks target-aware journal and typed-terminal
adoption. Its replacement/adaptation remains blocked until the downstream M7
owners adopt this schema; this package does not claim to have changed that
runtime path.

## Validation and tests

`RecordingContractV1.validate()` is a pure function over immutable values. It
reports typed violations for zero owner/recording/project UUIDs, zero
generation, invalid dimensions/FPS/FourCC, an invalid audio policy, target /
obligation drift, artifact-requirement drift, failure-relation drift, and
non-exhaustive or duplicated terminal entries. `validated()` is a throwing
boundary over the same result. `RecordingTerminalDisposition.accepts(...)`
checks the typed artifact/error/cancellation invariants at the observation
boundary without performing persistence or changing runtime state.

Focused tests cover:

1. valid Camera Coach and AR Workspace contracts;
2. exact identity and format rejection;
3. required-audio downgrade rejection, invalid audio combinations, and
   explicit video-only selection;
4. target-aware exhaustive terminal outcomes, one-to-one entries, and expected
   obligations;
5. artifact/error/cancellation acceptance and negative invariants;
6. throwing validation without mutation.

The existing `RecordingLifecycleTransitionTests` file is unchanged by this
task and remains the regression suite for M1-010 adjacency and recorder
behavior.

## Verification record

Executed from this worktree (the result and DerivedData paths are task-unique
and may be removed after the durable record is copied here):

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:shafinMultitoolTests/RecordingContractV1Tests \
  -only-testing:shafinMultitoolTests/RecordingLifecycleTransitionTests \
  -derivedDataPath /tmp/setos-m7-001-dd-20260904g \
  -resultBundlePath /tmp/setos-m7-001-result-20260904g.xcresult
```

Result: **TEST SUCCEEDED**, 15/15 passed, 0 failures, 0 skipped (6
`RecordingLifecycleTransitionTests` + 9 `RecordingContractV1Tests`). The
post-correction xcodebuild log is at
`/tmp/setos-m7-001-test-20260904g.log` and the result bundle is at
`/tmp/setos-m7-001-result-20260904g.xcresult`.

This simulator command is mechanical evidence only. The iPhone 17 Pro and
physical devices were not targeted. Physical A/V sync, microphone, codec,
orientation, thermal, Photos, and playback qualification remain external
M13/device work.
