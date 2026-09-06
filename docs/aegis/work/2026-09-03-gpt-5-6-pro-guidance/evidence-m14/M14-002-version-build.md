# M14-002 — version/build

Status: **verified on the current store**.

- `MARKETING_VERSION = 1.0` → `CFBundleShortVersionString` (valid
  three-component marketing version for a 1.0 release).
- `CURRENT_PROJECT_VERSION = 1` → `CFBundleVersion` (monotonic build
  counter, starts at 1).
- Consistent across all three targets (app/unit/UI share the same
  version keys — verified in the M0-006 matrix).
- Uniqueness in App Store Connect cannot be proven locally and is
  recorded as a submission-time check; the RC manifest records `1.0 (1)`.
