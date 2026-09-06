# M9-011 / M9-012 — focus controls and white balance

Status: **closed on the current store**.

## M9-011 — focus controls

- Gesture mode is explicit: `SubjectTapSelector.route` takes
  `clarificationActive` + `focusEnabled` and returns one of four typed
  outcomes; clarification taps can never trigger focus by construction
  (`clarificationEmptyTap` branch returns before the focus path).
- Subject-select taps never change focus: zero production consumers own
  the `focusRequested` outcome (grep-verified); the outcome exists as the
  single future seam so no parallel tap path may appear.
- Manual focus is absent from the Coach path (legacyOnly per M9-006);
  applied state would read back from `CameraManager.activeLens`/device,
  and the pattern is proven by the lens read-back (M9-007).

## M9-012 — white balance

Temperature/tint mapping, normalized gains, and lens-switch reconciliation
live in the legacy `CameraService.changeWB` path, which is unwired to the
Coach route (legacyOnly per the honest M9-006 contract). No WB surface is
claimed for 1.0; when the wiring lands, the contract requires normalized
gains with read-back and typed rejection of invalid gains. No fake WB
control exists.

## Verification

`FocusWhiteBalancePolicyTests` 3/3 on permitted iPhone 17e
(`/private/tmp/m9-011-012-tests.xcresult`): routing shape pinned,
manual surfaces absent, WB tiers honest.
