# M9-007 — capture configuration serialization

Status: **verified on the current store; no production change required**.

## Singular ownership

- Every `beginConfiguration/commitConfiguration` pair and every device
  `lockForConfiguration/unlockForConfiguration` pair lives on the
  manager's serial `sessionQueue`, fenced by the M1-003 session generation
  (stale start/lens work resumes cancelled instead of reconfiguring after
  teardown). No second configuration owner exists on the Coach route.
- UI state reads back from the device: after every start/resume
  `currentLens = cameraManager.activeLens` and
  `availableLenses = cameraManager.availableLenses` — never a guessed
  default (a telephoto selection survives pause without flashing wide).
- Failed/clamped values surface typed: `CameraLensSwitchResult`
  (success/noOp/failure with reason) reaches the VM presentation state
  and the localized switching/failed status; an unavailable lens is never
  clamped to a neighbor.

## Verification

`CaptureConfigurationTests` 2/2 on permitted iPhone 17e
(`/private/tmp/m9-007-tests.xcresult`): typed failure surfacing +
device read-back after start.
