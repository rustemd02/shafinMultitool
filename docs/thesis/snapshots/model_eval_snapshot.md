# Model Eval Snapshot

Last verified commit: `02bdf3ae0b711ed5e0b7a640cbf808196d304b62`

## Scene Generator model/iteration comparison

Values are from available repository artifacts. Percent values from markdown reports are normalized here as decimals when source reports use decimals; do not mix sources without citing the exact table.

| Iteration | Confirmed metrics | Source | Status |
|---|---|---|---|
| base | SG v7 primary table: `json_valid=34.73%`, `schema_valid=0.00%`, `runtime_fallback=100.00%`; later iter2 table uses `base_qwen3_1_7b json_valid=42.75%`. | `experiments/sc_benchmark/reports/v6_v7/combined_eval_base_v6_v7_v7_orpo.md` | verified with source-context caveat |
| v6 | SG v7 primary table: `json_valid=1.53%`, `schema_valid=1.53%`, fallback `100.00%`; legacy v6 table separately reports `json_parse_rate=100.00%`, `schema_valid_rate=55.02%`. | same report | verified; do not compare legacy and SG v7 contracts as equivalent |
| v7 | `json_valid=98.85%`, `schema_valid=98.85%`, `case_strict_success=2.29%`, `exact_marker_id=100.00%`, `ordinal_binding=98.26%`. | same report; V8 scientific report | verified |
| v7_orpo_iter1 | V8 report model_only: `json_valid=0.9656`, `schema_valid=0.9618`, `target_resolution=0.0940`, `chronology=0.0725`, `case_strict_success=0.0267`. | `docs/SGv8pipeline/runs/v8_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md` | verified |
| v7_orpo_iter2 | V8/V9 reports model_only: `json_valid=0.9504`, `schema_valid=0.9466`, `target_resolution=0.1128`, `chronology=0.0840`, `action_recall=0.1066`, `strict=0.0344`. | `docs/SGv8pipeline/runs/v8_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md`, `docs/SGv9pipeline/runs/v9_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md` | verified |
| v8_plan_sft | `json_valid=0.9466`, `schema_valid=0.5649`, `ordinal_binding=0.8403`, `target_resolution=0.4684`, `chronology=0.1412`, `action_recall=0.4572`, `strict=0.0954`; plan raw parse `0.9580`, reference binding `0.7634`, beat integrity `0.2748`. | `docs/SGv8pipeline/runs/v8_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md` | verified |
| v8_plan_orpo_iter1 | `json_valid=0.9504`, `schema_valid=0.5649`, `ordinal_binding=0.8385`, `target_resolution=0.4803`, `chronology=0.1412`, `action_recall=0.4741`, `strict=0.1031`; plan raw parse `0.9580`, reference binding `0.7595`, beat integrity `0.2786`. | `docs/SGv8pipeline/runs/v8_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md`, `docs/SGv9pipeline/runs/v9_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md` | verified |
| v9_event_sft | Compiled slice: `json_valid=1.0000`, `schema_valid=0.6069`, `ordinal_binding=1.0000`, `target_resolution=0.9214`, `chronology=0.8702`, `action_recall=0.9355`, `runtime_fallback=0.4351`, `strict=0.5076`. | `docs/SGv9pipeline/runs/v9_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md` | verified |
| v9_2_event_sft | User-provided V9.2 predictions before policy fix: `json_valid=1.0000`, `schema_valid=0.6069`, `ordinal_binding=1.0000`, `target_resolution=0.9812`, `chronology=0.9695`, `action_recall=0.9846`, `runtime_fallback=0.4198`, `strict=0.5573`. | `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions/benchmark_results_seed42/aggregate/scientific_report.md` | verified |
| v9_2_event_sft + v9_3_policy_replay | Same frozen V9.2 predictions after V9.3 policy correction: `json_valid=1.0000`, `schema_valid=1.0000`, `ordinal_binding=1.0000`, `target_resolution=0.9812`, `chronology=0.9695`, `action_recall=0.9846`, `runtime_fallback=0.0038`, `strict=0.9695`. | `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions_policy_v93/benchmark_results_seed42/aggregate/scientific_report.md`, `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions_policy_v93/fallback_audit/v9_2_to_v9_3_policy_audit.md` | verified replay; not a retrained checkpoint |
| v9_3_event_sft dataset | Prepared training dataset: `5564` mixed rows, `4730` train, `834` val, with `278` new V9.3 targeted rows. | `docs/SGv9pipeline/runs/v9_3_seed42/mixed_event_sft/v9_3_event_sft_mixed_manifest.json`, `docs/SGv9pipeline/runs/v9_3_seed42/V9_3_TRAIN_BENCH_RUNBOOK.md` | verified |
| v9_3_event_sft | Fresh V9.3 successor predictions: `json_valid=1.0000`, `schema_valid=1.0000`, `ordinal_binding=1.0000`, `target_resolution=0.9983`, `chronology=0.9962`, `action_recall=0.9986`, `runtime_fallback=0.0000`, `strict=0.9962`; demo-parity `3/3`. | `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/v9_3_post_train_eval_summary.json`, `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/benchmark_results_seed42/aggregate/scientific_report.md`, `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/demo_parity_validation/demo_parity_results.json` | verified |
| live smoke v8 | Real GGUF v8 live smoke: `passed=0/12`, runtime about 808 seconds, model loaded. | `diploma.md` entry 2026-04-26 | partially_verified; attach xcresult before final defense |
| live smoke v9 | V9 runtime hardening entry reports `SceneV8PipelineTests/testLiveLocalModelDatasetSampledCases()` `1/1 passed`, no failures. | `diploma.md` entry 2026-05-04 | partially_verified; attach xcresult before final defense |

## Strict refresh audit

The earlier `clean140` holdout is now treated as an intermediate artifact, not the final honest benchmark slice. After stricter normalized matching by `sample_id`, exact `source_text`, `normalized_source_hash`, and `graph_family_key` with short-hash normalization, the historical `eval_bundle_v1` retains `0/262` leakage-safe cases.

| Artifact | Current verified statement | Source | Status |
|---|---|---|---|
| Historical `eval_bundle_v1` | Under strict matching it retains `0/262`; all 262 cases overlap the checked train corpora by `sample_id` and `graph_family_key`, with 95 direct source-text collisions and 89 normalized-source-hash collisions. | `experiments/sc_benchmark/workspace/eval_bundle_v2_fresh262_all_models/strict_overlap_audit.json` | verified |
| Intermediate `clean140` slice | The 140-case all-model holdout remains useful as an intermediate methodological probe, but it is superseded and should not be presented as the final honest model-vs-model slice. | `experiments/sc_benchmark/workspace/eval_bundle_v1_leakage_aware_all_models/leakage_audit.json`, `experiments/sc_benchmark/workspace/runs/leakage_aware_all_models_seed42/aggregate/scientific_report.md` | obsolete as final slice |
| Strict `fresh262` bundle | A new fully refreshed bundle preserves `N=262` with `109 synthetic_heldout`, `89 hard_heldout`, `64 real_runtime`; under the same strict audit it retains `262/262` cases. The `real_runtime` slice is rebuilt as synthetic runtime proxies because no unused leakage-safe runtime reserve remained inside the historical SG v7 pools. | `experiments/sc_benchmark/workspace/eval_bundle_v2_fresh262_all_models/eval_bundle_manifest.json`, `experiments/sc_benchmark/workspace/eval_bundle_v2_fresh262_all_models/strict_overlap_audit.json` | verified |
| Fresh262 metrics | No honest cross-model metrics are recorded yet for `fresh262`, because every compared model needs regenerated predictions on the new bundle. Historical prediction exports from `eval_bundle_v1` cannot be reused. | `experiments/sc_benchmark/workspace/benchmark_config.seed42.fresh262_all_models.json`, `experiments/sc_benchmark/workspace/fresh262_rerun_instructions.md` | pending rerun |

## V9 raw event-table metrics

| Metric | Value | Source |
|---|---:|---|
| case_count | 262 | `dataset_v9_event_sft_seed42.event_slice_summary.json` |
| event_parse_rate | 1.0000 | same |
| event_schema_valid_rate | 1.0000 | same |
| event_actor_slot_accuracy | 0.9691 | same |
| event_target_slot_accuracy | 0.9439 | same |
| event_action_type_accuracy | 0.9621 | same |
| event_beat_order_accuracy | 0.9677 | same |
| event_full_row_accuracy | 0.9355 | same |
| chunk_event_coverage_rate | 0.9355 | same |
| cross_chunk_* metrics | null | same; needs_source for continuity claims |

## Claims not safe yet

| Potential claim | Why unsafe | Status |
|---|---|---|
| “V9 is universally better than all earlier models.” | Evidence is seed42 frozen eval and specific live smoke, not broad production distribution. | needs_source |
| “V9.3 is strictly better than V9.0 in a pure model-vs-model sense.” | Full-bundle gain is real for the 262-case benchmark context, but the leakage-aware 140-case all-model holdout does not support strict dominance: V9.0 is perfect there, while V9.3 misses one hard three-beat case. | verified |
| “Hybrid Camera Analysis neural evidence improves quality.” | Current hybrid smoke is `mobile_blocked`; deterministic v1 is verified. | needs_source |
| “Chunk-native continuity is quantitatively solved.” | V9 event summary has null cross-chunk continuity metrics. | needs_source |
| “V9.3 trained model reaches the policy-replay metrics.” | Fresh V9.3 predictions exceed the V9.3 acceptance gate, but still leave 1 mined `dialogue_action` hard case; phrase as measured benchmark result, not universal correctness. | verified |

## Q05 eval sync — 2026-09-13

| Item | Measured fact | Source | Status |
|---|---|---|---|
| D05 numeric gates (frozen 262 predictions) | `json_valid/schema_valid 1.0`, `target_resolution 0.99829`, `chronology 0.99618`, `action_recall 0.99860`, `marked_object_recall 1.0`, `ordinal_binding 1.0`, `dangling_target_rate 0.0`, `runtime_fallback 0.0`, demo-parity 3/3 — master thresholds ≥.99/.985/.99 exceeded. | `EV-SG-D05-001`, `D01-D05-rights-and-corpora.md` | verified numerically |
| D05 full packet | **Does not pass:** eval bundle 100 % RU against an EN ≥35 % requirement, provenance synthetic/runtime_reviewed without independent human-gold, several gates not measured by this evaluator (clarification recall, hallucinated objects, critical corruption, boundaries F1), 6000/800/1200 floors unconfirmed, and a scored external fine-tuned V9.3 artifact rather than the on-device provider. | `EV-SG-D05-001`, `CL-SG-D05-001` | verified negative/limitation |
| “The v2 composition model is trained/ready.” | The v2 contract and masked trainer are verified (`pytest ml/camera_coach/tests` 24 passed; real gradient check with `count_nonzero(grad) == 0` on a fully masked delta head; resume `max abs diff = 0.0`), but no admitted-data training happened (0 admitted records) and the Swift `CaptureIntent`/`intent_features` side does not exist. | `EV-CA-ML-002`, `CL-CA-034` | not supported |
| “The app can run the v2 composition model.” | **Not supported:** M00b added the Swift input side (real `CaptureIntent`, `CaptureIntentFeatureContract` with unknown≠natural, v2 assembly payload and a fail-closed scorer seam) plus a shared-fixture Swift/Python parity suite (Swift `Executed 13 tests, 0 failures`, `TEST SUCCEEDED`, exit 0, 0 skips, 0 retries; Python 8 checks, exit 0), but no exported v2 Core ML model exists (M05/M06) and the v1 research package stays excluded from the app target, so `declaresV2IntentInput == false` and `predictV2` returns `nil`. | `EV-CA-ML-003`, `CL-CA-036` | not supported |
| Release-candidate gate arithmetic | The gate instrument computes proof statistics itself; Clopper–Pearson `0/81 = 3.6309 %` (matches runbook ~3.6), `0/100 = 2.951 %`, minimum 149 clean advised-good frames for the 2 % budget (148 do not), fail-closed exit 2 without a candidate manifest; 41 self-tests, full `tools/tests` 114 passed. | `EV-REL-GATES-001`, `CL-REL-GATES-001` | verified (instrument scope) |

## Q05 eval sync round 3 — 2026-09-13

Scope note: paths, sha256, Python counts and Core ML shapes were re-read or re-derived from the in-tree artifacts this session; no simulator run. `last_verified_commit` unchanged (dirty tree at `0733df2…`).

| Item | Measured fact | Source | Status |
|---|---|---|---|
| “The app uses a neural composition model.” | **Not supported, and the stronger negative is measured on the build:** `compact_neural_evidence_net` exists nowhere in the repository and the built Release `.app` contains exactly `aesthetic_nima_mobilenet_fp16.mlmodelc` and `DETRResnet50SemanticSegmentationF16P8.mlmodelc`, so `isModelAvailable == false` and no neural inference runs; the app works on the deterministic path plus two auxiliary models. The research `SETCompositionNet-Stage2-Local.mlpackage` is excluded from the target by `membershipExceptions`. | `EV-REL-NEURAL-001`, `CL-REL-NEURAL-001`, built Release bundle, `CoreMLNeuralEvidenceProvider.swift:18-33`, `project.pbxproj:67` | verified negative |
| Frozen `SETCompositionNet` contract consumption | **No production consumer:** `AnalysisPipeline.swift` has 0 matches for `setCompositionNet`/`CameraTensorTransform`/`SETCompositionNet`; the runtime provider builds 256×256 and 160×160 tensors while the contract and the v2 export declare 320 and 192. C02 slice C is `blocked_contract`; the N11 producer has no consumer. | `EV-CA-SETCONTRACT-001`, `CL-CA-051` | verified contract block |
| M05 v2 export path | The export path is built and validated **as tooling only**: `python3 -m pytest ml/camera_coach/tests/ -q` → **42 passed** (+11 export tests); a `coremltools` spec read confirms 7 inputs including a separate `intent_features [1,9]` and 9 outputs in the manifest `head_order`; parity `overall_max_abs_error = 2.518e-4`; all four intent-conditioned heads `both_respond_to_intent = true`; provenance `release_admissible=false`, `blocked_on="M03,M04 admitted data (0 admitted)"`. **Finding:** the `.mlpackage` `tree_sha256` is not reproducible (two fresh runs gave different hashes from the in-tree one) while `weights_sha256` is stable, so `weights_sha256` is the stable identity. Still not trained/calibrated; M05 remains `blocked_external`. | `EV-CA-ML-005`, `CL-CA-052` | tooling only / partially_verified |

## Q05 eval sync round 4 — 2026-09-13

Scope note: paths, sha256, JSON facts and Python counts were re-read or re-run from the in-tree files this session (`python3 -m pytest tools/tests` → **467 passed**); no Swift/simulator run. `last_verified_commit` unchanged (dirty tree at `0733df2…`). This round supersedes earlier instrument identities: `check_candidate_gates.py` is now `1e9da48b…57dbd01d`, `plan_abstention_threshold.py` is now `ae37afbb…3ae5b785`.

| Item | Measured fact | Source | Status |
|---|---|---|---|
| Acceptance policy is versioned and behaviorally bound | `evaluation-policy-v1.json` `b1e657b8…83b4580a` (`schema_version 1.4.0`) is thresholds-only and bound to the gate instrument in both directions (at-threshold passes; a one-value nudge fails exactly that gate; precision distinguishes point-met/Wilson-short as `insufficient_evidence`; coverage checked both ways). `good_frame_budget` needs the 95 % upper bound and `min_clusters ≥ 2` and forbids all-KEEP/all-ABSTAIN; `false_improved.definition_source.evaluator_extraction` is explicitly **NOT AVAILABLE** (no evaluator computes it); `trained_head_mask` is required before the locked test. On the **real** artifact a silent content edit gives `--check` exit 1 and a version bump exit 2 ("requires impact list"); restore → PASS exit 0. | `EV-REL-POLICY-001`, `CL-REL-POLICY-001`, `test_evaluation_policy_binding.py` (30 tests), `freeze_receipt.py` | verified (instrument/contract) |
| Ten §5.1 rows have no operational definition | Ten of 26 `runbook_5_1_rows` are `pending_definition` (two precision rows, accepted coverage ×3, abstention correctness, verification accuracy, critical forbidden, wrong-direction/target false success); a repo search finds no numerator/denominator/unit for them. A decision packet (10 rows, 23 options) is prepared and stays `awaiting_owner_decision`; a test forbids any producer from emitting a pending row, so no denominator is invented. | `EV-REL-DEFGAP-001`, `CL-REL-DEFGAP-001`, `definition-packet-5-1.json`, `test_evaluation_policy_rows.py`, `test_definition_packet.py` | verified finding |
| Six §5 producers + executable key coverage | Six `tools/release/` producers compute the manifest blocks (candidate manifest with `set_metrics.json` anti-drift check; episode confusion + both false_improved ratios refusing unverified improvements; paired arms with clusters `[hits_a,n_a,hits_b,n_b]` and neural block only for declared arms; weight lineage from provenance + admitted rights; gold block refusing <2 annotators; human block by the §4.2 conjunction excluding assisted/non-blind). `test_manifest_key_coverage.py` runs all six and checks each of **36** gate quantities is produced (verified by running) or a documented gap (14 entries). | `EV-REL-PRODUCERS-001`, `CL-REL-PRODUCERS-001`, `tools/tests/test_manifest_key_coverage.py` | verified (tooling) |
| Rehearsals on real artifacts | Packet A on the real 319-frame manifest: 146 notices all for the admitted film, splits `frames=146/319`, quarantine excluded, live manifest untouched. Packet B: real label builders → full gold block **passes** `gold_independence_and_kappa`. Packet G: apply choices → freeze `--check` exit 2 → `--write` → PASS. Packet D: all 20 packet `check_id`s known to the importer; accepting a report is explicitly **not** a hardware PASS. Limit: three first fixtures were rejected by the tools' own invariants, so rehearsal proves connectivity, not data quality. | `EV-REL-REHEARSAL-001`, `CL-REL-REHEARSAL-001`, `EXECUTION_STATE.md` | partially_verified (methodology) |
