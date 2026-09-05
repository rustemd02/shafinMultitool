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

## FIX-FIRST correction evidence

The coordinator handoff now treats the source-owner assignment result as
authoritative: `ARSceneContainer` retains a recording controller only when its
owner binding succeeds. The production AR callback and its deterministic test
seam share one forwarding boundary that requires the coordinator owner UUID to
match the controller binding; an active token must additionally be the AR
workspace token for that same owner. A second coordinator attached to the same
view-model/context therefore cannot borrow the first coordinator's token. The
two-coordinator case is covered by
`testCoordinatorRebindPreservesActiveSourceAndForeignCoordinatorCannotBorrowToken`.

`CameraService.stopRecording()` now captures the stopped token and performs
compare-and-clear while holding `recorderLock`. The bounded interleaving test
`testCameraServiceStopPreservesReplacementClaimMadeDuringUnlockedCleanup`
releases the old claim and installs a replacement during the cleanup hook; the
replacement remains active and is not erased by the old stop path.

## FIX-FIRST idempotent-rebind correction evidence

`SceneRecordingController.setRecordingSourceOwnerID` now accepts an exact
currently bound owner again in every non-terminal lifecycle state, including
`.recording`, without changing the source generation or active token. A
different owner remains rejected while a take is active, and a terminally
released controller cannot be rebound. The coordinator regression invokes the
same owner's `updateSessionState` after recording starts, forwards two later
frames through the production boundary, and verifies both reach the recorder;
the same test then verifies a foreign coordinator remains rejected.

## FIX-FIRST cache-generation correction evidence

`SceneRecordingController` now carries the producer owner ID into the same
`stateQueue` transaction that validates lifecycle/token state and mutates the
cached payload/timestamp or recorder append. Idle cache entries carry the
current owner and anticipated next generation; active entries carry the exact
token generation. Owner replacement clears the cache atomically, and terminal
stop/release clears it before returning to idle/released state. Implicit start
requires an exact current owner and next generation, so a prior coordinator's
frame cannot seed a replacement take.

`testOwnerReplacementCannotStartFromPreviousIdleCache` covers A's idle frame,
B replacement, a stale A callback after the swap, and B's fresh timestamp 4.
`testTerminalStopInvalidatesPreviousOwnerCacheBeforeReplacement` covers the
same boundary after a terminal writer stop. The existing coordinator rebind,
foreign-active rejection, and CameraService compare-and-clear tests remain
production regressions; the coordinator rebind test seeds its first frame
through the production coordinator forwarding boundary so it carries the
explicit owner claim required by the cache fence.

## FIX-FIRST test-fixture correction evidence

The broad post-cache-correction run exposed one stale test setup: after an
explicit coordinator owner binding, the rebind regression still seeded its
initial frame through the legacy unowned `enqueueVideo` compatibility path.
That path is intentionally rejected once an owner is bound. The test now uses
the coordinator's existing production forwarding seam, preserving the
same-owner active rebind assertion and the foreign-coordinator rejection
without weakening the owner fence. No production code changed in this
correction.

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

Result: **TEST SUCCEEDED**, 94/94 passed, 0 failures, 0 skipped. This was the
pre-correction baseline; its result bundle was
`/private/tmp/setos-m7-002-final2-20260905.xcresult` and is superseded by the
correction evidence below.
`git diff --check` passed with exit status 0. A prior identical target briefly
returned simulator `SBMainWorkspace Busy` before any test executed; rerun after
the allowed iPhone Air boot completed passed without source changes.

The correction precheck ran the focused recording/ownership set: **21/21
passed**, 0 failures, 0 skipped. The final correction run added the M6-004 route
and teardown integration suites (`CommercialShellRoutingTests`,
`CommercialShellLaunchCompositionTests`, `CameraViewModelLifecycleTests`, and
`SceneWorkspaceTeardownTests`) to the prior set: **151/151 passed**, 0 failures,
0 skipped. Its historical result bundle was
`/private/tmp/setos-m7-002-correction-final-20260905.xcresult` and is
superseded by the second correction below.
`git diff --check` passed after the correction edits.

The second correction focused run covered the recording/ownership classes:
**96/96 passed**, 0 failures, 0 skipped on iPhone Air iOS 26.5. Its historical
result bundle was `/private/tmp/setos-m7-002-correction2-focused-20260905.xcresult`.
The final second-correction run added the M6-004 route and teardown integration
suites above: **151/151 passed**, 0 failures, 0 skipped. The retained final
result bundle is `/private/tmp/setos-m7-002-correction2-final-20260905.xcresult`.
`git diff --check` passed after the idempotent-rebind correction.

The third-correction RED reproduction failed on the pre-fix cache path as
expected (`testOwnerReplacementCannotStartFromPreviousIdleCache`), then the
two direct production regressions passed **2/2**, 0 failures/skips, on iPhone
Air iOS 26.5. Its result bundle was
`/private/tmp/setos-m7-002-correction3-reg-20260905.xcresult` and is retained as
the smallest passing correction evidence. A subsequent full focused run
and expanded M6-004 run were blocked after test launch by the host's orphaned
`simctl diagnose` process (no test summary was produced); only the owned
xcodebuild/diagnostics processes were terminated. Root/coordinator integration
must rerun the focused and expanded commands cleanly before claiming final
verification for this correction.

The fourth-correction targeted run covered the coordinator rebind regression
and both owner-replacement cache regressions: **3/3 passed**, 0 failures, 0
skips, on iPhone Air iOS 26.5. Its retained result bundle is
`/private/tmp/setos-m7-002-correction4-reg-20260905.xcresult`. The expanded
route/teardown verification remains owned by root after integration; no broad
worker suite was launched in this correction. `git diff --check` passed before
commit.

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
