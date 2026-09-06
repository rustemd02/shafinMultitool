# M4-021 — model version/rollback

Status: **closed on the current store**.

## Registry contract (`CameraModelRegistry.swift`)

- Exactly one approved bundled model may be active. The pure `activation`
  gate admits only a present artifact whose contract version, calibration
  version, and both 64-hex receipt hashes match the frozen contract;
  anything else yields `.unavailable` or `.mismatchDisabled` — neural
  advice stays disabled and the deterministic heuristic path owns the
  advice with the honest unavailable state (no guessing, no proxy).
- The approved artifact is currently `nil`: no converted model ships in
  this build (M4-016 conversion pending), so the registry boots to
  `.unavailable` by construction.
- Rollback: `rollbackTarget` records the last known-good compatible
  version; restore happens only through an app update carrying that
  artifact — no download, synthesis, or runtime hot-swap exists.

## Verification

`CameraModelRegistryTests` 6/6 on permitted iPhone 17e
(`/private/tmp/m4-021-tests.xcresult`): unavailable, active, contract
mismatch, calibration mismatch, malformed receipt, rollback targeting.
