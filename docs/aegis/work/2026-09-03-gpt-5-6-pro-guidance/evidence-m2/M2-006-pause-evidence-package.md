# M2-006 — Pause evidence package (explicit temporality + freshness barrier)

Task: Rework pause analysis to produce a same-frame or explicitly declared temporal-aggregate
evidence package.
Owner boundary: `PauseAnalysisOwner`.

## Mechanism

`PauseEvidencePackage` (LatestFrameEvidenceStore.swift):
- `temporality`: `.sameFrame` when no source was re-measured after acceptance;
  `.temporalAggregate` when pause-time recomputes exist (fresh local DETR / aesthetic on the
  accepted pixel buffer) — the aggregate is DECLARED, not silent.
- `verdicts: [FeatureSourceID: FeatureFreshnessVerdict]` — per-source availability, measuredAt,
  and age (fail-closed: missing timestamp or unknown lens generation → unavailable; M2-005
  declared windows judged against the validation moment).
- `isSourceUsable(_:)` — the gate downstream consumers must pass.
- `exposedAges` — every source age exposed to validation.

## Production wiring (AnalysisPipeline.runPauseAnalysisImpl, group.notify)

The completed pause assembly builds the package from `frameEvidence.makeEnvelope()` + pause-time
recompute timestamps (detr/aesthetic when recomputed) and stores it as
`lastPauseEvidencePackage` (lock-guarded, internal for validation/diagnostics). Base Vision /
horizon / lighting samples and the aesthetic fallback now enter the published
`PipelineFeatureSnapshotAdapterState` only when their verdict is available — pause output can
never combine current DETR/neural inference with stale unmarked values. The fresh pause-time
DETR is by construction the declared aggregate member.

## Tests (PauseEvidencePackageTests 6/6 + LatestFrameEnvelopeTests 8/8 PASS; xcresult
/private/tmp/shafin-m2-006.xcresult)

sameFrame declaration; pause-time recompute declares temporalAggregate with age 0; stale
barrier at +2s (all five windows expired → all unavailable, ages exposed); missing base source
unavailable with nil age; fresh recompute cannot rescue stale envelope mixing (per-source
judgement); unknown lens generation fails the whole package.
