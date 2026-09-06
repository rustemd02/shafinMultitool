# M11-009 / M11-012 — motif budget and Reduce Transparency

Status: **closed on the current store**.

## M11-009 — motif budget

Structural audit (`scripts/evidence/check_motif_budget.py`, green):
exactly one cinematic accent token (`setOrange`), no rival accent colors,
no fullscreen film surfaces; annotation motifs stay punctuational and the
camera/AR frame stays hero. Per-state simultaneity follows from the
single-accent/single-marker presentation owners.

## M11-012 — Reduce Transparency global

New `Color.setAdaptiveScrim(reduceTransparency:)` is the single
transparency-aware surface (solid under Reduce Transparency, scrim
otherwise). All six Coach overlay structs
(TopChrome/HUDHeader/LensStatus/CommandBand/FixtureCommandBand/
StatusOverlay) read the environment and resolve through it, so text and
controls stay legible over noisy camera content. State is never
color-only: status surfaces pair color with text/mode copy.

Verification: 26/26 overlay + readability UI tests on permitted iPhone
17e (`/private/tmp/m11-012-tests.xcresult`).
