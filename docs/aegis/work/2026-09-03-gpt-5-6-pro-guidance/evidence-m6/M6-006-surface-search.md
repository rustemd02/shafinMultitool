# M6-006 — surface search

Status: **implemented and verified on the current store**.

## Closed acceptance gaps

All four verifier columns were gapped; all are now closed:

1. **Search begins only after ready.** `toggleMarkingMode` rejects entry
   with localized retry guidance + diagnostic log when `!isARSessionReady`
   instead of a silent no-op; existing `canToggleMarkingMode` busy-gating
   unchanged.
2. **Tracking limitations reported.** The AR delegate propagates every
   non-normal tracking state (`notAvailable`, `limited`) to
   `updateSurfaceTrackingPosture(isLimited:)` on the VM, which publishes
   typed localized retry/reposition guidance and keeps the invalid-fallback
   path from selecting anything; recovery renews the search window.
3. **No fake surface.** The fallback projection chain
   (existingPlaneGeometry → estimatedPlane) is unchanged in kind, but a
   search past its bounded window cannot select at all — it publishes
   timeout guidance and renews the window for the next tap.
4. **Retry/reposition guidance after bounded timeout.** 8 s search window
   (`surfaceSearchWindowSeconds`), three new copy keys in EN+RU
   (mark_not_ready, tracking_limited, surface_timeout) resolved through the
   production catalog.

## Verification

New `SurfaceSearchPolicyTests` 3/3 on permitted iPhone 17e
(`/private/tmp/m6-006-tests-r3.xcresult`): pre-ready entry rejected with
guidance, limitation → guidance and restore renewal, expired window selects
nothing.

## Honest boundary

Physical surface-detection behavior on device remains M13 qualification.
