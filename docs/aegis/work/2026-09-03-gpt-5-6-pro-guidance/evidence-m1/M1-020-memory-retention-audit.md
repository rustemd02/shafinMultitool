# M1-020 — Memory/retention cycle audit

Task: Audit delegate, Combine subscription, closure, Task, CVPixelBuffer, ARAnchor, and
AVAssetWriter retention cycles.
Owner boundary: `MemorySafetyOwner`. Static audit; two bounded cycles documented, no leaks
requiring production change found in the audited surfaces.

## Per-class findings

| Cycle class | Findings |
|---|---|
| Timer closures | `recordingTimer` (VM:4548) and `playbackTimelineTimer` (VM:4012) use `[weak self]`; both invalidated on stop/teardown (VM:4610, invalidatePlaybackTimelineTimer) — no retention |
| Delegates (ARSession) | `session.delegate = nil` on every release path: VM pauseAndDetach (VM:1191), ARSceneContainer updateUIView released branch (:91), dismantleUIView (:112) — no delegate cycle survives teardown |
| Combine subscriptions | VMs store in `cancellables` tied to owner lifetime; sinks use `[weak self]` (verified at CameraViewModel:253-256, SceneGeneratorViewModel setupBindings) — no self-retaining subscriptions found |
| Tasks | Long-lived tasks captured as `generationTask`/`recordingStartTask`/`lensSwitchTask`/`teardownTask` properties are cancelled + awaited + nilled on teardown (M1-008/M1-011); closures use `[weak self]` in VM/pipeline fire-and-forget paths |
| CVPixelBuffer | `SceneRecordingController.latestVideoPayload` intentionally caches ONE latest AR frame buffer for REC-tap writer setup (bounded, overwritten per frame, owned for the controller lifetime ≤ workspace lifetime); recorder-side buffers released via writer=nil on finish/discard (SerializedMediaRecorder discardPreparedResourcesOnQueue) — bounded, documented |
| ARAnchor / entities | `placedEntities`/`markerEntities` dictionaries cleared in `removePlacedSceneEntities` on generation commit and teardown (removePlacedSceneEntities "generation_commit") — bounded |
| AVAssetWriter | writer/input references nil'ed in `finishCompletedOnQueue` and `discardPreparedResourcesOnQueue`; failed-start path discards immediately (failStartOnQueue) — no writer outlives its recorder |
| **VM↔ARView cycle (documented, bounded)** | `SceneGeneratorViewModel.arView → ARView → Coordinator → viewModel` forms a cycle; broken deterministically at teardown (`pauseAndDetachARSession` nils `arView` after coordinator detached) — lifetime bounded by the M1-009 teardown ownership; route release always tears the workspace down |
| **SceneGeneratorDiagnosticsLogger static DateFormatter (documented)** | not thread-safe for concurrent `log` calls from arbitrary executors (noted during M1-008; race hazard, not a leak). Console-only diagnostics; fix candidate bundled with M2 logging cleanup |

## Basis

Findings derive from this session's verified mechanisms (M1-003 generation fence + 18/18,
M1-009 teardown 16/16, M1-010 recorder/controller suites, M1-011 race tests, M1-014 promotion
tests) plus targeted static inspection of the listed files. No unbounded retention cycle or
owner-escaping capture was found in the audited surfaces.

## Acceptance

Retention cycles audited across the six named areas; two bounded cycles documented with their
deterministic break points. No production change required.
