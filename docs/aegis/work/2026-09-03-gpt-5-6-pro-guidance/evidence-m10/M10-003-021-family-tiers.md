# M10-003 / M10-021 — device family and performance tiers

Status: **closed on the current store**.

## M10-003 — device family

`TARGETED_DEVICE_FAMILY = 1,2` (universal, no compatibility mode);
Camera route `.all` orientations, Scenes route `.landscape`, shell
delegates to the active child (fallback `.all` pre-route). Pinned by
`iPadDeviceFamilyTests` 3/3 against live controller instances.

## M10-021 — performance tiers

Locked matrix in `docs/implementation/ipad-performance-tiers-v1.md`:
A12-class / compact A15-class / M-series regular-width with governor
behavior per thermal state; budgets cover neural (heavy-model gate +
cadences), AR (frame interval), recording (backpressure policy +
per-take thermal record), Generator UI (effective performance), and
Storyboard (scheduler-bounded re-render, no per-frame timers). Tiers are
selected by live thermal/battery behavior, never a device-name allowlist.

Verification: `iPadPerformanceTierTests` 2/2 (monotonic degradation,
heavy-model shed at critical, snapshot truthfulness) + family 3/3 = 5/5
on permitted iPhone 17e (`/private/tmp/m10-003-021-tests.xcresult`).
Matrix execution on hardware remains M13.
