# M9-013 — audio meter

Status: **closed on the current store**.

`CameraManager` owns a truthful meter on the same session: an
`AVCaptureAudioDataOutput` attached only under microphone grant, with the
same attach/detach lifecycle as the video delegate. Levels are 16-bit PCM
RMS normalized to 0...1; unreadable buffers clear the level instead of
fabricating one. Without permission, without a running owner, or after
release the meter reports `nil` (unavailable) — the UI hides/disables
truthfully. No fixture animation exists in Release.

The M9-006 contract entry for `audioMeter` is updated from `post10` to
`available` on this owner.

Verification: `CameraAudioMeterTests` 2/2 on permitted iPhone 17e
(`/private/tmp/m9-013-tests.xcresult`). Physical microphone behavior
remains M13.
