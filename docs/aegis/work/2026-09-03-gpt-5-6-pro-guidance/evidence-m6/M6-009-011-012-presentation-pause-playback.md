# M6-009 + M6-011 + M6-012 — AR presentation, hint pause, playback evidence

Status: all three CLOSED on the current store (verify-and-close; no
production change this batch).

## M6-009 — AR coordinate transforms (verify-and-close)

Label/selection anchoring rides the device-provided
`ARFrame.displayTransform` (orientation- and device-correct by
construction, published as `hintDisplayTransform` and cleared on
release/interruption); the coordinator caches viewport/orientation
inputs per frame generation; storyboard drag hit-testing projects
world positions through the workspace view
(`projectedStoryboardActorHit`/`storyboardActorHit`). No parallel
hand-rolled projection matrix exists to drift. Synthetic
projectPoint fixtures on hardware remain M13 (the M6-020 seam now
allows driving the raycast half without a device; the projection
half requires real frames).

## M6-011 — hint pause (verify-and-close)

The pause/resume state machine is owned by the VM
(`startHintPauseAnalysis`/`resumeHintLiveAnalysis` with
`hintPausePresentationState`, failure reason typed
`.noAcceptedEvidence`, epoch/generation-fenced resumption) —
`SceneBundlePipelineTests.testSceneGeneratorHintPauseLifecycleStopsAndResumesLiveAnalysis`
pins the stop/resume lifecycle; the journey contract pins the
`arHintPause` state ordering
(`SceneJourneyContractTests`); recording integrity under pause/
interruption is covered by the M1-021 race lane and M7-014
(interruption finalizes exactly once). Pause freezes hint
advancement only — AR tracking and recording state are untouched by
construction (separate owners, generation fences).

## M6-012 — AR playback integration (verify-and-close)

Playback ownership is the M1-017 player owner (single playback path,
released on route exit) with the M7-026 probe-gated review player
(missing/corrupt media fails closed to the localized band, lease
released on dismiss/teardown); interruption stops playback through
the M6-014 generation-fenced single-flight handlers; in-workspace
scene animation (`playScene`/`animateActor`) animates placed
entities in place without retaining media or stale anchors — no
second player instance exists. Physical playback quality remains
M13.

## Honest open sibling

M6-010 (live hints bound to planned action/entity IDs) remains OPEN:
current live hints are frame-analysis-driven; binding them to
PlannedScene identities is a real feature not yet implemented. It is
not a dependency of M6-GATE.
