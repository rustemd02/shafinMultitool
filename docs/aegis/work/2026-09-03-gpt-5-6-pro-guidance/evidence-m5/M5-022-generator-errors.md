# M5-022 — generator errors

Status: **closed on the current store**.

## Closed defects

1. **Unit twin measured the wrong contract.** `testARFailureMessageUsesContainerPresentationLocale`
   delivered `didFailWithError` from a never-attached `ARSession`, which the
   M6-002 generation fence correctly rejects. The fixture now attaches a
   runtime owning the very session it fails and waits bounded for the
   MainActor publish hop — passes deterministically.
2. **UI twin asserted an obsolete message.** The simulator AR failure path
   publishes the typed localized world-tracking-unavailable recovery from
   the M6-002/003 owner, not the raw `ARSession` error string. The failure
   hierarchy in the original failure capture proves the band renders
   exactly `"AR world tracking is unavailable on this device. Use a device
   that supports AR world tracking."` in EN. The test asserts that copy now.

## Interim instrumentation

Three temporary DEBUG print markers were added during diagnosis and fully
removed before the passing run (verified by grep: zero markers remain in
`ARSceneContainer.swift`, `SceneGeneratorViewModel.swift`,
`SceneGeneratorView.swift`). Only test-file changes ship.

## Verification

`testARFailureMessageUsesContainerPresentationLocale` passed (unit lane);
`testGeneratorENErrorBandUsesProductionLocale` passed on permitted iPhone 17e
(`/private/tmp/m5-022-ui-r4.xcresult`).
