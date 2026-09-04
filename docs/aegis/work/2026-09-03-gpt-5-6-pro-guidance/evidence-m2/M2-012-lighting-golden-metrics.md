# M2-012 — Subject/background lighting metrics: golden metrics

Task: Correct subject/background lighting metrics by excluding the subject mask and accounting
for clipping/hotspots.
Owner boundary: `TechnicalFeatureOwner`. Implementation: LightingEstimator.swift rewritten to a
single deterministic 32×32 grid sample with subject-mask exclusion.

## Fixes over the previous estimator

1. Background mean now EXCLUDES subject pixels (previously the whole frame including the
   subject was averaged — a large dark subject dragged the "background" down).
2. Contradiction guard: subject clipping ≥ 0.02 suppresses the backlight claim
   (backlightIndex = 0) — no subject-underlit + subject-overexposed contradiction from one
   metric set.
3. All outputs forced finite (non-finite → 0); degenerate subject box → neutral subject mean
   (0.5), zero ratios.
4. Evidence floors: <8 subject samples → neutral subject metrics; <64 background samples →
   whole-frame-mean fallback (documented approximation), background-only ratios.

## Golden metrics (LightingEstimatorTests 7/7 PASS; xcresult /private/tmp/shafin-m2-012.xcresult)

| Fixture | Golden assertions |
|---|---|
| Front light (bg 30/255, subject 200/255) | subject > background mean; backlightIndex == 0; delta > 0 |
| Backlight (bg 210, subject 40) | backlightIndex > 0.1; background > subject |
| Low key (bg 5, subject 10) | means < 0.1, all outputs finite |
| Clipping (bg 128, subject 255) | clipped ratio > 0.9; backlightIndex == 0 (contradiction guard) |
| Uniform (120/120) | backlight 0, keyFill 1 ±0.05, delta 0 ±0.02, ratios 0 |
| Large dark subject on bright bg (centered 0.6 rect) | background mean > 0.75 (exclusion holds) |
| Degenerate zero box | all finite; subject mean neutral 0.5 |

Fixture note: subject patches are CENTERED where possible so the tests are invariant to the
Core Image y-orientation convention (M2-003 adapter owns orientation semantics).
