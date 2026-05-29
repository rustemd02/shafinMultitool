# Camera Analysis Snapshot

Last verified commit: `6e33b14d9cb001c38cdd1271bbbc56863392212e` plus dirty working-tree evidence updates on 2026-05-23.

## Pipeline scope

Camera Analysis covers the shooting-stage problem from litreview: not only estimating visual quality, but giving explainable recommendations. The current repository evidence supports deterministic v1 critique and a partially implemented/limited hybrid neural evidence path.

## Domain contracts

| Contract area | Description | Files |
|---|---|---|
| `FrameFeatureSnapshot` | Unified frame-level features: composition, subject, horizon, lighting, motion, aesthetics, objects, technical flags. | `shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift`, `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` |
| `SceneSemanticsReport` | Scene type, primary subject, dominance, readability, ambiguity/assumption records. | same |
| `CritiqueReport` | Verdict, issues, strengths, summary and evidence refs. | same, `shafinMultitool/Multitool2Module/Services/Critique/FrameCritiqueEngine.swift` |
| `RecommendationPlan` | Ranked actionable fixes and overlay hints. | `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` |
| Semantic tips | User-facing live/pause advice with grounding and validation. | `SemanticTipPlanner.swift` |
| Decision trace presentation | User-facing explanation sheet for current live/pause advice: verdict/confidence, reason lines, evidence, semantic actions, pipeline signals, limitations and trace ids. | `DecisionTracePresentation.swift`, `DecisionTraceView.swift`, `OverlayView.swift`, `DecisionTracePresentationTests.swift` |
| Neural evidence | Optional neural snapshot, metadata, policy outcomes and fusion decisions. | `NeuralEvidenceInferenceService.swift`, `HybridFusionService.swift` |

## Explainability contract

The explainability design requires critique/recommendations to point back to evidence instead of emitting unsupported advice. This is project evidence for the litreview gap: existing tools may score frames, while the prototype attempts to explain why a frame should be adjusted.

Current app-side UI evidence now includes a `Почему?` sheet in `OverlayView`. It maps the current `LiveHintPresentation` or `PauseCritiquePresentation` into a readable decision trace with reason lines, issue/strength rows, semantic action ids, debug signal rows, fallback/assumption limitations and trace ids. The same overlay UX now shows a live waiting status when no confident hint is ready and gives pause cards an explicit `Продолжить` action so the user can return to camera analysis without hunting for the top control.

Primary sources:
- `docs/cameraanalysis/04-explainability-contract.md`
- `docs/cameraanalysis/19-neural-evidence-domain-contract.md`
- `docs/cameraanalysis/23-hybrid-eval-harness.md`
- `CameraAnalysisDomainContracts.swift`
- `shafinMultitool/Multitool2Module/UI/Overlay/DecisionTracePresentation.swift`
- `shafinMultitool/Multitool2Module/UI/Overlay/DecisionTraceView.swift`
- `shafinMultitool/Multitool2Module/UI/Overlay/CameraOverlayUXPresentation.swift`
- `shafinMultitoolTests/CameraOverlayUXPresentationTests.swift`
- `shafinMultitoolTests/DecisionTracePresentationTests.swift`

## Critique engine

`shafinMultitool/Multitool2Module/Services/Critique/FrameCritiqueEngine.swift` takes a feature snapshot and scene semantics, then produces `CritiqueReport` with issues, strengths and evidence references. Verified deterministic eval shows measurable uplift over `legacy_suggestion_engine`.

Confirmed metrics from `docs/cameraanalysis/eval/out_v1/compare_report.json`:

| Metric | Baseline | Candidate | Delta |
|---|---:|---:|---:|
| issue_f1 | 0.888889 | 1.000000 | +0.111111 |
| primary_action_match_rate | 0.666667 | 1.000000 | +0.333333 |
| strength_f1 | 0.666667 | 1.000000 | +0.333333 |
| explanation_faithfulness_score | 0.775000 | 0.950000 | +0.175000 |
| fallback_policy_accuracy | 0.666667 | 1.000000 | +0.333333 |
| unsupported_claim_rate | 0.000000 | 0.000000 | 0.000000 |
| release_recommendation.status | - | `pass` | - |

## Recommendation planner and semantic tips

| Component | Role | Files |
|---|---|---|
| `RecommendationPlanner` | Converts critique into action plan and overlays. | `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` |
| `SemanticTipPlanner` | Ranks and formats grounded live/pause tips. | `shafinMultitool/Multitool2Module/Services/Recommendation/SemanticTipPlanner.swift` |
| `VisualSemanticEvidenceCoordinator` | Optional VLM evidence provider path and validation. | `shafinMultitool/Multitool2Module/Services/Reasoning/VisualSemanticEvidenceCoordinator.swift` |

## Semantic dataset eval bridge

Current semantic-tip work adds a dataset/eval bridge and a measured DEBUG real-runtime still-image replay. It is still not final product accuracy.

| Artifact | Current status |
|---|---|
| `semantic_labels_v1.jsonl` | 107-image silver label set with good/mixed/bad, expected live/pause actions, forbidden actions and confidence targets. |
| Python eval | Validates labels, validates candidate outputs, merges separate `live` and `pause` rows and produces set/bucket reports. |
| Swift producer | `SemanticEvalCandidateOutput` serializes live/pause presentation rows into the eval contract. |
| Still-image replay | DEBUG API `testingReplayStillImageForSemanticEval(...)` can replay one still image and export rows. |
| Demo semantic pack | `docs/cameraanalysis/demo/semantic_demo_scenarios.json` pins 8 replayable demo cases for keep, reframe, step back/closer, light, background, hotspot/horizon and current generic object-balance actions. |
| Runtime claim guardrail | `lightweightTest` cannot claim real runtime; only `fullRuntime` may emit `real_runtime_still_replay`. |

Latest measured candidate: `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r21a`.

| Metric | Value |
|---|---:|
| `record_count` | 107 |
| `pass_rate` | 1.000000 |
| `expected_action_hit_rate` | 1.000000 |
| `future_action_hit_rate` | 1.000000 |
| `forbidden_action_violation_rate` | 0.000000 |
| `good_frame_preservation_rate` | 1.000000 |
| `positive_confirmation_rate` | 1.000000 |
| `confidence_band_accuracy` | 1.000000 |
| `demo_priority_pass_rate` | 1.000000 |
| `technical_failure_gate_rate` | 1.000000 |

Honesty boundary: this is stronger evidence than the old proxy baseline because it replays the app-side Swift pipeline over the 107-image silver set. It is still not final dissertation performance evidence: live camera motion, UI timing, broader datasets, object/multi-subject grounding and scene-intent confidence remain open. The latest R21a slice adds runtime-observable `frame_aspect_ratio` evidence after R18a completed expected-action/future-action recall and R19b/R20a reduced confidence failures. It preserves forbidden-action control, good-frame preservation and positive confirmations. The current silver still replay has no strict failures, and the demo pack pins 8 user-facing semantic scenarios, but this must be described as still-image dataset/eval and demo-hardening evidence, not live-camera product readiness.

Decision-trace UI boundary: the `Почему?` sheet demonstrates explainability of the current presentation chain, not independent causal proof. It is appropriate for demo/defense because it exposes the internal verdict/evidence/action/signal/trace structure, but it still depends on the upstream live/pause analysis quality and the same product-readiness gaps above.

## Neural evidence wrapper

`shafinMultitool/Multitool2Module/Services/Pipeline/NeuralEvidenceInferenceService.swift` defines provider descriptors, requests, output shape checks, cadence policies, timeout/policy skipped outcomes and recorded metadata. This is a mobile-first wrapper around neural evidence, not proof of neural uplift by itself.

Hybrid eval status from `docs/cameraanalysis/eval/out_hybrid_example/**`:

| Signal | Value | Interpretation |
|---|---:|---|
| `fusion_trace_coverage_rate` | 1.0 | Traceability path works in smoke. |
| `head_policy_agreement_rate` | 1.0 | Head policy agrees in smoke. |
| `status_trace_consistency_rate` | 1.0 | Status and trace are consistent in smoke. |
| `safe_noop_rate` | 1.0 | Safe fallback/noop behavior is demonstrated. |
| `pause_execute_success_rate` | 0.0 | Mobile execution gate blocks release claim. |
| `release_verdict` | `mobile_blocked` | No final claim of neural uplift. |

## Live/pause modes

| Mode | Confirmed behavior |
|---|---|
| live | Supports lightweight hints/presentation; neural path is policy-gated and may skip. |
| pause | Supports deeper critique; hybrid smoke intended for pause but currently `mobile_blocked`. |

## What can be used as separate contribution

1. A typed domain contract for explainable camera critique.
2. Deterministic critique engine with verified uplift over legacy suggestions.
3. Evaluation harness that checks quality, unsupported claims and mobile gates.
4. Neural evidence wrapper as architecture contribution, but not yet as proven quality improvement.

## Links to litreview

| Litreview topic | Camera Analysis bridge |
|---|---|
| Aesthetic assessment | Project uses aesthetic/CoreML wrapper as one feature source, not as the only final answer. |
| Computer vision on mobile | Pipeline combines Vision/DETR/horizon/lighting/aesthetic signals. |
| Lack of explainable recommendations | Critique reports and evidence refs address this gap directly. |
| Mobile constraints | Cadence, thermal, policy skip and hybrid mobile gates formalize the constraint. |
