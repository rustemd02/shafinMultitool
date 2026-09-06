# M9-005 — torch

Status: **closed on the current store**.

## Truthful torch owner (`CameraManager`)

- New `setTorchActive(_:) -> Bool?` and `isTorchActive: Bool?` on the lens
  owner, serialized on the session queue against `currentInput?.device`.
- Unsupported configurations report `nil` (no input, or device without
  `hasTorch) — the UI hides/disables truthfully instead of showing a dead
  toggle. The legacy `CameraService.switchFlashlight` has no callers and
  stays untouched.
- State resets on owner release by construction: `releaseOnSessionQueue`
  detaches `currentInput`, so the device handle (and any torch state on
  it) cannot survive; afterwards the accessors report `nil`.
- Lens replacement goes through the same detach path, so a torch cannot
  leak across a lens switch either.

## Verification

`CameraTorchTests` 2/2 on permitted iPhone 17e
(`/private/tmp/m9-005-tests-r3.xcresult`): unsupported-without-input fails
closed with nil; release detaches to nil.

## Honest boundary

Physical torch hardware behavior on device remains M13; the simulator has
no torch, so the suite proves the truthfulness contract, not illumination.
