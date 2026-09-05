# M7-007 — orientation metadata

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

Orientation/mirroring now travels as track metadata; frames are never rotated.

- `AppleRecordingTrackTransformMapper` (AppleRecordingAdapters.swift) maps the
  frozen M7-001 `RecordingTrackTransformMetadata` onto a `CGAffineTransform`
  with a fixed, documented convention: portrait = identity,
  `portraitUpsideDown` = 180°, `landscapeLeft` = −90°,
  `landscapeRight` = +90°, and mirroring composes a horizontal flip under the
  orientation rotation.
- `AVAssetWriterRecordingWriter` writes the transform to
  `videoInput.transform` when the configuration supplies metadata, so the
  QuickTime track carries orientation while encoded natural size keeps the
  source pixel dimensions.
- `RecordingConfiguration.trackTransform` carries the metadata (default `nil`
  = previous identity behavior); `SceneRecordingController.start` accepts an
  optional `trackTransform:` parameter (default `nil`) and threads it into the
  writer configuration.

## Acceptance criteria evidence

| Criterion | Evidence |
|---|---|
| Metadata is written without rotating frames | `testWrittenAssetTrackCarriesOrientationTransformWithoutRotatingDimensions`: real H.264 take with `landscapeLeft` metadata — persisted `preferredTransform` equals the mapper matrix, natural track size stays 640×480. |
| Dimensions/transform are consistent | Same test asserts natural size == source dimensions while the transform conveys rotation; the M7-005 controller test asserts the metadata reaches the writer configuration unchanged. |
| Deterministic mapping for every supported orientation | `testTrackTransformMapperProducesDeterministicMetadataMatrices` (4 orientations × mirroring, matrix-element assertions). |

## Production wiring boundary (honest)

The controller seam and the writer path are complete, but the **caller-facing
orientation value is not yet supplied by production**: `ARSceneContainer` /
`SceneGeneratorViewModel` (outside this lane's ownership) do not pass a real
device-orientation-derived `RecordingTrackTransformMetadata` yet, so AR takes
record with the identity metadata until that one-line call-site update is
integrated by the main flow. The seam is source-compatible (optional
parameter).

## Narrow verification

Same focused run as M7-005/M7-006: **93/93 PASS, 0 failures** on iPhone Air
simulator iOS 26.5 (xcresult `/private/tmp/m7-pkgA-tests-r3.xcresult`).
`git diff --check` clean.

## Honest boundaries

- Upright playback for every physical iPhone/iPad orientation and lens
  configuration is physical-device acceptance (tracker: "physical playback
  matrix later"); simulator evidence proves metadata correctness, not display
  uprightness.


## Acceptance addendum (coordinator integration, 2026-09-05)

The acknowledged production-wiring gap is closed: `SceneGeneratorViewModel`'s
start path now derives `RecordingTrackTransformMetadata` from the current
device orientation via `currentRecordingTrackTransform()` (flat/unknown
postures fall back to the portrait baseline; no mirroring on the AR
world-tracking path) and passes it through `controller.start(trackTransform:)`
into the writer configuration. Pinned by
`testCurrentRecordingTrackTransformIsAlwaysValid`. Physical uprightness per
device/lens remains M13.
