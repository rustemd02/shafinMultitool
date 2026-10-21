# CAM-004 — `change_camera_angle` fail-closed verification receipt

Date: 2026-09-22. HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`). The working tree was already dirty with user-owned documentation additions, modifications and deletions; those changes were preserved. This verification changed only the CAM-004 tracker row and this receipt.

## Evidence

- **Command:**
  `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' -derivedDataPath /private/tmp/setos-cam001/dd -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -collect-test-diagnostics never -only-testing:shafinMultitoolTests/ActionVerifierTests -only-testing:shafinMultitoolTests/UserMovementObserverTests test`
- **Result:** exit `0`; `** TEST SUCCEEDED **`.
- **Counts:** `ActionVerifierTests` 28 executed / 0 failures / 0 skipped; `UserMovementObserverTests` 39 / 0 / 0; total 67 / 0 / 0.
- **Code inspected:** `shafinMultitool/Multitool2Module/Models/CameraAnalysis/UserMovementObserver.swift` (`ActionIntent` mapping, lines 846–875; `evaluate`, lines 1091–1225); `shafinMultitool/Multitool2Module/Models/CameraAnalysis/ActionVerifier.swift` (unsupported-family gates, lines 36–56 and 369–377).
- **Tests inspected:** `shafinMultitoolTests/ActionVerifierTests.swift:1306–1328` (`testUnsupportedBackgroundActionNeverBecomesImproved`); `shafinMultitoolTests/UserMovementObserverTests.swift:444–457` (unsupported action mapping) and `:546–567` (horizon-change counterexamples).
- **Contract result:** `change_camera_angle` has no qualified contour/occlusion metric and therefore resolves to unsupported/incomparable; horizon rotation cannot produce `improved`. No lateral/background success path is claimed until an honest metric exists.
- **Temporary space:** reused existing `/private/tmp/setos-cam001/dd`; no new DerivedData directory or separately requested `.xcresult` bundle was created. No historical temp/evidence was deleted.
- **Diff check:** `git diff --check -- docs/implementation/APP_STORE_RELEASE_TRACKER.md docs/implementation/receipts/2026-09-22-cam-004-verification.md` exited `0`.

## Scope and residual risk

This is a focused serial simulator verification of the two owning test classes. It does not qualify a contour/occlusion metric or prove a supported lateral/background path; the action intentionally remains incomparable until that metric is implemented and verified.
