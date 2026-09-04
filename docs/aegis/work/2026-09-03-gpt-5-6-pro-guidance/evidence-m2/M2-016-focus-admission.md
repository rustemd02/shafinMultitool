# M2-016 — Focus/readability evidence and refocus-advice admission report

Task: Define a conservative focus/readability signal and camera focus-state contract before
exposing refocus advice.
Owner boundary: `TechnicalFeatureOwner`. Implementation: NEW FocusEvidenceSignals.swift —
CameraFocusStateV2 contract (unsupported/locked/adjusting/failed), FocusEvidence verdict, pure
analysis over luma grid + gradient statistics, BGRA entry point.

## Joint admission predicate (validated, conservative)

Refocus advice is admitted ONLY when ALL hold:
1. `focusState == .locked` — unsupported devices fail closed permanently; adjusting (mid-sweep)
   and failed (unknown positions) states fail closed;
2. frame measurably defocused by the TechnicalQualityAnalyzer-aligned gradient predicate
   (mean ≥ 0.12 for measurable light; variance ≤ 780 && mean ≤ 38, or mean ≤ 13);
3. subject-region readability computed (nil region → 0, fail closed).

## Tests (FocusEvidenceSignalsTests 9/9 PASS; xcresult /private/tmp/shafin-m2-016.xcresult)

Sharp checkerboard: not defocused, no advice. Smooth gradient: defocused + admitted when
locked. Fake focus-state matrix: unsupported/adjusting/failed all refuse advice on the SAME
blurred fixture. Near-black frame cannot claim defocus. No subject region → zero readability.
BGRA entry matches the grid contract.

Attempts: instance-vs-static call labels (subjectReadability/gradientStats) — fixed.
