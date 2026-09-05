# M7-005 — writer configuration

Status: **implemented and verified in the isolated external-M7 lane**
(`codex/external-m7-recording`, BASE_HEAD `02f03f6`).

## What changed

`AVAssetWriter` inputs are now built from the active capture configuration
instead of hard-coded settings, and invalid combinations fail before any
writer exists:

- `RecordingConfiguration` (RecorderContracts.swift) gained
  - `videoCodec: RecordingQuickTimeCodec` (default `.h264`, the v1 baseline),
  - `pixelFormatFourCC: UInt32?` — the active capture buffer's native FourCC;
    `nil` keeps the platform adaptor default for direct constructions,
  - `trackTransform: RecordingTrackTransformMetadata?` (consumed by M7-007).
- New `RecordingCodecSupportChecking` seam; production default
  `AppleRecordingCodecSupportChecker` answers platform encoder availability.
  `AVAssetWriterRecordingWriterFactory` rejects an unsupported codec with the
  new typed `RecordingWriterError.unsupportedVideoCodec` and an explicitly
  zero pixel format with `.inputRejected` **before** creating any writer.
  There is no implicit codec fallback.
- The writer's video settings select the configured codec (H.264/HEVC) and pin
  `kCVPixelBufferPixelFormatTypeKey` to the supplied capture FourCC; audio
  keeps the fixed v1 AAC 48 kHz mono format.
- `SerializedMediaRecorder.prepareOnQueue` maps
  `.unsupportedVideoCodec`/`.inputRejected` to the existing typed
  `RecorderFailure.writerInputRejected` (taxonomy unchanged).
- `SceneRecordingController.performStart` now derives the pixel format from
  the actual initial `CVPixelBuffer` (`CVPixelBufferGetPixelFormatType`) and
  threads the selected codec, so writer settings reflect the active capture
  format, not a requested preset.

## Acceptance criteria evidence

| Criterion | Evidence |
|---|---|
| Writer settings are device-supported | `AppleRecordingCodecSupportChecker` consults platform encoder availability; unsupported selections injected through the seam are rejected pre-writer (`testWriterFactoryRejectsUnsupportedCodecBeforeCreatingAnyWriter`). Hardware-encode behavior per physical device is explicitly NOT claimed here. |
| Settings reflect selected resolution/FPS/format | `testWrittenAssetCarriesSelectedCodecAndPixelFormat` writes a real HEVC/420v take and asserts the encoded track's media sub-type is `kCMVideoCodecType_HEVC`; dimensions/FPS came from the configuration in all existing writer tests. |
| Invalid combinations fail before recording | `testWriterFactoryRejectsExplicitZeroPixelFormat`, `testSerializedRecorderRejectsUnsupportedCodecAsTypedInputFailure` (recorder stays `.idle`, no output file is created). |
| Production owner passes the active format | `testStartThreadsActiveCaptureFormatAndOrientationMetadataIntoConfiguration` (controller threads the real buffer FourCC). |

## Narrow verification

`xcodebuild test-without-building` (fresh build, iPhone Air simulator,
iOS 26.5): focused suites `AppleRecordingAdaptersTests`,
`SerializedMediaRecorderTests`, `RecordingLifecycleTransitionTests`,
`RecordingContractV1Tests`, `SceneRecordingControllerTests` —
**93/93 PASS, 0 failures** (xcresult `/private/tmp/m7-pkgA-tests-r3.xcresult`).
`git diff --check` clean.

## Honest boundaries

- Hardware HEVC/H.264 encode support per physical device remains external
  qualification (M13); simulator evidence proves the rejection path and the
  encoded-format binding, not device codec coverage.
- `CameraService`'s legacy writer path is not migrated to this configuration
  (it owns its own AVAssetWriter setup and remains the Camera Coach path).
