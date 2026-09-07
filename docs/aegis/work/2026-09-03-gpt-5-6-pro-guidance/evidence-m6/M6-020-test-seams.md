# M6-020 — AR test seams evidence

Status: CLOSED on the current store.

## Seam inventory (complete)

- Session lifecycle: `ARSessionRuntime` protocol (`ARSession` adopts
  directly; call-counting test runtime) — session/failure/frame event
  fakes exist in `ARSessionOwnershipTests` (6/6 green this session).
- Configuration capability: `ARWorldTrackingCapabilityProviding` +
  `ARWorldTrackingConfigurationPolicy` (fail-closed on unsupported).
- World map: `SETWorldMapCaptureResolver` with injectable
  request/sleep (timeout/cancellation/late-callback fakes in
  `SceneWorkspaceTeardownTests`) + `ARWorldMapPersistenceTests`
  (4/4).
- Surface raycast (added this task): `SceneSurfaceRaycasting`
  protocol + `SceneSurfaceRaycastResult` plain struct +
  `ARViewSurfaceRaycaster` production adapter wrapping the existing
  ARView two-pass query one-to-one (existing-plane → estimated-plane,
  ray-through for the floor fallback). The VM consumes the provider;
  a fake provider drives hit/miss/failure events without an ARView.

## Added fake-event proof

`SceneSurfaceRaycastingSeamTests` — 5/5 PASS on permitted iPhone 17e
(`/private/tmp/m620-tests.xcresult`): fake hit opens marker naming
with the projected world position; miss + no fallback rejects typed;
marking-mode gate rejects BEFORE any raycast (call count 0); the
naming transaction creates a canonical `object_marked_*` identity and
clears pending state; cancel discards without residue; blank name is
rejected. `ARSessionOwnershipTests` 6/6 regression green.

## Production wiring note

The tap guard now accepts either the seamed provider or the raw view
(diagnostic field `hasRaycaster` added); the default adapter attaches
automatically when the container sets `arView`. Legacy direct-query
path preserved for the raw-view case — production behavior unchanged.
