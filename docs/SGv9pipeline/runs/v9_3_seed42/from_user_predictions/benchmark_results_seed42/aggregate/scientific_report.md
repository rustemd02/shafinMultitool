# Scientific Benchmark Report

## Setup
- config: `/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/benchmark_config.v9.seed42.json`
- eval_bundle_dir: `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/eval_bundle_v1`
- total_scored_runs: 3
- total_pairwise_compares: 3

## Model Summary (mean ± std across seeds)

| model_id | seeds | overall.json_valid_rate | hard.chronology_phase_accuracy | real_runtime.runtime_fallback_rate | overall.case_strict_success_rate |
| --- | ---: | ---: | ---: | ---: | ---: |
| dataset_v7_orpo_iter2 | 1 | 0.9504 ± 0.0000 | 0.0000 ± 0.0000 | 0.6094 ± 0.0000 | 0.0840 ± 0.0000 |
| dataset_v8_plan_orpo_iter1 | 1 | 0.9504 ± 0.0000 | 0.0449 ± 0.0000 | 0.0312 ± 0.0000 | 0.1412 ± 0.0000 |
| dataset_v9_3_event_sft | 1 | 1.0000 ± 0.0000 | 0.9888 ± 0.0000 | 0.0000 ± 0.0000 | 0.9962 ± 0.0000 |

## Pairwise Results

| candidate | baseline | seed | wins_candidate | wins_baseline | ties | sign_test_pvalue | delta_pp.json_valid_rate | delta_pp.exact_marked_object_id_accuracy | delta_pp.chronology_phase_accuracy |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| dataset_v8_plan_orpo_iter1 | dataset_v7_orpo_iter2 | 42 | 149 | 84 | 29 | 0.000025 | 0.000 | 0.000 | 5.725 |
| dataset_v9_3_event_sft | dataset_v8_plan_orpo_iter1 | 42 | 224 | 0 | 38 | 0.000000 | 4.962 | 1.190 | 85.496 |
| dataset_v9_3_event_sft | dataset_v7_orpo_iter2 | 42 | 240 | 0 | 22 | 0.000000 | 4.962 | 1.190 | 91.221 |

## Slice Summary

| model_id | seed | slice | json_valid_rate | schema_valid_rate | ordinal_actor_binding_accuracy | target_resolution_accuracy | chronology_phase_accuracy | action_recall | runtime_fallback_rate | case_strict_success_rate |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| dataset_v7_orpo_iter2 | 42 | model_only | 0.9504 | 0.9504 | 0.9340 | 0.1128 | 0.0840 | 0.1066 | 0.9008 | 0.0840 |
| dataset_v7_orpo_iter2 | 42 | end_to_end | 0.5916 | 0.5916 | 0.5260 | 0.1282 | 0.0344 | 0.1206 | 0.5076 | 0.0344 |
| dataset_v8_plan_orpo_iter1 | 42 | model_only | 0.9504 | 0.9504 | 0.8385 | 0.4803 | 0.1412 | 0.4741 | 0.3931 | 0.1412 |
| dataset_v8_plan_orpo_iter1 | 42 | end_to_end | 0.9504 | 0.9504 | 0.8385 | 0.4803 | 0.1412 | 0.4741 | 0.3931 | 0.1412 |
| dataset_v9_3_event_sft | 42 | model_only | 1.0000 | 1.0000 | 1.0000 | 0.9983 | 0.9962 | 0.9986 | 0.0000 | 0.9962 |
| dataset_v9_3_event_sft | 42 | end_to_end | 1.0000 | 1.0000 | 1.0000 | 0.9983 | 0.9962 | 0.9986 | 0.0000 | 0.9962 |

## V8 Local Plan Slice Summary

| model_id | seed | slice | plan_parse_rate | plan_reference_binding_accuracy | plan_beat_integrity_accuracy |
| --- | ---: | --- | ---: | ---: | ---: |
| dataset_v8_plan_orpo_iter1 | 42 | local_plan_raw | 0.9580 | 0.7595 | 0.2786 |
| dataset_v9_3_event_sft | 42 | local_plan_raw | 0.0000 | 0.0000 | 0.0000 |

## Slice Reason Codes

| model_id | seed | reason_code | count |
| --- | ---: | --- | ---: |
| dataset_v7_orpo_iter2 | 42 | json_parse_fail | 13 |
| dataset_v7_orpo_iter2 | 42 | legacy_beat_repaired | 223 |
| dataset_v7_orpo_iter2 | 42 | schema_fail | 94 |
| dataset_v8_plan_orpo_iter1 | 42 | v8.invalid_spatial_relation_skipped | 11 |
| dataset_v8_plan_orpo_iter1 | 42 | v8.targetless_action_downgraded | 58 |

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
