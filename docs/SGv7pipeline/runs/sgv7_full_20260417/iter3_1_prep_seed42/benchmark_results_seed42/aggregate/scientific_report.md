# Scientific Benchmark Report

## Setup
- config: `/private/tmp/iter3_prep_benchmark_config.seed42.json`
- eval_bundle_dir: `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/eval_bundle_v1`
- total_scored_runs: 3
- total_pairwise_compares: 3

## Model Summary (mean ± std across seeds)

| model_id | seeds | overall.json_valid_rate | hard.chronology_phase_accuracy | real_runtime.runtime_fallback_rate | overall.case_strict_success_rate |
| --- | ---: | ---: | ---: | ---: | ---: |
| dataset_v7 | 1 | 0.9809 ± 0.0000 | 0.0000 ± 0.0000 | 0.6719 ± 0.0000 | 0.0191 ± 0.0000 |
| dataset_v7_orpo_iter1 | 1 | 0.9656 ± 0.0000 | 0.0000 ± 0.0000 | 0.6406 ± 0.0000 | 0.0267 ± 0.0000 |
| dataset_v7_orpo_iter2 | 1 | 0.9504 ± 0.0000 | 0.0000 ± 0.0000 | 0.6094 ± 0.0000 | 0.0344 ± 0.0000 |

## Pairwise Results

| candidate | baseline | seed | wins_candidate | wins_baseline | ties | sign_test_pvalue | delta_pp.json_valid_rate | delta_pp.exact_marked_object_id_accuracy | delta_pp.chronology_phase_accuracy |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| dataset_v7_orpo_iter1 | dataset_v7 | 42 | 19 | 7 | 236 | 0.028959 | -1.527 | 0.000 | 2.672 |
| dataset_v7_orpo_iter2 | dataset_v7 | 42 | 31 | 14 | 217 | 0.016094 | -3.053 | -1.190 | 3.817 |
| dataset_v7_orpo_iter2 | dataset_v7_orpo_iter1 | 42 | 18 | 13 | 231 | 0.473130 | -1.527 | -1.190 | 1.145 |

## Slice Summary

| model_id | seed | slice | json_valid_rate | schema_valid_rate | ordinal_actor_binding_accuracy | target_resolution_accuracy | chronology_phase_accuracy | action_recall | runtime_fallback_rate | case_strict_success_rate |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| dataset_v7 | 42 | model_only | 0.9809 | 0.9809 | 0.9722 | 0.0564 | 0.0420 | 0.0533 | 0.9771 | 0.0191 |
| dataset_v7 | 42 | end_to_end | 0.6221 | 0.6221 | 0.5486 | 0.1265 | 0.0229 | 0.1108 | 0.8664 | 0.0191 |
| dataset_v7_orpo_iter1 | 42 | model_only | 0.9656 | 0.9618 | 0.9514 | 0.0940 | 0.0725 | 0.0884 | 0.9618 | 0.0267 |
| dataset_v7_orpo_iter1 | 42 | end_to_end | 0.6145 | 0.6145 | 0.5503 | 0.1350 | 0.0267 | 0.1220 | 0.8511 | 0.0267 |
| dataset_v7_orpo_iter2 | 42 | model_only | 0.9504 | 0.9466 | 0.9340 | 0.1128 | 0.0840 | 0.1066 | 0.9504 | 0.0344 |
| dataset_v7_orpo_iter2 | 42 | end_to_end | 0.5916 | 0.5916 | 0.5260 | 0.1282 | 0.0344 | 0.1206 | 0.8550 | 0.0344 |

## Slice Reason Codes

| model_id | seed | reason_code | count |
| --- | ---: | --- | ---: |
| dataset_v7 | 42 | json_parse_fail | 5 |
| dataset_v7 | 42 | legacy_beat_repaired | 245 |
| dataset_v7 | 42 | schema_fail | 94 |
| dataset_v7_orpo_iter1 | 42 | json_parse_fail | 9 |
| dataset_v7_orpo_iter1 | 42 | legacy_beat_repaired | 231 |
| dataset_v7_orpo_iter1 | 42 | schema_fail | 92 |
| dataset_v7_orpo_iter2 | 42 | json_parse_fail | 13 |
| dataset_v7_orpo_iter2 | 42 | legacy_beat_repaired | 223 |
| dataset_v7_orpo_iter2 | 42 | schema_fail | 94 |

## Artifacts
- `runs_scored.csv`
- `model_summary.csv`
- `pairwise_compare.csv`
- `model_slice_summary.csv`
- `model_slice_summary_by_model.csv`
- `slice_reason_codes.csv`
- `slice_gate_results.csv`
- `slice_gate_winner.json` (when at least one candidate passes)
- `reports/` (raw eval harness outputs)
- `compares/` (A/B per-seed outputs)
