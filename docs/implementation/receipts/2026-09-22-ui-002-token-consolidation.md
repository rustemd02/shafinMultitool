# UI-002 — token consolidation in Camera UI (no parallel design system)

Date: 2026-09-22. Candidate HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`).
The working tree was dirty with other owners' parallel diffs before this task
(CAM-009 swift in `AnalysisPipeline.swift` + tests, UI agents in
`SETCameraCoachProductionView.swift`, `CameraOverlayUXPresentation.swift`,
`SETComponents/SETMetrics/SETLocalization.swift`, `SETLibraryProductionView.swift`,
entry-flow files and docs). Before editing each file its cleanliness was
re-verified via `git status --porcelain -- <file>`. No commit, push, PR, reset,
stash or foreign file was touched; `docs/admission/` untouched; the canonical
tracker row is left for the orchestrator.

## Task

UI-002 (tracker §12): «Свести типографику, spacing, color, corner, material и
motion к существующим tokens; не делать новый parallel design system. Check /
Done when: Focused diff; contrast and Dynamic Type semantics сохранены.»

## Method and boundary

- Token owners read but NOT modified: `SETColor.swift` (SETPalette +
  ShapeStyle extensions), `SETTypography.swift` (SETTypographySize, scaledFont),
  `SETMetrics.swift` (SETSpacing, SETRadius, SETStroke, SETComponentMetric,
  SETCameraCoachMetric), `SETMotion.swift`, `SETComponents.swift`.
  No new token was created anywhere (UI-002 forbids a parallel token layer).
- Replacement rule: only exact 1:1 value matches, so every replaced literal
  renders bit-identically; contrast (alpha channels kept verbatim) and
  Dynamic Type semantics (no text style, no scaling path was added, removed or
  changed — fixed-size literals stay fixed-size) are preserved by construction.
- Files already modified by other owners were excluded from edits:
  `SETCameraCoachProductionView.swift`, `CameraOverlayUXPresentation.swift`,
  `SETComponents/SETMetrics/SETLocalization.swift` (they are already the
  tokenized reference).

## Inventory (main Camera views, pre-edit)

Already fully tokenized (0 applicable literals): `OverlayView.swift`,
`ZoomControlView.swift`, `PauseSceneControlSheet.swift`,
`CameraCloudReviewControls.swift`, `DecisionTraceView.swift` (except
`tracking(0.35)`, see gaps), `SuggestionChip.swift`, `ProControlsPanelView.swift`,
`HorizonOverlay.swift`, `ThirdsGridOverlay.swift`, `BBoxOverlay.swift`,
`DirectionArrows` helper logic, both `#if DEBUG` fixture roots (out of scope).

Had magic literals: `SuggestionListView.swift` (legacy fallback pause
presentation — `SuggestionListView`/`PauseCritiqueCardView`/
`PauseStatusPanelView` have no external callers, compiled-in),
`CameraRecordingControlsView.swift` (live, owned by the production view),
`PauseImagePlacementSheet.swift` (live), `DebugOverlay.swift` (DEBUG-gated
debug HUD, compiled in), `DirectionArrows.swift` (#Preview-only view),
`DebugVisualizationOverlay.swift` (DEBUG-gated).

## Replacements (all value-identical, 35 lines in 5 files)

1. `shafinMultitool/Multitool2Module/UI/Overlay/SuggestionListView.swift` (23 lines)
   - `spacing/padding 8` → `SETSpacing.x2` (6 sites); `12` → `SETSpacing.x3`
     (5 sites); `16` → `SETSpacing.x4` (8 sites incl. one `-SETSpacing.x4`
     negative inset that cancels the outer padding); `4` → `SETSpacing.x1`
     (1 site); `Spacer(minLength: 8)` → `SETSpacing.x2`.
2. `shafinMultitool/Multitool2Module/UI/Overlay/CameraRecordingControlsView.swift` (5 lines)
   - `44` → `SETComponentMetric.minimumHitTarget` in `max(44, …)` clamp and
     4× `.frame(minWidth: 44, minHeight: 44)` (accessibility hit target).
3. `shafinMultitool/Multitool2Module/UI/Overlay/DebugOverlay.swift` (5 lines)
   - `spacing 4/padding 12/padding 8/spacer 16` → `SETSpacing.x1/x3/x2/x4`;
     `cornerRadius(8)` → `SETRadius.control`;
     `.system(size: 11, design: .monospaced)` → size scalar
     `SETTypographySize.micro` (system mono face kept — swapping to the
     `hudMono` face would NOT be 1:1).
4. `shafinMultitool/Multitool2Module/UI/Overlay/DirectionArrows.swift` (2 lines)
   - `.system(size: 48)` → size scalar `SETTypographySize.displayLarge`
     (2 sites; system face kept; view is #Preview-only).
5. `shafinMultitool/Multitool2Module/UI/Overlay/PauseImagePlacementSheet.swift` (1 line)
   - candidate outline `lineWidth: 1` → `SETStroke.standard`
     (white/black double stroke colors kept verbatim).

Diff: `git diff --stat` over the five files = 35 insertions / 35 deletions.
No file outside `shafinMultitool/Multitool2Module/UI/Overlay/` was edited.

## Token gaps (NOT created; listed for the design-system owner)

- Spacing scale has no 4/8/12/16/24/32/48 neighbors: paddings/spacings of
  `2, 3, 5, 6, 9, 10, 14` remain literal (SuggestionListView pause rows,
  ConfidenceBadge, action bar).
- Corner radius: `12` and `16` are used by the pause panels/rows but
  `SETRadius` has only `0/8/14/999` — either a new radius token decision or a
  conscious migration to `control`/`chip` is a separate owner decision.
- Color: every `.white/.black.opacity(x)` in pause surfaces (0.07–0.96),
  `Color.white` tint/foreground, and status colors `.green/.orange/.yellow/.red`
  (ConfidenceBadge tones, debug status colors) have no SET equivalent. Note:
  SET text tokens are `warmWhite` (0xF4F1EA), so `.white` is NOT replaceable
  1:1; migrating it would change rendered pixels and is out of scope.
- Typography tracking: `tracking(0.35)` (DecisionTraceView mono labels, 12
  sites) — `setMonoTracking()` resolves to 0.65, not 1:1.
- Motion: `.easeInOut(duration: 0.3)` (DirectionArrows) — `SETMotion` has
  0.26/0.28/0.32, none equal to 0.3.
- Materials: `.ultraThinMaterial` (SuggestionListView panels) has no token;
  the transparency-aware path is `setAdaptiveScrim(reduceTransparency:)`, which
  is a semantic (not 1:1) change requiring a call-site environment value.
- Size scalars with no token: image preview `height: 280`
  (CameraCloudReviewControls), editor `height: 260` (PauseImagePlacementSheet),
  recording auxiliary `default 128`, debug glyph `size: 10`, dot `8×8`.

## Check (commands and results)

No focused unit tests exist for the touched views (grep of
`shafinMultitoolTests` finds no reference to SuggestionListView,
DirectionArrows, DebugOverlay, PauseImagePlacementSheet; UITests references
only a method name). Per the task line the minimum check is a green app-target
build. Xcode 27.0 (27A266a) / iOS SDK 27.0 drift applies (canonical
`-workspace` lane fails before compilation on Pods deployment-target pins);
the workaround recorded in `receipts/2026-09-22-cam-003-calibration-contract.md`
was reused without changing any repository file:

```bash
xcodebuild -workspace shafinMultitool.xcworkspace -scheme Pods-shafinMultitool \
  -sdk iphonesimulator -destination 'id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /private/tmp/setos-ui002/dd \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 build     # ** BUILD SUCCEEDED **

xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool \
  -sdk iphonesimulator -destination 'id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /private/tmp/setos-ui002/dd build
  # ** BUILD SUCCEEDED ** (pre-existing .rcproject rule warning only)
```

## Limits / what this does NOT claim

- This does not redesign any surface (UI-003/UI-004 own that) and does not
  touch the pause/review live styling in files owned by other in-flight tasks.
- Unused legacy views (`SuggestionListView`, `PauseCritiqueCardView`,
  `PauseStatusPanelView`, `DirectionArrows`) were consolidated but their
  dead/fallback status is recorded here, not "fixed".
- No screenshot, VoiceOver or physical-device evidence was produced; contrast
  and Dynamic Type are preserved by construction (value-identical swaps), not
  re-measured.
- Scratch derived data lived only under `/private/tmp/setos-ui002/` and was
  removed after the run.
