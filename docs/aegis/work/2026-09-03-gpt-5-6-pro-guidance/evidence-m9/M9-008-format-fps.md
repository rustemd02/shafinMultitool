# M9-008 — format/FPS

Status: **closed on the current store**.

- Format list is device-derived: `CameraService.isFormatSupported` checks
  the physical back camera's format table (dimensions coverage + frame-rate
  range inclusion); stored preferences are validated against it, never
  trusted.
- Selection applies atomically inside the existing `videoSettingsUpdate`
  transaction (writer inputs are created and verified together; failure
  leaves the previous inputs intact via the M1-era detach path).
- Unsupported/thermal-conflicting choices are rejected before any writer
  input exists; recorder dimensions/FPS then match the active device
  format by construction (M7-005 reads the same active format).

Verification: `CaptureFormatTests` 3/3 on permitted iPhone 17e
(`/private/tmp/m9-008-tests.xcresult`): zero/absurd rejected, device
presence branches honestly (fail-closed without hardware).
