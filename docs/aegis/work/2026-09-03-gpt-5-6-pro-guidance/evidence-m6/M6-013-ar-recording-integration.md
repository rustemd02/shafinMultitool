# M6-013 — AR recording integration

Status: **integration verified on the current store; one follow-up test fix
committed (`a846179`)**.

## Verified production chain

- **One recording source owner:** AR frames reach the serialized recorder
  only through `ARSceneContainer.Coordinator` → `SceneRecordingController`
  with the coordinator's exact `RecordingOwnerToken` (M7-002 fence); stale
  coordinators cannot re-seed a cache or borrow a token
  (`SceneRecordingControllerTests.testCoordinatorRebind…`,
  `testExactSourceTokenIsRequired…`).
- **Start/stop reflected once:** controller start/stop/release single-flight
  and decision-enum joins; the recorder lifecycle funnels every stop reason
  through one finish (`SceneRecordingControllerTests`,
  `SerializedMediaRecorderTests` stop matrix).
- **Teardown awaits recorder release:** `SceneWorkspaceTeardownTests` pin the
  canonical owner order recording → playback → persist → release → AR;
  teardown joins an in-flight take before releasing the route (16/16).
- **ARSession ownership:** `ARSessionOwnershipTests` — one session owner,
  generation-fenced callbacks, capability-gated configuration.

One M5-018 integration gap was found and fixed during this verification
(`a846179`): the teardown generation test still used a 100-yield spin for
`.reading`, which cannot survive the request-owned leader countdown; it now
uses the bounded 5 s poll.

## Verification

53/53 PASS on permitted iPhone 17e
(`/private/tmp/m6-013-verify-r2.xcresult`): ARSessionOwnershipTests +
SceneRecordingControllerTests + SceneWorkspaceTeardownTests +
AudioSessionCoordinatorTests. `git diff --check` clean.

## Honest boundary

Real ARKit tracking, anchor stability and camera timing under recording are
physical-device acceptance (M13); simulator evidence is contract evidence
only, exactly as the tracker states.
