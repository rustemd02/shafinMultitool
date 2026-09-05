# M6-004 — Camera/AR ownership timeline

Status: complete (local implementation and focused simulator verification)

Branch: `codex/set-os-m6-004`

Worktree: `/Users/unterlantas/.codex/worktrees/shafinMultitool/m6-004-camera-ar-interop`

Base commit: `ea9d7ab03541d9c26996b93c4920004c94c68a8b`

## Implementation evidence

`CommercialCameraCoachRoute` now closes the production Camera Coach route's
re-entry boundary before awaiting `CameraViewModel.releaseAndWait()`. The new
route-only `CameraViewModel.beginRouteExit()` invalidates lifecycle and lens
intents, cancels in-flight restart/lens tasks, clears camera presentation and
polling work, and rejects later `start()`, `startAndWait()`, `togglePause()`,
and `switchLens(to:)` calls. Ordinary lifecycle release/restart remains
unchanged because only route teardown sets this terminal intent.

The route still awaits the existing shared release operation. Its order remains
CameraManager stop, analysis-pipeline/scheduler release, and CameraManager
configuration release. The manager's completion leaves the session lifecycle
idle/unconfigured and its serial session queue has drained before the shell can
construct the Scene route. There is no timing or animation delay involved.

`CommercialShellViewController` remains the single transition owner. It awaits
old-route deactivation, checks the typed `CommercialRouteDeactivationResult`,
removes the old child only for `.released`, and constructs the requested route
only after that acknowledgement. A blocked result leaves the old child, route,
selection, and mode control in place. Pending selections remain coalesced by
the same transaction and stale completions cannot install a newer route.

On the reverse path, `CommercialSceneLibraryRoute` continues to await the
existing `SceneWorkspaceTeardownProviding` owner. The coordinator awaits
recording/playback cleanup and persistence before its synchronous
`pauseAndDetach` callback. The accepted `ARSessionOwner` release seam then
pauses/detaches its runtime and advances the AR session generation. No second
router, global registry, or speculative protocol hierarchy was added.

## Deterministic integration coverage

`CommercialShellRoutingTests/testProductionCameraARBoundaryAwaitsTerminalOwnersAndRetriesSafely()` binds a real production
`CommercialShellComposition` to real `CameraViewModel` and `CameraManager`
instances, a fake serial camera session runner, the accepted
`ARSceneContainer.Coordinator`, and `SceneWorkspaceTeardownCoordinator`.
It proves:

- Camera → Scene waits for the fake CameraManager stop/release gate; no Scene
  construction or AR run occurs while Camera is still owned.
- The old Camera child remains shell-owned during the blocked release, while
  late `start`, resume, and lens requests are rejected; repeated selections do
  not double-start the camera.
- AR → Camera reports the typed `.persistenceFailed` result, preserves the
  Scene route and its localized/typed block reason, and does not start the
  replacement Camera.
- Retrying through the shell owner awaits persistence and AR pause/detach before
  constructing and starting the replacement Camera.
- The production route's full release call is exercised directly; reverting it
  to frame-stop leaves the manager configured and fails the integration
  assertions.

Existing routing, launch-composition, CameraManager, AR ownership, and Scene
workspace suites retain coverage for idempotence, stale generations,
concurrent callers, blocked teardown, and normal release/restart behavior.

## Verification receipt

Focused command (exit code 0):

```sh
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone Air,OS=26.5' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:shafinMultitoolTests/CommercialShellRoutingTests -only-testing:shafinMultitoolTests/CommercialShellLaunchCompositionTests -only-testing:shafinMultitoolTests/CameraViewModelLifecycleTests -only-testing:shafinMultitoolTests/ARSessionOwnershipTests -only-testing:shafinMultitoolTests/CameraManagerLifecycleTests -only-testing:shafinMultitoolTests/SceneWorkspaceTeardownTests -derivedDataPath /private/tmp/setos-m6-004-final-dd-20260905 -resultBundlePath /private/tmp/setos-m6-004-final-20260905.xcresult CODE_SIGNING_ALLOWED=NO
```

Result bundle: `/private/tmp/setos-m6-004-final-20260905.xcresult`

```text
device: iPhone Air, iOS Simulator, OS 26.5
ARSessionOwnershipTests: 6 passed
CameraManagerLifecycleTests: 20 passed
CameraViewModelLifecycleTests: 12 passed
CommercialShellLaunchCompositionTests: 14 passed
CommercialShellRoutingTests: 12 passed
SceneWorkspaceTeardownTests: 16 passed
total: 80 passed, 0 failed, 0 skipped, 0 expected failures
result: Passed
```

Summary command (exit code 0):

```sh
xcrun xcresulttool get test-results summary --path /private/tmp/setos-m6-004-final-20260905.xcresult
```

`git diff --check` exited 0. The build emitted existing SDK/deprecation and
Swift-concurrency warnings elsewhere in the target; no new production warning
was introduced by the route-fence implementation.

## Boundary and limitations

This receipt is simulator contract evidence only. The iPhone Air iOS 26.5
simulator does not prove physical camera availability, AR tracking quality,
plane detection, depth behavior, or hardware timing. No physical iPhone 17 Pro
or iPhone 13 was used, and no physical camera/AR proof is claimed.
