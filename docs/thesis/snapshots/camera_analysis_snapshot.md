# Camera Analysis Snapshot

Last verified commit: `02bdf3ae0b711ed5e0b7a640cbf808196d304b62`

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
| Neural evidence | Optional neural snapshot, metadata, policy outcomes and fusion decisions. | `NeuralEvidenceInferenceService.swift`, `HybridFusionService.swift` |

## Explainability contract

The explainability design requires critique/recommendations to point back to evidence instead of emitting unsupported advice. This is project evidence for the litreview gap: existing tools may score frames, while the prototype attempts to explain why a frame should be adjusted.

Primary sources:
- `docs/cameraanalysis/04-explainability-contract.md`
- `docs/cameraanalysis/19-neural-evidence-domain-contract.md`
- `docs/cameraanalysis/23-hybrid-eval-harness.md`
- `CameraAnalysisDomainContracts.swift`

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
