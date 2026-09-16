# Camera Analysis Snapshot

2026-09-16 storage sync (`EV-LOCAL-DATA-MOVE-001`, `CL-LOCAL-DATA-MOVE-001`): historical external SETOS paths now resolve under `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/`; see `../setos-backend/LOCAL_DATA.md` from the repository root. Original receipts and annotation journal bytes are preserved. Current reviewer media checks cover 300 photos, 84 videos and 252 video frames. No ML/product capability changed; chapters 4/5 remain `needs_update`, historical metric claims are not upgraded.

2026-09-15 visual-prefetch sync (`EV-CA-LANGUAGE-REVIEW-001`, `CL-CA-LANGUAGE-REVIEW-001`): the loopback reviewer now gives Command Code `meta/muse-spark-1.3-contributor` one reduced photo or three ordered video frames, prepares the visible item plus five successors through one paid worker, and presents the result for keyboard acceptance or natural-language correction. Six live proposals verified the scheduling/vision path after one first-revision local validation rejection; they do not verify aesthetic correctness. Append-only machine proposals remain human_gold=false, and accepted assisted records do not become independent gold. Explicit spatial goals are preserved but not coerced into v2 deltas (`training_ready=false`). The model has no Command Code ZDR route, so media egress is disclosed. The prior blind Tk/ROI workflow remains intact. No iOS runtime, model training, gold admission or release capability changed; chapters 4/5 remain `needs_update`.

2026-09-14 annotation-tooling sync (`EV-CA-HUMAN-PILOT-002`, `CL-CA-HUMAN-PILOT-002`): a 300-frame pilot now separates 100 blind and 200 assisted reviews before teacher labeling, with a direct parser-checked export to the existing v2 contract. Human reviews start at zero; machine proposals never become gold by their presence. Unchosen actions, risk, abstention, absent ROI/intent and borderline binary quality stay appropriately unlabelled. No model training or iOS runtime change was made in this task. See `tools/camera_annotation/README_REVIEW.md`; chapters 4/5 remain `needs_update`, previous historical claims are not retroactively upgraded.

2026-09-13 Q05 round-4 sync (`EV-REL-POLICY-001`, `EV-REL-DEFGAP-001`, `EV-REL-PRODUCERS-001`; claims `CL-REL-POLICY-001`, `CL-REL-DEFGAP-001`, `CL-REL-PRODUCERS-001`): the camera acceptance thresholds are now a versioned executable policy (`evaluation-policy-v1.json` `b1e657b8…`, `schema_version 1.4.0`) behaviorally bound to the gate instrument in **both** directions — a value exactly on a frozen threshold passes its gate, a one-value nudge fails exactly that gate, and coverage is checked both ways; `good_frame_budget` requires the one-sided 95 % upper bound and `min_clusters ≥ 2`; `false_improved` is recorded as having **no evaluator implementation** in the repository. A silent content edit of the real policy gives `freeze_receipt.py --check` exit 1 and a version bump exit 2, restore → PASS (proven this session). Separately, **ten of the 26 §5.1 acceptance rows have a threshold and no operational definition anywhere in the repository** (horizon/light precision, accepted coverage ×3, abstention correctness, verification accuracy, critical forbidden, wrong-direction/target false success) — a prepared 10-row/23-option decision packet is `awaiting_owner_decision` and no producer is allowed to emit a pending row, so no denominator is invented. Six `tools/release/` producers compute the §5 blocks and `test_manifest_key_coverage.py` runs all of them against a 36-quantity map (part produced, part documented gaps). No camera runtime capability or measured acceptance result is claimed; chapters 4/5 remain `needs_update`.

2026-09-13 Q05 round-3 sync (`EV-REL-NEURAL-001`, `EV-CA-SETCONTRACT-001`, `EV-CA-ML-005`; claims `CL-REL-NEURAL-001`, `CL-CA-051`, `CL-CA-052`): the production neural composition model is **absent from the build, not weak** — `compact_neural_evidence_net` is nowhere in the repo and the built Release bundle ships only the NIMA and DETR models, so `isModelAvailable == false` and no neural inference runs; any "the app uses a neural composition model" prose is wrong (`CL-REL-NEURAL-001`). The frozen `SETCompositionNet` contract is not consumed by any production path (`AnalysisPipeline.swift` 0 matches; runtime provider tensors 256/160 vs contract 320/192), the reason C02 slice C is `blocked_contract` and why N11 persistence has no consumer (`CL-CA-051`). The v2 export path is validated as tooling only (7 inputs incl. separate `intent_features [1,9]`, 9 outputs in `head_order`, `overall_max_abs_error = 2.518e-4`, four intent heads respond in both implementations, `release_admissible=false`, `blocked_on=M03,M04`; `pytest ml/camera_coach/tests` 42 passed), and its `.mlpackage` `tree_sha256` is not reproducible so `weights_sha256` is the stable identity (`CL-CA-052`). No new camera runtime capability is claimed; no model, physical-camera or release claim is added. Chapters 4/5 remain `needs_update`; `last_verified_commit` is unchanged (dirty tree).

2026-09-13 Q05 round-2 sync (`EV-CA-VERIFY-003`, `EV-CA-PLAN-002`, `EV-CA-CONTROL-001`, `EV-CA-COPY-001`, `EV-CA-INGRESS-001`, `EV-CA-REVIEW-001`, `EV-CA-TENSOR-001`, `EV-S05-RECORD-001`, `EV-S06-IPAD-001`; claims `CL-CA-040`…`CL-CA-049`): C04.2 and C05 are byte-identical re-confirmations of `CL-CA-037`/`CL-CA-038`, with one correction — the live C05 constants are at `AnalysisPipeline.swift:7346/7356`, not `7321/7331`. C06 makes the control inventory honest (`focusOnTap` installs `.autoFocus`+`.autoExpose`, never a lock; the `focusTapLock` row names `NONE`), C07 is catalog-owned RU+EN copy with the addressee pinned by tests (the pipeline authors no instruction literal), C09 has a fail-closed ingress plus closed Release egress and a review projection that keeps human input out of objective verification, C02 slice B records per-tensor transforms but exposes a ≤1-pixel two-seam crop-geometry gap left to a later package, and S05/S06 confirm the artifact boundary (`acceptedVideoCount > 0`) and the built-product iPad full-screen policy (hint truncation is the 2-line metric budget, not Russian). All of this is in-tree code/test evidence with reported simulator runs; no model, physical-camera or release claim is added. Chapters 4/5 remain `needs_update`; `last_verified_commit` is unchanged (dirty tree).

2026-09-13 M00b: `EV-CA-ML-003` / `CL-CA-036` add the Swift input side of the v2 intent contract (real `CaptureIntent`, explicit `CameraStyleCue → CaptureStyle` mapping, frozen `float32[9]` encoding with unknown≠natural, v2 assembly payload that leaves the 40 scalar slots untouched, fail-closed scorer `predictV2` seam). The Swift 13-test suite and the Python suite read the SAME canonical fixture and pass (Swift `TEST SUCCEEDED`, exit 0, 0 skips, 0 retries; Python 8 checks, exit 0). No exported v2 Core ML model exists (M05/M06), so the app still cannot run the v2 network; the v1 research `.mlpackage` stays excluded and is not relabelled v2. Chapter 4 remains `needs_update`.

Final episode update: `EV-CA-EPISODE-UI-001` final source passed27/27 selected checks, spec/quality rechecks PASS. Content-aware rail sizing is shared by the rendered panel and geometry reservation. Pending repair status below is historical; physical rendering, broad scene quality and release qualification remain open, as does the explicitly excluded incompatible fixture.

2026-09-11 episode follow-up (`EV-CA-EPISODE-UI-001`): selected fresh-replanning and actual capture-path checks now support automatic result presentation and explicit next cycle despite transient KEEP, with stale-result reset fencing. This supplies bounded replanning evidence absent from the earlier preview receipt, not general scene/model quality. Current run25/27, with both failures recorded; rail overflow repair and final verification pending. Chapters4/5 remain `needs_update`.

2026-09-11 bounded implementation update: `EV-CA-PREVIEW-001` / `CL-CA-PREVIEW-001` record explicit Vision/coaching target conversion, one bound live-preview projection, frozen active geometry, terminal clearing and typed frame-global copy with nil target. Parent selected simulator checks passed12/12 followed by1/1 for the final provenance guard. This updates local source integration only; human-gold, model calibration, actual camera pixels, continuous structured replanning and release qualification remain open. Chapters4/5 remain `needs_update`.

Last verified commit: `6e33b14d9cb001c38cdd1271bbbc56863392212e` plus dirty working-tree evidence updates on 2026-06-05.

## Pipeline scope

Design follow-up, 2026-09-11: [domain v3 draft](../../cameraanalysis/03-domain-contracts.md#camera-coach-domain-v3--проект-контракта-для-фото-и-видео) now defines the proposed types, 20 operations, episode/verification and VLM s2 delta for all 68 scenarios (`EV-CA-DESIGN-001`, `CL-CA-014`). This is documented design only, not executable schema or changed runtime. Chapter 4 remains `needs_update`; experimental claims and model qualification are unchanged.

Future requirements note, 2026-09-11: [requirements §23](../../cameraanalysis/camera-analysis-requirements-draft.md#23-camera-coach-для-фото-и-видео-каталог-сценариев-следующего-контракта) now records 68 proposed photo/video coaching cases, including two separately grounded lamps, sequential physical actions, temporal video evidence and before/after checks (`EV-CA-REQ-001`, `CL-CA-013`). This is future-work scope, not a change to the implemented pipeline or experimental results. The current 1.0 local-camera boundary and research-only Stage-2 limits remain. Chapter 4 is already `needs_update`; experimental chapter prose and its status are unchanged because this update supplies no new experiment.

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
| `semantic_labels_v2.jsonl` | 207-record benchmark-ready silver/first-pass still-image label bundle: 96 good, 14 mixed, 97 bad records. It adds 50 cinematic-preservation Apple TV Press frames, 20 imagegen bad stress cases and 30 deterministic synthetic bad paired variants. |
| `semantic_labels_cinematic_preservation_v1.jsonl` | 50 first-pass good-frame labels for deliberate cinematic/stylized frames (`108...157`); intended to test overcorrection avoidance, not aesthetic scoring. |
| Python eval | Validates labels, validates candidate outputs, merges separate `live` and `pause` rows and produces set/bucket reports. |
| Swift producer | `SemanticEvalCandidateOutput` serializes live/pause presentation rows into the eval contract. |
| Still-image replay | DEBUG API `testingReplayStillImageForSemanticEval(...)` can replay one still image and export rows. |
| Demo semantic pack | `docs/cameraanalysis/demo/semantic_demo_scenarios.json` pins 8 replayable demo cases for keep, reframe, step back/closer, light, background, hotspot/horizon and current generic object-balance actions. |
| Runtime claim guardrail | `lightweightTest` cannot claim real runtime; only `fullRuntime` may emit `real_runtime_still_replay`. |

Latest measured candidate: `docs/cameraanalysis/eval/out_semantic_real_runtime_v2_207_sim`.

| Metric | Value |
|---|---:|
| `record_count` | 207 |
| `pass_rate` | 0.632850 |
| `expected_action_hit_rate` | 0.714976 |
| `future_action_hit_rate` | 0.810127 |
| `forbidden_action_violation_rate` | 0.169082 |
| `good_frame_preservation_rate` | 0.906250 |
| `positive_confirmation_rate` | 0.770833 |
| `confidence_band_accuracy` | 0.845411 |
| `demo_priority_pass_rate` | 0.500000 |
| `technical_failure_gate_rate` | 0.962963 |

The previous closed result on `docs/cameraanalysis/eval/out_semantic_real_runtime_after_r21a` remains valid for the original 107-image silver subset and should be reported as a historical closed-subset result, not as the full benchmark result after dataset extension.

Measured source-bucket breakdown from `out_semantic_real_runtime_v2_207_sim/bucket_metrics.json`:

| Source bucket | `record_count` | `pass_rate` | Key observation |
|---|---:|---:|---|
| `curated_user_inbox` | 57 | 1.000000 | Original curated cases remain fully closed. |
| `public_iqa_bad_tail` | 50 | 1.000000 | Original bad-tail slice remains fully closed. |
| `official_promo_cinematic_preservation` | 50 | 0.400000 | Main regression on deliberate cinematic/stylized good frames; `good_frame_preservation_rate=0.820000`, `positive_confirmation_rate=0.560000`. |
| `imagegen_bad_candidate` | 20 | 0.150000 | Strong weakness on synthetic semantic stress; `forbidden_action_violation_rate=0.600000`. |
| `synthetic_bad_paired_apple_tv_press` | 30 | 0.033333 | Hardest slice; `expected_action_hit_rate=0.266667`, `technical_failure_gate_rate=0.857143`. |

Honesty boundary: this is stronger evidence than proxy or oracle smoke because it replays the app-side Swift pipeline over all 207 images and then scores live/pause rows with the same Python eval harness. It is still not final dissertation performance evidence: labels remain silver/first-pass, the run is still-image replay rather than live-camera UX, and broader human-reviewed generalization is not yet proven.

Visual-audit follow-up: a second, more demo-oriented audited subset now exists at `docs/cameraanalysis/dataset/inbox/semantic_labels_v2_minus15_appletv_good_minus8_subtle_bad_minus10_weak_synthetic.jsonl`. It removes 10 visually weak or misleading synthetic/imagegen negatives after manual frame review, then rescored the same runtime outputs on the remaining 174 records.

Latest visually audited demo subset: `docs/cameraanalysis/eval/out_semantic_real_runtime_v2_minus15_appletv_good_minus8_subtle_bad_minus10_weak_synthetic`.

| Metric | Value |
|---|---:|
| `record_count` | 174 |
| `pass_rate` | 0.752874 |
| `expected_action_hit_rate` | 0.804598 |
| `forbidden_action_violation_rate` | 0.132184 |
| `good_frame_preservation_rate` | 0.864198 |
| `positive_confirmation_rate` | 0.827160 |
| `confidence_band_accuracy` | 0.902299 |
| `demo_priority_pass_rate` | 0.648649 |
| `technical_failure_gate_rate` | 0.954545 |

Measured source-bucket breakdown on the audited subset:

| Source bucket | `record_count` | `pass_rate` | Key observation |
|---|---:|---:|---|
| `curated_user_inbox` | 57 | 0.912281 | Original curated slice stays strong. |
| `public_iqa_bad_tail` | 50 | 0.960000 | Original bad-tail slice stays strong. |
| `official_promo_cinematic_preservation` | 35 | 0.600000 | Good-frame preservation remains the main non-synthetic bottleneck. |
| `imagegen_bad_candidate` | 15 | 0.266667 | Improved after removing ambiguous imagegen negatives, but still weak. |
| `synthetic_bad_paired_apple_tv_press` | 17 | 0.352941 | Improved after removing weak/false synthetic negatives, but still not closed. |

Boundary for thesis wording: this audited subset is appropriate for an honest demo/evaluation slice after manual label review. It must not be presented as the replacement for the full stress benchmark or as proof that the runtime generalizes to all synthetic/cinematic cases.

Regenerated bad-bucket follow-up: the ambiguous synthetic/imagegen negatives were replaced with a visually stronger 174-record bundle at `docs/cameraanalysis/dataset/inbox/semantic_labels_v2_minus15_appletv_good_minus8_subtle_bad_minus10_weak_synthetic_regen_bad_v1.jsonl`. It keeps the audited good/cinematic slices, removes the old bad buckets, and adds explicit `ca_img_208...ca_img_239` anti-examples for foreground obstruction, edge cutoff, clutter, hotspot/backlight, underexposure and tiny-subject failure modes.

Latest regenerated bad-bucket replay: `docs/cameraanalysis/eval/out_semantic_real_runtime_v2_regen_bad_v1`. **Current-source status (2026-09-12): these figures are historical-artifact-bound and do not reproduce from the working tree — CL-CA-011 is `conflicts_with_current_code`. A fresh fullRuntime still replay on the content-identical 174-label bundle scored `pass_rate=0.379310` / `good_frame_preservation_rate=0.518519`, with 109/174 pause action sets changed (`EV-CA-EVAL-010`, `CL-CA-016`, `docs/cameraanalysis/eval/camera-baseline-v0/drift-174/`). A single-hunk object edge-pressure calibration then raised the same lane to `pass_rate=0.505747` / `good_frame_preservation_rate=0.839506` with a recorded A/B control run (`EV-CA-EVAL-011`, `CL-CA-017`, `docs/cameraanalysis/eval/camera-baseline-v0/drift-174-calibrated-edge-neutral/`), initially at the cost of one newly failing still-replay expectation test, which the follow-up dominant-technical override (`EV-CA-EVAL-012`, `CL-CA-018`) removed while raising the lane to `pass_rate=0.534483` / phase B 142/35 with no newly failing test.** Instrumentation evidence for the same series also records that the detector is not in signal parity with this historical artifact: `object_count` differs for 66/174 records because DETR box extraction now uses connected-component labelling, so `object_count`/`objectDensity`/`backgroundClutterScore` must not be compared against the numbers above (`EV-CA-EVAL-013`, `CL-CA-019`). The remaining 35 expectation failures are decomposed by class in `EV-CA-EVAL-014` / `CL-CA-020`: nineteen expected framing steps are unattainable because those actions are effectively never emitted, the missing background corrections sit on records with no clutter signal, and the candidate gate that would fix four keeps was measured to remove advice from thirty non-good records, so no further rule change was made. The follow-up signal-viability check (`EV-CA-EVAL-015`, `CL-CA-021`) rejected both proposed detection signals before implementation: the distractor and subject-size signals already exist, their usable formulations would fire on roughly half the good records, and the framing labels are not consistent with measured subject geometry. A follow-up label review and held-out decision (`EV-CA-EVAL-016`, `CL-CA-022`) corrected that reading — `step_back` encodes occlusion/edge cutoff, which the pipeline already detects as the future action `avoid_occlusion` (46 rows lane-wide, 19 of them with no semantic action) — and rejected every clutter threshold for relaxing the isolation rule on a deterministic 87/87 split, so the rule stands unmodified as a known limitation. The occlusion-routing gap is located as well (`EV-CA-EVAL-017`, `CL-CA-023`) — `technicalPauseActions` returns an empty list for `.occlusion`, so a detected occlusion can never become a semantic remark — but closing it is measured as net-negative (2 net expectations against one forbidden violation and 16 unrequested actions), so it is recorded as a limitation rather than fixed. A confidence-parity check (`EV-CA-EVAL-018`, `CL-CA-024`) likewise rejected restoring the historical multiplicative subject confidence (126/174 band matches today against 6/174) and corrected the earlier inference that the raw publication was a parity break likely to hurt alignment. A framing-label audit (`EV-CA-EVAL-019`, `CL-CA-025`) then bounded that class: 14 of 20 framing expectations are consistent with their own problem text and the measured geometry, five name a different family and three expect `step_closer` while the measured subject area contradicts it, so those eight need label or corpus revision and no threshold was fitted to them. The last unmeasured pause-card lever — a pause-verdict confidence gate that silences corrections below a threshold — was then measured across the full threshold range through the canonical scorer and rejected at every threshold (`EV-CA-EVAL-022`, `CL-CA-028`, `docs/cameraanalysis/eval/camera-baseline-v0/drift-174-confidence-gate/`): pause confidence does not separate the 13 overcorrected good frames (median 0.740) from the 65 correctly kept ones (median 0.750), no threshold raises pass_rate above the ungated 93/174 (best 92; 91 at the preservation-optimal t=0.69–0.70 where preservation rises to 0.864198; 81 at t=0.75 where preservation reaches 0.925926), and no threshold approaches the §9.6 forbidden gate of ≤ 0.02, so the pause-confidence lever joins the exhausted set. The 8 `missing_future_action` failures are then fully attributed (`EV-CA-EVAL-023`, `CL-CA-029`, `docs/cameraanalysis/eval/camera-baseline-v0/drift-174-future-action-decomposition/`): 5 occlusion-recall misses where the probe never fires, 2 exposure-direction contradictions (`ca_img_101/223`, labels claim overexposure against measured `exposure_bias` −2.60/−1.71) and 1 sharpness-recall miss — so with EV-CA-EVAL-014/015/019/022 the failure-class accounting for the still-replay lane is closed and every remaining expectation failure is attributed to signal-limited detection or label revision.

| Metric | Value |
|---|---:|
| `record_count` | 174 |
| `pass_rate` | 0.850575 |
| `expected_action_hit_rate` | 0.908046 |
| `future_action_hit_rate` | 0.943662 |
| `forbidden_action_violation_rate` | 0.028736 |
| `good_frame_preservation_rate` | 0.987654 |
| `positive_confirmation_rate` | 0.987654 |
| `confidence_band_accuracy` | 0.925287 |
| `demo_priority_pass_rate` | 0.685185 |
| `technical_failure_gate_rate` | 1.000000 |

Measured regenerated source-bucket breakdown:

| Source bucket | `record_count` | `pass_rate` | Key observation |
|---|---:|---:|---|
| `curated_user_inbox` | 57 | 0.929825 | Original curated subset remains strong, with no forbidden-action violations. |
| `public_iqa_bad_tail` | 50 | 0.960000 | Original public bad-tail subset remains strong. |
| `official_promo_cinematic_preservation` | 35 | 0.885714 | Guarded promo/cinematic preservation is now mostly closed; remaining failures are one unresolved unknown-wide frame and confidence calibration. |
| `imagegen_bad_candidate` | 15 | 0.600000 | Generated bad-image bucket now clears the demo gate, but remains below original curated/public slices. |
| `synthetic_bad_paired_apple_tv_press` | 17 | 0.411765 | Synthetic bad paired bucket now clears the demo gate after contextual runtime hardening, but remains the hardest source bucket. |

Interpretation boundary: the regenerated set is visually clearer and more useful for defense/demo stress testing, and the latest runtime hardening passes the planned still-image replay gates (`overall pass_rate >= 0.80`, `forbidden_action_violation_rate <= 0.08`, `good_frame_preservation_rate >= 0.92`, `synthetic_bad_paired_apple_tv_press >= 0.40`). It is still silver-label still-image evidence: the generated bad buckets are improved rather than closed, one ambiguous unknown-wide promo frame remains unresolved by current runtime features, and live-camera UX/generalization still requires separate validation.

Decision-trace UI boundary: the `Почему?` sheet demonstrates explainability of the current presentation chain, not independent causal proof. It is appropriate for demo/defense because it exposes the internal verdict/evidence/action/signal/trace structure, but it still depends on the upstream live/pause analysis quality and the same product-readiness gaps above.

## SETCompositionNet research lane

On 2026-09-11 the user-operated Colab Stage 1/2 run completed a five-epoch
research fit over 5,597 automatically generated paired-corruption examples.
The receipt proves that only `issue_logits`, `action_utility_logits`, and
`continuous_target_deltas` were trainable. Fit loss decreased monotonically,
and a fresh-input probe excludes an obvious frozen or constant trained-head
failure. A separate external FP16 Core ML `mlprogram` exposes the six frozen
inputs and nine outputs and passes one deterministic CPU parity case.

This is execution/convertibility evidence, not a production-quality claim.
The data is silver rather than human gold; there is no validation split,
calibration or selected-candidate evidence; `good_frame_probability`,
`risk_probability`, and `abstention_probability` remain untrained; and the
package is not present in the Xcode bundle or model registry. Source:
`docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m4/M4-silver-actions-stage2-colab.md`.

## Polza VLM research probes — 2026-09-11

Delivery-plan follow-up (2026-09-11): [master plan §24](../../aegis/work/2026-09-03-gpt-5-6-pro-guidance/SET_OS_APP_STORE_1_0_CODEX_MASTER_PLAN_v2.md#24-план-доведения-до-app-store--2026-09-11) specifies server/client work, Codex-owned source acquisition, independent human annotation, complete-head training/calibration, Colab resume, Core ML/device qualification and UI/release gates. `EV-REL-PLAN-001` / `CL-REL-PLAN-001` are planning evidence only. Existing chapters 4/5 remain `needs_update`; no new model or runtime quality was measured by this documentation change.

User-authorized paid experiments are recorded in [POLZA_RESEARCH_PROBE.md](../../cameraanalysis/eval/POLZA_RESEARCH_PROBE.md), with code, pinned Commons inputs, response snapshots and provider-reported costs. This is separate from Stage-2 training and from s2 app ingress. It tests structure, coarse point localization and explicit constraints, not aesthetic preference, human-gold quality, temporal tracking or live iPhone UX. A bounded debug-only ingress slice is tracked in the same report; production camera egress remains closed. Evidence/claim: `EV-CA-VLM-001`, `CL-CA-015`. Chapters 4 and 5 already remain `needs_update`; no chapter text or protected litreview was changed.

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

Data preparation update (2026-09-11): `EV-CA-DATA-OBJECTS-001` / `CL-CA-DATA-OBJECTS-001` record official Open Images metadata candidate mining. The catalog contains source hashes and counts, not acquired pixels or human-gold. Chapters 4/5 remain `needs_update`; no new model-quality claim follows.

Subsequent pilot acquired one external research JPEG and stored a real Core ML DETR output with SHA-bound receipt (`local_pilot` in the same catalog). The left/right light components expose area-derived confidence admission differences; this is a one-image diagnostic, not app/Vision parity, calibrated confidence, temporal validation or human-gold. The 18-test SubjectTracker result is still under FIX-FIRST spec review and must not be cited as completed multi-object product behavior.

Existing DETR class/mask logits were then exposed in an external research package without weight changes. Compilation, finite outputs and one-input exact hard-map comparison succeeded; this makes a learned-signal qualification experiment possible, but does not establish per-object calibration, identity or release readiness. Receipt: catalog `local_pilot.signals_export_receipt`.

| Litreview topic | Camera Analysis bridge |
|---|---|
| Aesthetic assessment | Project uses aesthetic/CoreML wrapper as one feature source, not as the only final answer. |
| Computer vision on mobile | Pipeline combines Vision/DETR/horizon/lighting/aesthetic signals. |
| Lack of explainable recommendations | Critique reports and evidence refs address this gap directly. |
| Mobile constraints | Cadence, thermal, policy skip and hybrid mobile gates formalize the constraint. |

### 2026-09-11 — Local object association foundation

`EV-CA-TRACK-001` / `CL-CA-TRACK-001` cover the working-tree extension of existing `SubjectTracker`: up to four object states, conservative geometry/label association, stale generation/sequence rejection and historical provenance on loss. Independent review exposed and resolved a mixed active/lost ambiguity; its targeted regression passed on iPhone 17e simulator. The earlier 23-test result predates that last repair and is not represented as a full final-suite run. No qualified detection, live producer/consumer integration, temporal replay or physical-device readiness is established. Chapters 4/5 remain `needs_update`; no chapter prose or protected litreview changed.

### 2026-09-11 — Target identity in the advice handoff

`EV-CA-TARGET-001` / `CL-CA-TARGET-001` cover optional identity propagation through the existing bounded planner, stabilizer and episode admission, including the production candidate construction. The final 16 selected tests passed after fixing unconditional rejection of object identity on frame-global advice. Spec re-review and fresh quality review passed. `currentLiveHint` remains a separate presentation path without this identity contract, so visible object-bound coaching and full R03–R06 acceptance remain open. Chapters 4/5 remain `needs_update`.

### 2026-09-13 — v3 contract layer, N11 transform, stable-target binding and the verify-the-result correction

`EV-CA-V3-001` / `CL-CA-031` record a fail-closed v3 contract validator checked behaviorally against an independent Python validator on one shared 61-case fixture (22 accept / 39 reject, two byte-identical copies); 25 Swift tests `TEST SUCCEEDED` and 8 Python tests passed. `EV-CA-COORD-001` / `CL-CA-032` record that the N11 tensor-transform contract (`CameraTensorTransformContract` requiring `independent_scale_to_target` for `setcompositionnet.v1.full_frame_rgb`/`subject_crop_rgb` and rejecting an aspect-fill recipe), a corrected false doc contract (`CameraCoordinateSpaceV2.modelInput` described aspect-fill while the implementation uses independent scale), a fail-closed `visibleDestinationPoint` and `ObjectTargetBinding` are proven by 97 tests / 0 failures across six suites — but **not wired into production**: `MetalPreprocessor`/`CoreMLNeuralEvidenceProvider` do not return or persist the transform, the registry/binding are not connected to `AnalysisPipeline`, there is no runtime owner for intent revision, and coinciding boxes of two same-label objects cannot be disambiguated by a geometric tracker (the selection must be invalidated). `EV-CA-VERIFY-001` / `CL-CA-033` record that the false `changeCameraAngle → absoluteChange(horizonRotation)` criterion was removed and the action now returns `.uncertain(reason: "unsupported_action")` (64 tests / 0 failures); the action stays in the catalog and yields `incomparable`, and the contour metric is C04.2+. `EV-CA-ML-002` / `CL-CA-034` record the v2 intent/supervision contract and masked trainer (`pytest ml/camera_coach/tests` 24 passed) with the explicit limitation that no admitted-data training happened and the Swift `CaptureIntent` does not exist. `EV-CA-REGISTRY-001` / `CL-CA-030` record the `not_a_stable_contract` v3 registry with 260 conformance checks PASS and 5 injection controls. Therefore "coordinates are fixed in the runtime", "the target is stable in the app" and "the model is trained/ready" are **not** supported. Chapter 4 remains `needs_update`.
