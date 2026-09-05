# M7-026 — playback

Status: **implemented and verified on the current store**.

## Behavior delivered

- The review player path (lease-gated `AVPlayerViewController` presentation,
  release on dismiss/disappear/deinit, audio-session playback lease via the
  serialized coordinator) already satisfied route lifecycle correctness
  (M1-017 ownership). This task closed the missing failure leg:
  `AVURLAssetPlaybackProbe` (M7-026 adapter in `AppleRecordingAdapters.swift`)
  checks existence, `isPlayable`, and a video track before presentation; a
  missing/corrupt artifact releases the playback lease and surfaces the
  localized recorder error band instead of an empty player.
- Orientation and audio travel as track metadata written by M7-007/M7-005;
  `AVPlayerViewController` applies the preferred transform and plays the
  audio track when present — no shell-side rotation logic exists to drift.

## Verification

`AppleRecordingAdaptersTests` 16/16 on permitted iPhone 17e
(`/private/tmp/m7-026-tests-r2.xcresult`): the new
`testPlaybackProbeAcceptsRealMovieAndRejectsMissingAndCorruptFiles` proves a
real written movie plays-probe-true while garbage and missing files fail
closed; the writer/orientation/codec suites stay green.

## Honest boundary

Upright playback for every physical orientation/lens configuration remains
M13 device qualification.
