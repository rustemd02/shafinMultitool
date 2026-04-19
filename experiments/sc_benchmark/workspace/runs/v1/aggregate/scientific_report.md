# Scientific Benchmark Report

## Setup
- config: `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/benchmark_config.v1.json`
- eval_bundle_dir: `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/eval_bundle_v1`
- total_scored_runs: 0
- total_pairwise_compares: 0

## Model Summary (mean ± std across seeds)

| model_id | seeds | overall.json_valid_rate | hard.chronology_phase_accuracy | real_runtime.runtime_fallback_rate | overall.case_strict_success_rate |
| --- | ---: | ---: | ---: | ---: | ---: |

## Pairwise Results

| candidate | baseline | seed | wins_candidate | wins_baseline | ties | sign_test_pvalue | delta_pp.json_valid_rate | delta_pp.exact_marked_object_id_accuracy | delta_pp.chronology_phase_accuracy |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |

## Artifacts
- `runs_scored.csv`
- `model_summary.csv`
- `pairwise_compare.csv`
- `reports/` (raw eval harness outputs)
- `compares/` (A/B per-seed outputs)
