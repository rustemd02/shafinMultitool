# M9-006 — Pro Controls contract

Status: **closed on the current store**.

`ProCameraControlContracts` locks the 1.0 surface: 13 controls with honest
tiers — format/resolution+FPS and torch are `available` on their real
owners; exposure/EV/manual/focus/WB variants are `legacyOnly` (live in the
unwired legacy `CameraService` path, shipping only with Coach-path wiring);
audio meter is `post10` (no owner exists); histogram/zebra/peaking have no
control case at all and are documented as excluded.

Verification: `ProCameraControlContractsTests` 4/4 on permitted iPhone 17e
(`/private/tmp/m9-006-tests.xcresult`): exact coverage, real owners,
exclusion integrity, torch availability.
