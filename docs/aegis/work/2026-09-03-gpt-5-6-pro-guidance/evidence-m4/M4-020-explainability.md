# M4-020 — neural explainability

Status: **closed on the current store**.

## Closed gap

Every neural contribution now carries the full explainability tuple:

- **head**: `appliedHeadIds` on each `HybridFusionDecision`;
- **calibrated confidence**: `HybridFusionService(headCalibrator:)` routes
  every scalar and shot-type head confidence through its calibration curve
  (keyed by head id); out-of-domain or unavailable heads abstain — the
  contribution is dropped, never mixed as raw (`testOutOfDomainHeadAbstainsFromRanking`);
- **model version**: `neuralMetadata.modelVersion` travels with the input;
- **ROI**: `neuralMetadata.roiStrategy` travels with the input;
- **linked action**: `targetId`/`targetType` on each decision.
- **Deterministic localized text**: fused summaries rebuild through the
  deterministic summary builder (no free-form neural text reaches UI —
  M2-030 boundary intact).

The nil-calibrator path preserves the legacy multiplier behavior for
fixtures without calibration; production wiring of a real calibration
schema arrives with the M4-016 converted artifact.

## Verification

19/19 (fusion 9/9 incl. the two new M4-019/M4-020 tests + calibrator 10/10)
on permitted iPhone 17e (`/private/tmp/m4-020-tests.xcresult`).
