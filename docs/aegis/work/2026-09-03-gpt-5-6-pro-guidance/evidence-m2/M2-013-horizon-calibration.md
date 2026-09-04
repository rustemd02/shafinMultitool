# M2-013 — Horizon angle/confidence calibration report

Task: Normalize horizon angle/confidence through capture orientation and reject intentional/weak
horizon evidence.
Owner boundary: `TechnicalFeatureOwner`. Implementation: HorizonEstimator.swift reworked —
explicit `HorizonEstimate` (angleDegrees/confidence/isAvailable/suppressedByIntent),
`HorizonIntentOverride`, pure `normalizedSceneAngle(observationAngleDegrees:orientation:)`.

## Normalization (sign stability)

Vision measures the horizon in the ORIENTED image; each capture-orientation tag applies a
rotation ρ (.up=0, .right=90, .down=180, .left=270). Scene angle = normalize180(measured − ρ)
— the same physical tilt yields the same scene angle under every orientation. Line angles are
mod 180, normalized to (−90, 90].

## Availability fail-closed

- Absent observation / request error → unavailable (confidence 0). The previous motion fallback
  that published confidence 0.1 as if it were knowledge is gone.
- Low confidence (< 0.2) → unavailable (angle suppressed).
- Unknown-future-proof: unavailable outputs carry zeroed angle/confidence for all downstream
  consumers (features, overlay, replay).

## Intentional override

`HorizonIntentOverride.intentional` → unavailable + `suppressedByIntent = true`: the user's
deliberate tilt suppresses correction.

## Consumer migration

All AnalysisPipeline consumers (features update, live overlay state, pause/replay helpers,
logHighFrameDebug) now read `isAvailable ? angleDegrees/confidence : 0` — unavailable horizon
contributes zeroed values instead of stale claims.

## Tests (HorizonEstimatorTests 4/4 PASS; xcresult /private/tmp/shafin-m2-013.xcresult)

1. Sign stability: 7 tilts × 4 orientations — scene angle == physical tilt (pure table).
2. HorizonEstimate.unavailable semantics.
3. Synthetic-line integration: detected → available, screen-clockwise tilt measures
   non-positive, magnitude ≤ drawn tilt (the 0.2·Vision + 0.8·roll blend is by design; roll=0
   on simulator damps the first frame), confidence > 0.2.
4. Intentional override: unavailable + suppressedByIntent, confidence 0.
