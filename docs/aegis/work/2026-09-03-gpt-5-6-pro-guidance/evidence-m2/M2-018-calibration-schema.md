# M2-018 — Confidence calibration schema and unit results

Task: Create a calibration layer that converts neural and deterministic evidence into
action-specific calibrated probabilities and selective-risk decisions.
Owner boundary: `CalibrationOwner`. Implementation: NEW CameraConfidenceCalibrator.swift
(HybridFusionService integration deferred to the planner task M2-020 that consumes calibrated
probabilities).

## Schema (cal1)

- `CameraCalibrationKnotV1` (raw, calibrated) — piecewise-linear isotonic-shaped curve knots.
- `CameraCalibrationCurveV1` — actionID, version, knots, declared domain [domainLow,
  domainHigh]; validate() rejects empty curves, unsorted knots, non-monotonic calibrated
  values, non-finite/out-of-range values, inverted domains.
- `CameraActionCalibrationSchemaV1` — versioned ("cal1") map actionID → curve; Codable
  round-trip pinned.
- `CameraCalibratedOutcome` — calibrated(Double) / outOfDomain / unavailable. RAW LOGITS ARE
  ABSENT FROM THE OUTCOME TYPE: UI/advice consume calibrated probabilities only.
- `CameraConfidenceCalibrator.calibratedProbability(rawLogit:actionID:)` — selective risk:
  out-of-domain → .outOfDomain, missing entry → .unavailable, non-finite → abstain.
- `expectedCalibrationError(pairs:bins:)` — standard binned ECE.

## Unit results (CameraConfidenceCalibratorTests 10/10 PASS; xcresult
/private/tmp/shafin-m2-018.xcresult)

1. Non-monotonic curve rejected (calibratedNotMonotonic).
2. Unsorted knots / non-finite knot / inverted domain / empty curve rejected.
3. Identity curve calibrates exactly within domain.
4. Out-of-domain raw → selective abstention (.outOfDomain).
5. Missing entry and non-finite raw abstain.
6. Outcome type carries no raw logits (outOfDomain + nil probability + isAbstaining).
7. Piecewise curve monotonic across a 200-step grid.
8. ECE: perfectly calibrated bin centers → 0.
9. ECE: known offset (predictions 0.85, actual 0.5) → 0.35.
10. Schema Codable round-trip with schemaVersion "cal1".
