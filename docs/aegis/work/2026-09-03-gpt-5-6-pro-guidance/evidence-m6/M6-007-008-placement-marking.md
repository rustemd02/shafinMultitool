# M6-007 + M6-008 — placement and marking contract evidence

Status: CLOSED on the current store (simulator contract half; physical
surface confirmation is M13).

## Pre-existing owners (audited, no production change)

- Placement: `SpatialPlannerService.planScene` — deterministic scene
  space from camera transform + planes, priority placement
  (marked → detected → virtual), stable `placed_<entity>` IDs, floor
  Y from real planes (or honest camera-relative fallback), M5-030
  provenance left unstamped for the atomic VM commit. Entities enter
  AR under the VM's world-zero scene anchor (single owner, M6-002
  generation fences).
- Marking: `MarkedObjectMatcher` — canonical `object_marked_*`
  identities, stable ordering, alias resolution with duplicate/
  ambiguity fail-closed; tap→raycast→two-phase naming in the VM with
  the marking mode gated on surface readiness (M6-006).

## Added contract proof

`shafinMultitoolTests/ARPlacementMarkingContractTests.swift` — 6/6
PASS on permitted iPhone 17e (`/private/tmp/m607-tests.xcresult`):

- placement is byte-identical across runs for identical inputs
  (determinism);
- stable `placed_<id>` identity and script-object binding survive
  planning;
- marked objects win over detected ones (source == .marked) and the
  placed position is the real marker position;
- rotation/position well-formedness (no NaN enters AR);
- canonical marker IDs are stable and namespaced;
- duplicate same-alias markers fail closed — the resolver never
  silently binds an arbitrary marker.

Two fixture corrections mirror the real contract (script-object
identity is the bind target; marker priority expresses via
placementSource).

## Boundaries

Real-plane raycast behavior and user surface confirmation on
hardware remain M13.
