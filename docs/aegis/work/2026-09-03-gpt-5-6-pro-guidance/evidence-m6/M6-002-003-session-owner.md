# M6-002 → M6-003 — AR session owner and configuration policy

Status: complete (correction)

Branch: `codex/set-os-m6-002-003`

Worktree: `/Users/unterlantas/.codex/worktrees/shafinMultitool/m6-002-003-session-owner`

Base commit: `3ca091fb80d9fbde32f11082948c62364117170c`

Correction commit: local follow-up commit (SHA is recorded in the worker
report)

## Implementation evidence

`ARSceneContainer.Coordinator` is the sole runtime owner of the workspace
`ARSession` lifecycle. It alone attaches the delegate, runs configurations,
pauses for generation, and pauses/detaches on replacement, dismantle, release,
or deinitialization. `SceneGeneratorViewModel` retains only a weak release
handle and a weak `ARView` for rendering/entity work; it does not mutate the
session delegate or lifecycle.

The owner maintains an active session identity and generation under a lock.
Delegate callbacks from another session, a stale generation, or a released
owner are rejected before presentation/frame/error/interruption handling.
Release is terminal, increments an observable release count exactly once, and
is safe to repeat. Deinitialization synchronously pauses and detaches the
runtime and schedules recording-source release.

`ARWorldTrackingConfigurationPolicy` is deterministic and takes injectable
`ARWorldTrackingCapabilityEvidence`; production uses the ARKit-backed adapter.
World tracking, horizontal-plane detection, and gravity alignment are required
capabilities. The applied configuration always keeps horizontal planes,
gravity, no environment texturing, and no scene reconstruction. Requested
depth chooses smoothed scene depth, then scene depth, then an explicit
depth-free `.unavailable` plan when neither is supported. The initial world map
is forwarded unchanged. Unsupported base/world tracking returns a typed
failure before any `run` call and maps to the complete RU+EN localized recovery
copy `set.generator.error.ar_configuration_unsupported`.

Equivalent plans do not rerun the session; a material plan change reruns once.
The existing recording-source owner token/FPS publication, frame generation
invalidation, coaching overlay, one-`ARView` representable, routes, and
accessibility IDs remain unchanged.

The correction constructs `ARView` with
`automaticallyConfigureSession: false` before the coordinator attaches the
session, removing the late property mutation that could allow an automatic run
first. Interruption and interruption-ended callbacks remain identity- and
generation-fenced; an accepted ended callback applies the interruption safety
transition for its accepted latest generation when the earlier safety task was
not observed, then enters recovery. A per-interruption latch makes that safety
transition observable and exactly once.

## Verification receipt

Required bounded command (exit code 0):

```sh
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone Air,OS=26.5' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:shafinMultitoolTests/ARSessionOwnershipTests -only-testing:shafinMultitoolTests/ARConfigurationPolicyTests -only-testing:shafinMultitoolTests/ARWorkspaceContractTests -only-testing:shafinMultitoolTests/SceneWorkspaceTeardownTests -derivedDataPath /private/tmp/setos-m6-002-003-correction-dd -resultBundlePath /private/tmp/setos-m6-002-003-correction.xcresult CODE_SIGNING_ALLOWED=NO
```

Result bundle: `/private/tmp/setos-m6-002-003-correction.xcresult`

```text
device: iPhone Air, iOS Simulator, OS 26.5
ARSessionOwnershipTests: 6 passed
ARConfigurationPolicyTests: 6 passed
ARWorkspaceContractTests: 10 passed
SceneWorkspaceTeardownTests: 16 passed
total: 38 passed, 0 failed, 0 skipped, 0 expected failures
result: Passed
```

The focused owner/policy suites were also run before the final bounded command
on the same simulator with result bundle
`/private/tmp/setos-m6-002-003-correction-focused.xcresult`: 16 passed, 0
failed, and 0 skipped (6 ownership and 10 workspace-contract tests).

The correction tests pin both failure modes: a source contract confirms the
constructor disables automatic session configuration before owner attachment,
and the deterministic interruption ordering test sends interruption and
ended callbacks before yielding to MainActor, proving one safety application,
playback stop, and recovery for the latest generation.

The required mutation grep (exit code 0; no output) was:

```sh
rg -n 'session\.(run|pause)|session\.delegate' shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift
```

The only lifecycle mutations are the `runtime.run`/`runtime.pause`/
`runtime.delegate` paths inside `ARSceneContainer.Coordinator`, including its
replacement and deinitialization release paths; the view model has no direct
mutation sites. `git diff --check` also exited 0.

## Limitations

The iPhone Air simulator verifies ownership, generation fencing, teardown, and
configuration-policy contracts only. It does not claim physical AR tracking
quality, plane detection, depth quality, or device hardware support. No
elapsed-time readiness, fake frame/plane success, physical-device run, route
change, scene reconstruction, or environment feature was introduced.
