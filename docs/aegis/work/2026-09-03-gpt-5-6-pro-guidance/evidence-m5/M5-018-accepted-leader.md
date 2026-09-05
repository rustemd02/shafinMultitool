# M5-018 — Accepted request leader presentation

## Contract

`SceneGeneratorViewModel` owns the accepted-request leader. The stable event ID
is `generator.leader.<lowercased-request-uuid>.<epoch>`. The existing
`generationTask` is the only countdown owner; the SwiftUI view only projects
the published phase through the existing `SETLeaderCountdown` component.

The production call path is:

`generateScene()` or clarification continuation →
`publishAcceptedGenerationAttempt()` (`accepted → queued → leader`) → consume
the event ID in `SETMotionEventLedger` → the existing `generationTask` awaits
`playGenerationLeaderIfNeeded()` → publish `generating(reading)` →
`performGeneration()`.

Clarification continuation reuses the same UUID and epoch. Its already
consumed event ID therefore cannot replay the leader and it proceeds directly
to generation. Teardown and cancel clear the projection after joining the same
owner task; rotation/recomposition has no event-consumption side effect.

Normal Motion uses the shared 320 ms leader steps followed by the shared action
duration. Reduce Motion starts at `.action`, uses the shared 120 ms crossfade,
and performs no travel, scale, rotation, or overshoot. A live environment
change is delivered through `onChange` as well as the initial appearance.

## Changed files

- `shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift`
  — request-owned event/phase state, one-shot ledger consumption, countdown in
  the existing generation task, cancellation/teardown cleanup, and DEBUG-only
  production-route fixture seam.
- `shafinMultitool/SceneGeneratorModule/Views/SceneGeneratorView.swift`
  — render-only leader projection, stable accessibility probe, motion-preference
  propagation, and deferred DEBUG fixture trigger.
- `shafinMultitoolTests/SceneBundlePipelineTests.swift`
  — one-shot/replay and Reduce Motion owner-contract coverage.
- `shafinMultitoolUITests/SETGeneratorProductionUITests.swift`
  — normal-motion rotation evidence route and Reduce Motion evidence probe.
- `M5-018-normal-leader-simulator.mp4`
  — bounded simulator recording of the normal-motion production route.

No routes, persistence, recording/media owners, M7 files, accessibility IDs
outside this new probe, or `EXECUTION_STATE.md` were changed.

## Verification

All runs used the permitted iPhone 17e Simulator, device
`1F680A42-CEB3-43E8-9CED-52F874962A62`, iOS 26.5. No iPhone 17 Pro or physical
device was used.

- `git diff --check` — passed before handoff.
- Focused owner tests — `2 tests, 0 failures`, `** TEST SUCCEEDED **`:
  `/tmp/shafin-m5-018-unit-final.xcresult`.
- Normal production-route UI test — `1 test, 0 failures`,
  `** TEST SUCCEEDED **`:
  `/tmp/shafin-m5-018-ui-leader-video.xcresult`.
  It captured `generator_leader` in landscape-left, preserved the same visible
  owner projection through landscape-right rotation, and retained both
  screenshots as XCTest attachments.
- Motion video was recorded concurrently with the passing normal UI route:
  `docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m5/M5-018-normal-leader-simulator.mp4`.
- A separate Reduce Motion UI receipt is retained at
  `/tmp/shafin-m5-018-ui-leader-reduce-motion-final.xcresult` and honestly
  fails its accessibility probe. The production Reduce Motion projection is
  intentionally only 120 ms, while XCTest's standard existence polling
  sampled at roughly one-second intervals; extending production timing or
  adding a fake overlay would violate the motion contract. The owner-level
  immediate-action/no-replay contract is covered by the passing focused unit
  test above. Reduce Motion visual capture remains an open evidence limitation.

## Boundaries

This packet proves request identity, one-shot ownership, lifecycle fencing,
normal-motion production-route rendering, rotation stability, and the
Reduce Motion state contract. Simulator evidence does not prove physical
camera/ARKit/hardware timing behavior.
