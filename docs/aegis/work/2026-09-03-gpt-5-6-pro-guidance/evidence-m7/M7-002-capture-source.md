# M7-002 — canonical capture-source ownership

Status: **implemented in the isolated capture-source lane; targeted simulator
verification passed; awaiting coordinator integration**.

## Scope and boundary

One typed `RecordingOwnerToken` (`source`, owner UUID, `RecordingID`, and
monotonically fenced generation) is now required for claimed recording paths.
The serialized recorder queue is the canonical shared append boundary for AR
and recorder-adapter callers; `CameraService` applies the same token fence to
its legacy direct AVAssetWriter path. A source claim is exclusive, stale
claims/releases cannot revoke a newer owner, and replacement is accepted only
after terminal recorder stop/release.

The implementation is limited to:

- `shafinMultitool/Services/Recording/RecorderContracts.swift`
- `shafinMultitool/Services/Recording/SerializedMediaRecorder.swift`
- `shafinMultitool/SceneGeneratorModule/Services/SceneRecordingController.swift`
- `shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift`
- `shafinMultitool/Services/CameraService.swift`
- existing recording/ownership tests in `shafinMultitoolTests/`
- this evidence file

`CameraManager.swift` was inspected but not changed: the modern Camera Coach
manager currently feeds realtime analysis/scheduling and has no recorder source
handoff. Adding an unrelated handoff there would create a second owner. The
legacy `CameraService` path is fenced in place; full AVFoundation unification is
M6-013 and remains out of scope.

## Runtime evidence

- `RecorderContracts` carries the optional owner token through frame fences,
  state snapshots, and video/audio frame values. `RecordingSourceFence` is the
  shared exact-identity comparison; an untagged frame is accepted only before a
  source claim exists.
- `SerializedMediaRecorder` serializes claims, releases, prepare/start/stop,
  and appends on its existing queue. Claims require a valid token, a newer
  generation, and idle/prepared state. Releases require the exact token and a
  terminal state with no finish in flight.
- `SceneRecordingController` claims an AR token before prepare, passes the
  active token from `ARSceneContainer` into every AR video append, and awaits
  stop plus recorder release before releasing the source. Teardown clears the
  controller token only after that ordered terminal path.
- `CameraService` owns a lock-serialized Camera Coach token for its direct
  writer, rejects non-Camera Coach claims, requires the exact token for video
  appends, and clears only the token that was stopped/finished. In-flight
  preparation prevents replacement claims.
- Existing payload and timestamp paths remain unchanged apart from carrying
  the identity fence. Finalized media and first/last timestamp assertions stay
  in the existing recorder tests.

## Deterministic test evidence

`SerializedMediaRecorderTests` exercises the real claim/append/release path:

1. Camera Coach and AR claims are mutually exclusive; the same claim is
   idempotent.
2. Exact owner+generation frames are accepted while stale generation/owner
   frames are rejected; stale release is ignored.
3. A replacement claim is rejected while recording and before source release,
   then succeeds on a fresh recorder after terminal release.
4. Sixteen concurrent claims produce exactly one winner.
5. The accepted frame is written to the finalized artifact and timestamp
   behavior remains valid.

`SceneRecordingControllerTests` and `RecordingLifecycleTransitionTests` cover
AR token propagation, generation advancement, awaited route teardown, and no
active source after release. Existing `ARSessionOwnershipTests` and
`CameraManagerLifecycleTests` remain regression coverage for the adjacent
ownership/lifecycle boundaries.

## Verification record

Executed from this worktree on the simulator-only hardware boundary:

```text
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone Air,OS=26.5' \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -only-testing:shafinMultitoolTests/SerializedMediaRecorderTests \
  -only-testing:shafinMultitoolTests/SceneRecordingControllerTests \
  -only-testing:shafinMultitoolTests/RecordingLifecycleTransitionTests \
  -only-testing:shafinMultitoolTests/RecordingContractV1Tests \
  -only-testing:shafinMultitoolTests/ARSessionOwnershipTests \
  -only-testing:shafinMultitoolTests/CameraManagerLifecycleTests \
  -derivedDataPath /private/tmp/setos-m7-002-final-dd2-20260905 \
  -resultBundlePath /private/tmp/setos-m7-002-final2-20260905.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

Result: **TEST SUCCEEDED**, 94/94 passed, 0 failures, 0 skipped. The durable
result bundle is `/private/tmp/setos-m7-002-final2-20260905.xcresult`.
`git diff --check` passed with exit status 0. A prior identical target briefly
returned simulator `SBMainWorkspace Busy` before any test executed; rerun after
the allowed iPhone Air boot completed passed without source changes.

This lane did not use, boot, target, shut down, or erase an iPhone 17 Pro,
physical iPhone 13, or any physical device. Simulator evidence does not qualify
physical camera/AR timing, codec, thermal, or A/V synchronization behavior.

## Residual risk and follow-up

`CameraService` remains a legacy direct writer and is fenced but not migrated
to the serialized v1 recorder. Physical capture qualification and the broader
M6-013 integration remain follow-ups. Production AR and Camera Coach paths are
claimed before appending; the unclaimed recorder compatibility path is retained
only for existing pre-M7 contract tests and does not establish a second source
owner.
