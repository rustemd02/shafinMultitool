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
| live smoke v8 | Real GGUF v8 live smoke: `passed=0/12`, runtime about 808 seconds, model loaded. | `diploma.md` entry 2026-04-26 | partially_verified; attach xcresult before final defense |
| live smoke v9 | V9 runtime hardening entry reports `SceneV8PipelineTests/testLiveLocalModelDatasetSampledCases()` `1/1 passed`, no failures. | `diploma.md` entry 2026-05-04 | partially_verified; attach xcresult before final defense |

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
| “Hybrid Camera Analysis neural evidence improves quality.” | Current hybrid smoke is `mobile_blocked`; deterministic v1 is verified. | needs_source |
| “Chunk-native continuity is quantitatively solved.” | V9 event summary has null cross-chunk continuity metrics. | needs_source |
