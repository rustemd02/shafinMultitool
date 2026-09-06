# M9-009 / M9-010 — auto exposure/EV and manual exposure

Status: **closed on the current store**.

## Closed defects (legacy path)

- `changeISO` force-unwrapped the device (crash when nil), wrote without
  checking `isExposureModeSupported(.custom)`, and never clamped. Now:
  nil device → nil, unsupported mode → nil, ISO clamps to the active
  format's [minISO, maxISO], and the applied value reads back
  (`device.iso`). Callers persist only the applied value.
- `changeWB` had the same crash shape plus unnormalized gains. Now:
  nil/unsupported → nil, non-positive temperature rejected, gains
  normalized to [1.0, maxWhiteBalanceGain], applied gains read back.
- EV/auto behavior: auto exposure survives orientation and allowed lens
  switch through the session-owned device (M1-006 fence); the 180° preset
  converts to duration arithmetically (1/48s at 24fps, pinned by test)
  with device support checked at apply time.

## Verification

`ExposureWhiteBalanceTests` 3/3 on permitted iPhone 17e
(`/private/tmp/m9-009-010-tests.xcresult`): fail-closed without device,
invalid WB rejected, 180° conversion exact.
