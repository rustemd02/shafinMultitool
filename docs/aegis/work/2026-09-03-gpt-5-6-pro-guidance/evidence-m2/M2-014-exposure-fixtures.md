# M2-014 — Exposure feature fixtures and predicates

Task: Define measurable underexposure, overexposure, clipping, and subject readability signals
suitable for safe advice.
Owner boundary: `TechnicalFeatureOwner`. Implementation: NEW ExposureFeatureSignals.swift (pure
luma-grid analysis; BGRA entry point included).

## Explicit predicates (never a bare global mean / aesthetic score)

- underexposure: (mean ≤ 0.36 && darkRatio ≥ 0.46) || (mean ≤ 0.18 && darkRatio ≥ 0.35)
- overexposure: (clippedRatio > 0.92-luma ≥ 0.055 && mean ≥ 0.36) || (hotspotRatio ≥ 0.060 && mean ≥ 0.38)
- clipping: frame fraction above luma 0.92
- subjectReadability: fraction of subject-region samples within the readable luma band
  [0.15, 0.92]; no region → 0 (fail closed, no readability claim)
- contradiction flag: isContradictionFree = !(under && over) — exposed honestly to advice

## Fixture matrix (ExposureFeatureSignalsTests 7/7 PASS; xcresult /private/tmp/shafin-m2-014.xcresult)

| Fixture | Expected | Forbidden |
|---|---|---|
| Dark frame (luma 12) | underexposed | overexposure |
| Blown frame (luma 250) | overexposed, clipping > 0.9 | underexposure |
| Mid frame (128) | neither declared | — |
| Half dark / half blown (mean 0.3598) | underexposure wins the 0.36 boundary deterministically, contradiction-free | — |
| Readable subject on bright bg | readability > 0.9 | — |
| Blown subject on dark bg | readability < 0.1 | — |
| No subject region | readability == 0 (fail closed) | — |
| BGRA buffer entry | overexposed, not under | — |

Boundary note: under uses mean ≤ 0.36, over uses mean ≥ 0.36 — coincidence only at exactly
0.36, unattainable on a discrete grid; the deterministic tie-break is underexposure.
