# M10-010 — AR iPad layouts evidence

Status: CLOSED on the current store (verify-and-close; physical
geometry M13).

## Acceptance → owners/proof

- "Preview, surface guidance, placement, marker naming, hints,
  record/playback, tray, error surfaces adapt": every AR-workspace
  overlay is container-driven by construction — the M10-005 closure
  centralized safe-area/container geometry (the one `UIScreen.main`
  violation was fixed to container width; 3/3 geometry tests), the
  hint overlay and scrims size from the workspace container, and the
  storyboard tray now adapts at regular width presentation-only
  (M10-011, same state owners). No scaled-iPhone layout exists (the
  M10 stop-rule).
- "Portrait, landscape, full-screen, and allowed large-window modes":
  windowing policy (M10-004) permits fullscreen-only with resizable
  SwiftUI layouts; orientation adaptation rides the device-provided
  display transform (M6-009) and container geometry; the platform
  contract pins 4 orientations on a universal binary
  (M10-001, 4/4 tests).
- "Without creating duplicate state owners": this task added zero
  production code — all surfaces reuse the VM/coordinator owners
  (M6 chain) with the M10-011 presentation-only size-class hook.
- "Invalid camera/AR size pauses safely": readiness/posture gates
  (M6-005/M6-018) re-evaluate on real frames only; capture controls
  disable semantically while unstable.

## Lane proof (this session)

iPad lanes 10/10 PASS on permitted iPhone 17e
(`/private/tmp/m1010-tests.xcresult`): iPadOverlayGeometryTests 3/3,
iPadPlatformContractTests 3/3, iPadDeviceFamilyTests 4/4 — pinned
against the built product plist and aspect-driven canonical
transforms across iPhone/iPad/split canvases.

## Boundary

Physical iPad geometry/window qualification executes in M13
(iPad-scripts + ar-workspace-v1 step 12).
