# M6-018 — tracking quality

Status: **implemented and verified on the current store**.

## Closed acceptance columns

1. **Tracking reason maps to one bounded action.** `ARKitTrackingLimitation`
   (excessiveMotion, insufficientFeatures, initializing, relocalizing,
   unavailable — exhaustive, `CaseIterable`) carries exactly one
   `guidanceCopyKey` each; the AR delegate maps every `ARCamera.TrackingState`
   (normal → available, notAvailable → unavailable, limited(reason) → the
   matching bounded reason, `@unknown` fail-closed to insufficientFeatures)
   into `updateSurfaceTrackingPosture`. Five new EN+RU copy keys give one
   bounded guidance action per reason.
2. **Controls disabled semantically and accessibly.** `recordButton` (legacy
   shell `refreshUI`) dims and carries a disabled VoiceOver hint while
   tracking is unstable, keeping its accessibility identifier; marking entry
   is blocked at the VM gate with localized guidance (M6-006). Marking and
   recording share the one `requiresStableTrackingForCapture` signal.

## Verification

`SurfaceSearchPolicyTests` 4/4 on permitted iPhone 17e
(`/private/tmp/m6-018-tests.xcresult`): M6-006 triple plus the new
`testEveryTrackingReasonMapsToOneBoundedGuidanceAction` pinning all five
reason→copy mappings and the capture gate.

## Honest boundary

Physical tracking-reason behavior on device remains M13 qualification.
