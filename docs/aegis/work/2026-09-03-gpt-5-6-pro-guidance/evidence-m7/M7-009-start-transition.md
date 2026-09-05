# M7-009 — start transition

Status: **production owner verified in the isolated external-M7 lane; no new
production change required** (`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## Verified production behavior

The serialized start transition already implements the acceptance contract;
this task verified it against the current production owners (fresh run in
this lane, not inherited claims):

- **Serialized prepare → startWriting → startSession → recording.**
  `SceneRecordingController.performStart` builds the writer configuration,
  claims the source with a typed `RecordingOwnerToken` (generation-fenced,
  M7-002), `prepare`s the `SerializedMediaRecorder` (which creates the
  `AVAssetWriter` inputs), `start`s it (`startWriting` inside the Apple
  adapter, `startSession(atSourceTime:)` on the first appended sample), and
  only then commits the controller lifecycle to `.recording` together with
  the accepting frame fence. The recorder itself transitions to `.recording`
  only after `writer.start()` returned true and an optional audio driver
  started.
- **Owner token.** The start verifies the recorder snapshot after acceptance
  (`state == .recording`, exact generation, exact owner token) before
  publishing the fence; a mismatch releases everything and throws
  `.invalidTransition`.
- **Late completion cannot revive a cancelled/tearing-down owner.** The
  commit step re-checks `lifecycle == .starting` on the controller state
  queue; stop/release callers join the start task instead of finalizing a
  half-armed take; a lost commit releases the recorder and rethrows.
- **M7-008 addition:** mandatory preconditions now gate the start before any
  of the above (see M7-008 evidence).

## Verification (fresh in this lane)

- `RecordingStartTeardownRaceTests` — start parked in mic-permission await +
  teardown completes → resumed start aborts on owner guards without arming a
  take; start on a released workspace never reaches the permission client.
- `SceneRecordingControllerTests` — start single-flight, stop joins start,
  release joins both, concurrent start losers share the winner's task,
  configuration threading (M7-005/M7-007), preflight rejection (M7-008).
- Package B focused run: **79/79 PASS, 0 failures** on iPhone Air simulator
  iOS 26.5 (xcresult `/private/tmp/m7-pkgB-tests-r2.xcresult`).

## Honest boundaries

Barrier-controlled cancellation/teardown races are proven at the unit seam
with deterministic fixtures; real sensor/ARFrame delivery timing and the
legacy `CameraService` writer path's runtime behavior remain physical-device
qualification (M13 / M7-032).
