# M9-001 — lens contract

Status: **production owner verified on the current store; no production change required**.

## Verified contract

- **Only discovered built-in devices.** `discoverAvailableLenses` enumerates
  exactly `CameraLens.allCases` (ultraWide/wide/telephoto) through
  `AVCaptureDevice.default(deviceType, for: .video, position: .back)` — a lens
  is exposed only when the physical device exists; at most one telephoto
  entry; duplicates structurally impossible (`!discovered.contains`).
- **No synthetic 0.5×/1×/2× labels.** UI labels come from
  `CameraLensDescriptor.displayLabel`: the physical WIDE/ULTRA/TELE names by
  default, a `%.1f×` magnification only when computed truthfully from the
  measured wide-vs-device field-of-view ratio, or a measured mm value —
  never a guessed focal length (grep-verified: no `×`, `0.5`, or focal
  literal in the lens surface).
- **Real device/FOV capability mapping.** `deviceType` maps each lens to its
  `builtIn*Camera` type; the magnification math guards zero/negative FOV
  and degrades to the plain label when unmeasurable.
- The committed inventory test pins all of this
  (`testPhysicalLensInventoryHasOneTruthfulTelephotoDescriptor`); lens
  transaction rollback invariants hold via `CameraLensSwitchTransactionTests`.

## Verification

5/5 (`testPhysicalLensInventoryHasOneTruthfulTelephotoDescriptor` +
`CameraLensSwitchTransactionTests` 4/4) on permitted iPhone 17e
(`/private/tmp/m9-001-tests.xcresult`).

## Honest boundary

Which physical lenses a real device exposes is device hardware; simulator
evidence proves the discovery contract, not a device inventory.
