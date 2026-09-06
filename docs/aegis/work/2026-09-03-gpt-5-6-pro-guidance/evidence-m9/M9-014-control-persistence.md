# M9-014 — control persistence

Status: **closed on the current store**.

- Preferences restore only when supported: `setDefaultSettings` validates
  the stored resolution/FPS through the M9-008 device gate and falls back
  explicitly to documented defaults (3840×2160/25fps) otherwise; the pure
  `restoredCaptureSettings` policy is unit-tested.
- Applied-only persistence: ISO/WB writes persist only the read-back
  applied values (M9-009/010), so a rejected change never pollutes stored
  settings.
- No setting starts capture: `setDefaultSettings`/`prepareRecorder` only
  configure the writer; capture starts exclusively through the permission-
  gated start path.

Verification: `ControlPersistenceTests` 3/3 on permitted iPhone 17e
(`/private/tmp/m9-014-tests.xcresult`).
