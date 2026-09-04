# M2-002 — Canonical normalized coordinate spaces contract

Task: Define canonical normalized coordinate spaces for sensor, Vision, model input, preview,
subject target, and SwiftUI canvas.
Owner boundary: `CameraGeometryOwner`. Implementation: CameraAnalysisDomainContracts.swift
(CameraCoordinateSpaceV2, CameraSpacePointV2, AspectFillTransform). M2-003 will implement the
single orientation/mirroring adapter that feeds these spaces.

## Space definitions (unit square unless stated)

| Space | Origin | Axes | Framing notes |
|---|---|---|---|
| sensor | TOP-left pixels | x-right, y-down | landscape-native raw sensor buffer |
| vision | BOTTOM-left | x-right, y-UP | Apple Vision convention; rotation/mirroring applied by Vision request orientation |
| modelInput | TOP-left | y-down | square ASPECT-FILL (center crop) of sensor; sensor edges outside crop unreachable; not invertible without crop window |
| preview | TOP-left | y-down | ASPECT-FILL of sensor into visible preview bounds; inverse requires bounds + display orientation |
| subjectTarget | TOP-left | y-down | coaching tap/markers/arrows; same framing as preview, never mirrored vs captured scene |
| swiftUICanvas | TOP-left | y-down | hosting overlay view bounds; identity for normalized values vs preview when bounds equal |

## Conversion rules implemented

- `flippedVertically` — Vision (y-up) ↔ y-down family; own inverse.
- `AspectFillTransform` — center-crop aspect-fill between pixel sizes: fillScale =
  max(dw/w, dh/h); destination = (source·scale − cropOffset)/destination; inverse returns nil
  outside the crop window (fail closed, no invented coordinates); degenerate sizes fail closed
  to unit-square identity.
- Rotation and mirroring are deliberately NOT here — the M2-003 display-transform adapter is the
  single owner.

## Property tests (CameraCoordinateSpaceTests, 8/8 PASS; xcresult /private/tmp/shafin-m2-002.xcresult)

- unit-square bounds for all 6 spaces over 256 deterministic pseudo-random points + grid + edges + out-of-range/NaN/∞ probes
- vertical flip is its own inverse (production clamp semantics: non-finite → 0)
- vision→subject target top/bottom mapping
- aspect-fill round-trip inside crop window (ε 1e-9, >200 interior probes)
- bounds hold across 4 sensor/destination combinations incl. portrait sensors
- outside-crop non-invertibility / round-trip consistency
- degenerate sizes → identity; NaN/∞ → 0 (fail closed)
- exactly six canonical spaces
