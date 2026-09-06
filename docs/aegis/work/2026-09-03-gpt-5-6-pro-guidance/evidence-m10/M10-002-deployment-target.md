# M10-002 — deployment target

Status: **verified on the current store; no production change required**.

- All targets agree: app/unit/UI at 17.0 (M0-006 matrix; the unit 17.2
  mismatch is fixed there). Dependencies (Pods/SnapKit platform ios 14.0)
  are satisfied above by the app floor.
- Availability guards cover newer APIs: `videoRotationAngle` (iOS 17.0+)
  behind `@available` protocols with the `applyMirroring` fallback on the
  `else` path (`CameraDataOutputConnectionConfigurator`); call sites use
  `if #available(iOS 17.0, *)` with pre-17 behavior preserved.
- Minimum documented with hardware implications: iPadOS/iOS 17.0 in
  `ipad-platform-contract-v1.md` — devices that cannot run 17 are
  unsupported; no API below the floor is referenced unguarded
  (grep-verified: every `@available`/`#available` site pairs with a
  fallback path).
