# M6-004 — Camera/AR ownership timeline

Status: complete (local implementation)

Branch: `codex/set-os-m6-004`

Worktree: `/Users/unterlantas/.codex/worktrees/shafinMultitool/m6-004-camera-ar-interop`

Base commit: `ea9d7ab03541d9c26996b93c4920004c94c68a8b`

## Implementation evidence

`CommercialCameraCoachRoute` now maps its production `CameraViewModel` route
deactivation to `releaseAndWait()`, not the shorter frame-stop operation. The
existing ViewModel release operation is shared and awaited, and its terminal
order is: stop frame production, release the analysis pipeline and scheduler
registrations, then await `CameraManager.releaseAndWait()`. The manager's
release completion leaves its lifecycle `idle`, configuration `unconfigured`,
and advances its session generation before the shell can construct the next
route.

The existing `CommercialShellViewController` remains the single transition
owner. It awaits the old route's deactivation, checks the typed
`CommercialRouteDeactivationResult`, removes the old child only for
`.released`, and constructs the requested route only after that boundary. A
`.blocked` result leaves the old child, route, selection, and mode control in
place. Pending selections remain coalesced by the same transaction and are
discarded when container teardown supersedes the transition.

On the reverse path, `CommercialSceneLibraryRoute` continues to await the
existing `SceneWorkspaceTeardownProviding` owner. The coordinator awaits
recording/playback cleanup and persistence before its synchronous
`pauseAndDetach` callback. That callback reaches the accepted
`ARSessionOwner` release seam, which pauses and detaches the runtime and
advances the AR session generation. The owner already exposes terminal
`isReleased`, `releaseCount`, and generation observability; no second router,
registry, or protocol hierarchy was added.

## Deterministic coverage

- `CommercialShellRoutingTests/testMutualExclusionFenceWaitsForPreviousOwnerRelease()` proves both directions: no Scene construction before Camera release and no replacement Camera construction before Scene/AR release.
- `CommercialShellRoutingTests/testBlockedDeactivationRetainsChildAndSelection()` proves a blocked release preserves the active route and does not construct the second owner.
- `CommercialShellRoutingTests/testRapidSelectionsCoalesceToLastRequestedSection()` and `testContainerTeardownSuppressesStalePendingSelection()` cover concurrent selection coalescing and stale completion suppression.
- `CommercialShellLaunchCompositionTests` covers shared/idempotent camera release and the existing awaited route-construction fence.
- `CameraManagerLifecycleTests` covers concurrent starts/stops, idempotent release, stale start fencing, terminal idle/unconfigured state, and the stop/release session-generation increments.
- `ARSessionOwnershipTests` covers one runtime owner, terminal idempotent pause/detach, release-count and generation fencing, and stale callback rejection.
- `SceneWorkspaceTeardownTests` covers awaited recording/persistence/release order, concurrent callers, blocked persistence, route retention, and late callback suppression.

## Verification receipt

Required bounded command (exit code 0):

```sh
xcodebuild test -quiet -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone Air,OS=26.5' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:shafinMultitoolTests/CommercialShellRoutingTests -only-testing:shafinMultitoolTests/CommercialShellLaunchCompositionTests -only-testing:shafinMultitoolTests/ARSessionOwnershipTests -only-testing:shafinMultitoolTests/CameraManagerLifecycleTests -only-testing:shafinMultitoolTests/SceneWorkspaceTeardownTests -derivedDataPath /private/tmp/setos-m6-004-dd -resultBundlePath /private/tmp/setos-m6-004.xcresult CODE_SIGNING_ALLOWED=NO
```

Result bundle: `/private/tmp/setos-m6-004.xcresult`

```text
device: iPhone Air, iOS Simulator, OS 26.5
ARSessionOwnershipTests: 6 passed
CameraManagerLifecycleTests: 20 passed
CommercialShellLaunchCompositionTests: 14 passed
CommercialShellRoutingTests: 12 passed
SceneWorkspaceTeardownTests: 16 passed
total: 68 passed, 0 failed, 0 skipped, 0 expected failures
result: Passed
```

Supplementary summary command (exit code 0):

```sh
xcrun xcresulttool get test-results summary --path /private/tmp/setos-m6-004.xcresult
```

`git diff --check` exited 0. The build emitted pre-existing SDK/deprecation
warnings; no warning was introduced by the M6-004 source diff.

## Boundary and limitations

This receipt is simulator contract evidence only. The iPhone Air iOS 26.5
simulator does not prove physical camera availability, AR tracking quality,
plane detection, depth behavior, or hardware timing. No physical iPhone 17 Pro
or iPhone 13 was used, and no physical camera/AR proof is claimed.
