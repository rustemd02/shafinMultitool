# Camera Analysis Semantic Demo Pack

Status: R21a demo-hardening artifact.
Date: 2026-05-27.

This folder defines a small, repeatable demo pack for Camera Analysis semantic
tips. It does not add a second intelligence layer. It pins representative
R21a still-image replay scenarios that the existing runtime presentation path
must keep showing correctly.

## Source Of Truth

- `semantic_demo_scenarios.json` is the machine-readable scenario pack.
- `shafinMultitoolTests/AnalysisPipelinePresentationTests.swift` contains
  `testSemanticDemoScenarioPackReplaysExpectedPresentationActions`, which
  replays every scenario through `AnalysisPipeline.testingReplayStillImageForSemanticEval(...)`.
- The pack uses images and labels from `docs/cameraanalysis/dataset/inbox`.
- The measured baseline is `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r21a`.

## Covered Demo Behaviors

- Positive confirmation for a good cinematic/establishing frame.
- Reframing: `shift_frame_right`.
- Distance correction: `step_back` and `step_closer`.
- Background correction: `simplify_background`, `wait_for_background_clearance`.
- Lighting correction: `add_front_fill_light`.
- Technical/compositional mix: `remove_background_hotspot`, `level_horizon`.
- Current object-oriented support: `move_object_back` for a generic object-balance case.

## Honest Boundary

This pack proves that selected still-image demo scenarios continue to reach
live/pause presentation rows with expected semantic actions. It is not a claim
that arbitrary live camera scenes or precise object-left/right grounding are
stable. In particular, `move_object_left` and `move_object_right` exist in the
catalog, but they are not yet promoted as demo-stable object-aware behavior
without a stronger object-grounding mini-set.

## Demo Flow

Use these scenarios when recording or manually presenting the feature:

1. `ca_img_010`: show that a good cinematic frame receives `keep_current_setup`
   instead of mechanical overcorrection.
2. `ca_img_013`: show a visible live tip: «упрости фон» and «смести кадр вправо».
3. `ca_img_014`: show background simplification and waiting for a cleaner background.
4. `ca_img_022`: show the current object-balance boundary: object action is
   supported as `move_object_back`, not as fully precise left/right grounding.
5. `ca_img_074`: show technical and composition issues combined in pause.
6. `ca_img_092`: show `step_back`.
7. `ca_img_093`: show `step_closer` plus front-fill light.
8. `ca_img_096`: show a simple `step_closer` distance correction.
