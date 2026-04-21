# Scientific Benchmark Report

## Setup
- config: `/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter2/sgv7_eval_pack_seed42/benchmark_config.local.with_repo_bundle.seed42.json`
- eval_bundle_dir: `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/eval_bundle_v1`
- total_scored_runs: 4
- total_pairwise_compares: 6

## Model Summary (mean ± std across seeds)

| model_id | seeds | overall.json_valid_rate | hard.chronology_phase_accuracy | real_runtime.runtime_fallback_rate | overall.case_strict_success_rate |
| --- | ---: | ---: | ---: | ---: | ---: |
| base_qwen3_1_7b | 1 | 0.4275 ± 0.0000 | 0.0000 ± 0.0000 | 1.0000 ± 0.0000 | 0.0000 ± 0.0000 |
| dataset_v7 | 1 | 0.9885 ± 0.0000 | 0.0000 ± 0.0000 | 0.8906 ± 0.0000 | 0.0229 ± 0.0000 |
| dataset_v7_orpo_iter1 | 1 | 0.9580 ± 0.0000 | 0.0000 ± 0.0000 | 0.8750 ± 0.0000 | 0.0267 ± 0.0000 |
| dataset_v7_orpo_iter2 | 1 | 0.9504 ± 0.0000 | 0.0000 ± 0.0000 | 0.8281 ± 0.0000 | 0.0382 ± 0.0000 |

## Pairwise Results

| candidate | baseline | seed | wins_candidate | wins_baseline | ties | sign_test_pvalue | delta_pp.json_valid_rate | delta_pp.exact_marked_object_id_accuracy | delta_pp.chronology_phase_accuracy |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| dataset_v7 | base_qwen3_1_7b | 42 | 258 | 1 | 3 | 0.000000 | 56.107 | 100.000 | 4.580 |
| dataset_v7_orpo_iter1 | base_qwen3_1_7b | 42 | 251 | 5 | 6 | 0.000000 | 53.053 | 100.000 | 7.634 |
| dataset_v7_orpo_iter2 | base_qwen3_1_7b | 42 | 249 | 5 | 8 | 0.000000 | 52.290 | 98.810 | 8.397 |
| dataset_v7_orpo_iter1 | dataset_v7 | 42 | 10 | 10 | 242 | 1.000000 | -3.053 | 0.000 | 3.053 |
| dataset_v7_orpo_iter2 | dataset_v7 | 42 | 16 | 13 | 233 | 0.711071 | -3.817 | -1.190 | 3.817 |
| dataset_v7_orpo_iter2 | dataset_v7_orpo_iter1 | 42 | 9 | 6 | 247 | 0.607239 | -0.763 | -1.190 | 0.763 |

## Slice Summary

- none

## Slice Reason Codes

- none

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
