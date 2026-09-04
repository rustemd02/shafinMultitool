# M2-009 — Tap-to-select manual subject selection

Task: Implement tap-to-select for ambiguous people, groups, objects, and scene regions without
conflicting with focus/exposure behavior.
Owner boundary: `SubjectSelectionOwner`. Implementation: NEW SubjectTapSelector.swift (pure;
UI wiring consumes it in the S05 clarification view when built).

## Contract

`SubjectTapSelector.route(displayX:displayY:candidates:clarificationActive:focusEnabled:transform:)`
routes every tap to exactly one intent:
- `.subjectSelected(candidate)` — clarification tap hits a candidate (display point → M2-003
  inverse transform → scene space → hit-test).
- `.clarificationEmptyTap` — clarification tap on empty space: recoverable feedback; focus never
  fires during clarification (selection gesture is not stolen).
- `.focusRequested(sceneX:sceneY:)` — normal mode: explicit coordinated focus at the scene point.
  Future focus/exposure implementation must consume this outcome instead of adding a parallel tap
  path — that is the anti-conflict coordination.
- `.ignored` — no clarification and focus unavailable.

Geometry: `hitTest` inflates regions by touchSlop (0.04 normalized), nearest-center wins, equal
distances resolve by ascending candidate id (deterministic), regionless candidates never hit,
non-finite display taps clamp to center (fail closed).

## Tests (SubjectTapSelectorTests 10/10 PASS; xcresult /private/tmp/shafin-m2-009.xcresult)

Same physical candidate selected in all 8 display states (orientation × mirroring invariance
through the inverse transform); portrait display-top ↔ sensor-right-edge mapping; touch slop
forgiveness at edges; nearest-center wins; deterministic id tie-break; regionless never hit;
empty-clarification feedback; coordinated focus; ignored without focus; non-finite fail-closed.

Attempts: 1) tuple in enum broke Equatable → named associated values; 2) test-side geometry
errors (portrait inverse expectation, non-overlapping slop bands, equidistant fixture) — fixed
with correct math. Resolver/selector production code needed no change for these.
