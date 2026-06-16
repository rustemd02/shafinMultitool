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
