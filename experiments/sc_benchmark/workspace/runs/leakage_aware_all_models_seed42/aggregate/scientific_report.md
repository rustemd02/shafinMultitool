# Scientific Benchmark Report

## Setup
- config: `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/benchmark_config.seed42.leakage_aware_all_models.json`
- eval_bundle_dir: `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/eval_bundle_v1_leakage_aware_all_models`
- total_scored_runs: 9
- total_pairwise_compares: 10

## Model Summary (mean ± std across seeds)

| model_id | seeds | overall.json_valid_rate | hard.chronology_phase_accuracy | real_runtime.runtime_fallback_rate | overall.case_strict_success_rate |
| --- | ---: | ---: | ---: | ---: | ---: |
| base_qwen3_1_7b | 1 | 0.4714 ± 0.0000 | 0.0000 ± 0.0000 | 1.0000 ± 0.0000 | 0.0000 ± 0.0000 |
| dataset_v7 | 1 | 0.9929 ± 0.0000 | 0.0000 ± 0.0000 | 1.0000 ± 0.0000 | 0.0214 ± 0.0000 |
| dataset_v7_orpo_iter1 | 1 | 0.9500 ± 0.0000 | 0.0000 ± 0.0000 | 1.0000 ± 0.0000 | 0.0286 ± 0.0000 |
| dataset_v7_orpo_iter2 | 1 | 0.9500 ± 0.0000 | 0.0000 ± 0.0000 | 1.0000 ± 0.0000 | 0.0214 ± 0.0000 |
| dataset_v8_plan_orpo_iter1 | 1 | 0.9429 ± 0.0000 | 0.0476 ± 0.0000 | 0.0000 ± 0.0000 | 0.1429 ± 0.0000 |
| dataset_v8_plan_sft | 1 | 0.9286 ± 0.0000 | 0.0635 ± 0.0000 | 0.0000 ± 0.0000 | 0.1429 ± 0.0000 |
| dataset_v9_2_event_sft_policy_v93 | 1 | 1.0000 ± 0.0000 | 1.0000 ± 0.0000 | 0.0000 ± 0.0000 | 1.0000 ± 0.0000 |
| dataset_v9_3_event_sft | 1 | 1.0000 ± 0.0000 | 0.9841 ± 0.0000 | 0.0000 ± 0.0000 | 0.9929 ± 0.0000 |
| dataset_v9_event_sft | 1 | 1.0000 ± 0.0000 | 1.0000 ± 0.0000 | 0.0000 ± 0.0000 | 1.0000 ± 0.0000 |

## Pairwise Results

| candidate | baseline | seed | wins_candidate | wins_baseline | ties | sign_test_pvalue | delta_pp.json_valid_rate | delta_pp.exact_marked_object_id_accuracy | delta_pp.chronology_phase_accuracy |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| dataset_v7 | base_qwen3_1_7b | 42 | 138 | 0 | 2 | 0.000000 | 52.143 | 100.000 | 2.143 |
| dataset_v7_orpo_iter1 | dataset_v7 | 42 | 1 | 7 | 132 | 0.070312 | -4.286 | 0.000 | 0.714 |
| dataset_v7_orpo_iter2 | dataset_v7_orpo_iter1 | 42 | 2 | 2 | 136 | 1.000000 | 0.000 | 0.000 | -0.714 |
| dataset_v8_plan_sft | dataset_v7_orpo_iter2 | 42 | 104 | 34 | 2 | 0.000000 | -2.143 | 0.000 | 12.143 |
| dataset_v8_plan_orpo_iter1 | dataset_v8_plan_sft | 42 | 5 | 5 | 130 | 1.000000 | 1.429 | 0.000 | 0.000 |
| dataset_v9_event_sft | dataset_v8_plan_orpo_iter1 | 42 | 120 | 0 | 20 | 0.000000 | 5.714 | 0.000 | 85.714 |
| dataset_v9_2_event_sft_policy_v93 | dataset_v9_event_sft | 42 | 0 | 0 | 140 | 1.000000 | 0.000 | 0.000 | 0.000 |
| dataset_v9_3_event_sft | dataset_v9_event_sft | 42 | 0 | 1 | 139 | 1.000000 | 0.000 | 0.000 | -0.714 |
| dataset_v9_3_event_sft | dataset_v8_plan_orpo_iter1 | 42 | 119 | 0 | 21 | 0.000000 | 5.714 | 0.000 | 85.000 |
| dataset_v9_3_event_sft | dataset_v7_orpo_iter2 | 42 | 137 | 0 | 3 | 0.000000 | 5.000 | 0.000 | 97.143 |

## Slice Summary

| model_id | seed | slice | json_valid_rate | schema_valid_rate | ordinal_actor_binding_accuracy | target_resolution_accuracy | chronology_phase_accuracy | action_recall | runtime_fallback_rate | case_strict_success_rate |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| dataset_v8_plan_orpo_iter1 | 42 | model_only | 0.9429 | 0.9429 | 0.8385 | 0.4103 | 0.1429 | 0.4108 | 0.4714 | 0.1429 |
| dataset_v8_plan_orpo_iter1 | 42 | end_to_end | 0.9429 | 0.9429 | 0.8385 | 0.4103 | 0.1429 | 0.4108 | 0.4714 | 0.1429 |
| dataset_v8_plan_sft | 42 | model_only | 0.9286 | 0.9286 | 0.8323 | 0.4000 | 0.1429 | 0.3966 | 0.4786 | 0.1429 |
| dataset_v8_plan_sft | 42 | end_to_end | 0.9286 | 0.9286 | 0.8323 | 0.4000 | 0.1429 | 0.3966 | 0.4786 | 0.1429 |
| dataset_v9_2_event_sft_policy_v93 | 42 | model_only | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 0.0000 | 1.0000 |
| dataset_v9_2_event_sft_policy_v93 | 42 | end_to_end | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 0.0000 | 1.0000 |
| dataset_v9_3_event_sft | 42 | model_only | 1.0000 | 1.0000 | 1.0000 | 0.9966 | 0.9929 | 0.9972 | 0.0000 | 0.9929 |
| dataset_v9_3_event_sft | 42 | end_to_end | 1.0000 | 1.0000 | 1.0000 | 0.9966 | 0.9929 | 0.9972 | 0.0000 | 0.9929 |
| dataset_v9_event_sft | 42 | model_only | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 0.0000 | 1.0000 |
| dataset_v9_event_sft | 42 | end_to_end | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 1.0000 | 0.0000 | 1.0000 |

## V8 Local Plan Slice Summary

| model_id | seed | slice | plan_parse_rate | plan_reference_binding_accuracy | plan_beat_integrity_accuracy |
| --- | ---: | --- | ---: | ---: | ---: |
| dataset_v8_plan_orpo_iter1 | 42 | local_plan_raw | 0.9580 | 0.7595 | 0.2786 |
| dataset_v8_plan_sft | 42 | local_plan_raw | 0.9580 | 0.7634 | 0.2748 |

## Slice Reason Codes

| model_id | seed | reason_code | count |
| --- | ---: | --- | ---: |
| dataset_v8_plan_orpo_iter1 | 42 | v8.invalid_spatial_relation_skipped | 11 |
| dataset_v8_plan_orpo_iter1 | 42 | v8.targetless_action_downgraded | 58 |
| dataset_v8_plan_sft | 42 | v8.invalid_spatial_relation_skipped | 10 |
| dataset_v8_plan_sft | 42 | v8.targetless_action_downgraded | 57 |
| dataset_v9_2_event_sft_policy_v93 | 42 | v9.action_type_repaired | 5 |
| dataset_v9_2_event_sft_policy_v93 | 42 | v9.described_text_repaired | 5 |
| dataset_v9_event_sft | 42 | v9.action_type_repaired | 2 |
| dataset_v9_event_sft | 42 | v9.described_text_repaired | 2 |

## Artifacts
- `runs_scored.csv`
- `model_summary.csv`
- `pairwise_compare.csv`
- `model_slice_summary.csv`
- `model_slice_summary_by_model.csv`
- `v8_plan_slice_summary.csv`
- `v8_plan_slice_summary_by_model.csv`
- `slice_reason_codes.csv`
- `slice_gate_results.csv`
- `slice_gate_winner.json` (when at least one candidate passes)
- `reports/` (raw eval harness outputs)
- `compares/` (A/B per-seed outputs)
