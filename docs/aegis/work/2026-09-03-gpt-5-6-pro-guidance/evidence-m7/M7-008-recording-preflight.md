# M7-008 — recording preflight

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

A dedicated `RecordingStartPreflighting` owner
(`Services/Recording/RecordingPreflight.swift`) validates every mandatory
precondition of a start request **before any recorder is created, any output
URL is allocated, and the controller lifecycle leaves its between-takes idle
state**. The serialized controller runs it inside the start task and throws
the typed failure to the caller; the UI never enters recording because the
lifecycle projection only flips to `.recording` after writer acceptance.

Deterministic validation order in `StandardRecordingStartPreflight`:

1. **Format** — positive dimensions/FPS (`.writerInputRejected`).
2. **Codec support** — through the M7-005 `RecordingCodecSupportChecking`
   seam (`.writerInputRejected`).
3. **Pixel format** — an explicitly zero FourCC is rejected.
4. **Disk budget** — conservative M7-017 estimate via `RecordingArtifactStore`
   (`.insufficientStorage`); a capacity-query failure fails closed.
5. **Microphone** — read-only `AVAudioApplication` posture check for
   sound-required takes (`.microphoneDenied`). The contextual
   request/denial flow stays owned by M7-004's permission owner; this is the
   last-line defense.
6. **Audio session** — the serialized `AudioSessionCoordinator` must not be
   interrupted (`.audioSessionUnavailable`).

Three new typed `RecorderFailure` cases: `.microphoneDenied`,
`.insufficientStorage`, `.audioSessionUnavailable` (all recoverable; existing
localized recorder error surface covers them via the recording error band).

The production convenience initializer wires the disk-budget closure to the
real artifact store; tests inject static checkers and budget closures.

## Acceptance criteria evidence

- One failure fixture per precondition:
  `RecordingPreflightTests` — invalid dimensions, unsupported codec, zero
  pixel format, disk-below-requirement, disk-query-failure (fail closed),
  denied microphone, unavailable audio session, plus the satisfied baseline
  that returns `nil`.
- Rejection happens before recording: `testStartPreflightRejectionHappensBeforeRecorderCreation`
  (controller integration) asserts zero recorders created, no source token,
  lifecycle back to `.idle`, typed `.insufficientStorage` thrown.
- Localized + recoverable: failures are typed `RecorderFailure`s consumed by
  the existing recording error surface (M1-018 mapping lane).

## Narrow verification

Package B focused run (iPhone Air simulator, iOS 26.5):
**79/79 PASS, 0 failures** (`SerializedMediaRecorderTests`,
`RecordingPreflightTests`, `SceneRecordingControllerTests`,
`RecordingStartTeardownRaceTests`; xcresult
`/private/tmp/m7-pkgB-tests-r2.xcresult`). `git diff --check` clean.

## Honest boundaries

- "Active project" precondition remains the ViewModel's caller contract (the
  VM only starts takes inside an active workspace); `SceneGeneratorViewModel`
  is outside this lane's ownership, so the controller cannot re-validate it.
- The production microphone check reads real permission posture; the request
  flow itself stays with the M7-004 owner (not duplicated here).
