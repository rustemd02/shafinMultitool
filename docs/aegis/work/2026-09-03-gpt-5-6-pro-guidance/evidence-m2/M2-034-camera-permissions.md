# M2-034 Camera permission UI receipt

Date: 2026-09-05
Branch: `codex/set-os-m2-034`
Simulator: iPhone 17e, iOS 26.5, `1F680A42-CEB3-43E8-9CED-52F874962A62`
Physical device / iPhone 17 Pro: not used

## Change

- `CameraCoachEntryFlowModel` now fences every async snapshot/request commit
  with cancellation and a monotonic operation generation.
- Foreground rechecks are accepted only from `.blocked` (or an explicit
  ready-state caller); lifecycle callbacks cannot replace intro,
  permission-context, requesting, or initial resolving.
- Existing Camera Coach view, PermissionClient owner, catalog values, Settings
  URL, and accessibility IDs were reused unchanged.
- The DEBUG UI entry fixture now uses the existing deterministic
  `CameraManagerTestConfiguration.ready` seam with a DEBUG-only session runner
  and isolated notification center. Authorized ready-entry and
  denied→authorized foreground recheck exercise the existing production root
  without claiming camera hardware discovery.
- The authorized-return UI assertion checks the canonical
  `camera_coach_live_surface` root. The simulator has no physical camera
  frames, so `camera_coach_seeking_status` is not a truthful fixture contract.
- Focused model coverage now includes intro/recheck gating, canceled resolve
  and request callbacks, plus RU+EN visible/accessibility catalog coverage.

## Verification

- UI entry flow (9 tests, iPhone 17e):
  `xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -collect-test-diagnostics never -only-testing:shafinMultitoolUITests/CameraCoachEntryFlowUITests -derivedDataPath /private/tmp/m2-034-correction-ui-dd-r2 -resultBundlePath /private/tmp/m2-034-correction-ui-r2.xcresult CODE_SIGNING_ALLOWED=NO`
  → `Executed 9 tests, with 0 failures (0 unexpected)`;
  result: `/private/tmp/m2-034-correction-ui-r2.xcresult`.
- Focused model + added RU/EN presentation test (16 tests, iPhone 17e):
  `xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -collect-test-diagnostics never -only-testing:shafinMultitoolTests/CameraCoachEntryFlowModelTests -only-testing:shafinMultitoolTests/CameraCoachEntryPresentationTests/testCameraEntryCopyHasRussianAndEnglishVisibleAndAccessibilityValues -derivedDataPath /private/tmp/m2-034-correction-unit-r2 -resultBundlePath /private/tmp/m2-034-correction-unit-r2.xcresult CODE_SIGNING_ALLOWED=NO`
  → `Executed 16 tests, with 0 failures (0 unexpected)`;
  result: `/private/tmp/m2-034-correction-unit-r2.xcresult`.
- Focused lifecycle checks also passed: authorized return 1/1 at
  `/private/tmp/m2-034-correction-auth-r2.xcresult`; denied→authorized
  foreground recheck 1/1 at `/private/tmp/m2-034-correction-denied-r2.xcresult`.
- `git diff --check`: PASS.

Boundaries: no Camera overlay, route, AR, recording, Generator, thesis, or
execution-state files changed. Final commit hash is reported in the handoff.
