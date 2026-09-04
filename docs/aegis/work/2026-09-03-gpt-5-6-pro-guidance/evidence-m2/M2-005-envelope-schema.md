# M2-005 — AcceptedFrameEnvelope schema and source freshness trace

Task: Introduce immutable AcceptedFrameEnvelope for frame ID, capture time, orientation, lens
generation, pixel buffer, and all feature source timestamps.
Owner boundary: `AnalysisPipelineOwner`.

## Envelope schema (LatestFrameEvidenceStore.swift)

`AcceptedFrameEnvelope` (immutable struct):
- `frameID: String` (trimmed; whitespace-tolerant `matches(frameID:)`)
- `capturedAt: Date`
- `orientation: CGImagePropertyOrientation`
- `lensGeneration: UInt64` (0 = unknown → fail-closed: ALL sources unavailable)
- `pixelBuffer: CVPixelBuffer`
- `featureSourceTimestamps: [FeatureSourceID: Date]`

`FeatureSourceID` = vision | horizon | lighting | detr | aesthetic.
`FeatureSourceFreshnessWindows` (declared, seconds): vision 0.25, horizon 0.4, lighting 0.6,
detr 0.8, aesthetic 1.5.

## Availability policy (fail closed)

`sourceAvailability(asOf:)`: available ⇔ lens generation known AND source timestamp exists AND
age ≤ declared window. Missing timestamp / unknown generation / expired → UNAVAILABLE. Future
timestamps clamp to age 0 (clock skew cannot go negative). Expired values are never silently
mixed with fresh ones — each source is judged on its own measuredAt.

## Wiring

- `LatestFrameEvidenceStore.Snapshot` gained `lensGeneration` (defaulted 0 for legacy/synthetic
  publishers; zero ripple) + `featureSourceTimestamps` extracted from the adapter state
  (vision/detr from FeatureSample.measuredAt; horizon/lighting/aesthetic from their measuredAt
  fields) + `makeEnvelope()`.
- Production high-priority capture (AnalysisPipeline performHigh) now passes the live pipeline
  `generation` as lensGeneration.
- Store-level provenance regression: LatestFrameEvidenceStoreTests 5/5 (incl. concurrent publish
  never tears the envelope).

## Tests (LatestFrameEnvelopeTests 8/8 PASS; xcresult /private/tmp/shafin-m2-005.xcresult)

Fresh-in-window availability; expired vision unavailable while fresh lighting stays available
(mixed-age inputs never combined); per-source declared windows on the availability edge
(all-in / all-expired matrix); missing timestamp unavailable; unknown lens generation fails
closed for every source; future timestamp clamps to zero age; frame-ID match/mismatch;
store→envelope provenance wiring.
