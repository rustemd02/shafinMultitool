# Combined Eval Report: `base` vs `v6` vs `v7` vs `v7_orpo`

Date: 2026-04-20  
Owner: SGv7 benchmark workspace

## Sources

- SG v7 unified scoring (same eval bundle, `262` cases each):
  - `/tmp/sc_bench_rescore/base/set_metrics.json` (base was sanitized for malformed list items in `predicted_script`)
  - `/tmp/sc_bench_rescore/v6/set_metrics.json`
  - `/tmp/sc_bench_rescore/v7/set_metrics.json`
  - `/tmp/sc_bench_rescore/v7_orpo/set_metrics.json`
- Legacy v6 holdout scoring:
  - [legacy_v6_summary_corrected.json](/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/legacy_v6_summary_corrected.json)
  - [dataset_v6_legacy_seed42_rerun.jsonl](/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/dataset_v6_legacy_seed42_rerun.jsonl)

## SG v7 Primary Metrics (basis table)

All values are percentages (`%`). Higher is better except `runtime_fallback_rate` (lower is better).

| Model | json_valid | schema_valid | strict_success | exact_marker_id | ordinal_binding | target_resolution | chronology | action_recall | runtime_fallback |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `base` | 34.73 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 100.00 |
| `v6` | 1.53 | 1.53 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 100.00 |
| `v7` | 98.85 | 98.85 | 2.29 | 100.00 | 98.26 | 6.32 | 4.58 | 6.03 | 97.33 |
| `v7_orpo` | 96.56 | 96.18 | 2.67 | 100.00 | 95.31 | 8.89 | 6.49 | 8.42 | 95.80 |

## Addendum: `v8 hotfix` and `v9 slot-event` (seed 42, same eval bundle)

This addendum extends the original report with newer architecture iterations that are directly comparable under the same `262`-case frozen eval bundle.

Key point:
- `v8` moved from `text -> final JSON` to `plan -> compile`.
- `v9` moved further to `slot/event table -> compile`, removing plan-structure responsibility from the model.

All values are percentages (`%`). Higher is better except `runtime_fallback_rate` (lower is better).

| Model | json_valid | schema_valid | strict_success | ordinal_binding | target_resolution | chronology | action_recall | runtime_fallback |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `v7_orpo_iter2` (model_only) | 95.04 | 94.66 | 3.44 | 93.40 | 11.28 | 8.40 | 10.66 | 95.04 |
| `v8_plan_orpo_iter1` (end_to_end) | 95.04 | 56.49 | 10.31 | 83.85 | 48.03 | 14.12 | 47.41 | 71.37 |
| `v9_event_sft` (end_to_end) | 100.00 | 60.69 | 50.76 | 100.00 | 92.14 | 87.02 | 93.55 | 43.51 |

### V9 event-table metrics (raw slice)

These are **V9-specific** metrics measured on the raw `event table` output (separate from compiled `SceneScript` scoring):

| Metric | Value (%) | Notes |
|---|---:|---|
| `event_schema_valid_rate` | 100.00 | Structural validity of event table |
| `event_actor_slot_accuracy` | 96.91 | Gold-based semantic accuracy |
| `event_target_slot_accuracy` | 94.39 | Gold-based semantic accuracy |
| `event_action_type_accuracy` | 96.21 | Gold-based semantic accuracy |
| `event_beat_order_accuracy` | 96.77 | Gold-based semantic accuracy |

## Legacy v6 Metrics Aligned To SG v7 Naming

Important: numbers are not altered.  
Only metric naming is aligned where possible.

Legacy set size: `209` cases.

| SG v7-aligned label | Legacy v6 source metric | Value (%) | Notes |
|---|---|---:|---|
| `json_valid_rate` | `json_parse_rate` | 100.00 | Direct parseability proxy |
| `schema_valid_rate` | `schema_valid_rate` | 55.02 | Direct |
| `case_strict_success_rate` | `exact_match_rate` (proxy) | 0.00 | Proxy, not identical contract |
| `action_recall` | `action_count_match_rate` (proxy) | 35.41 | Count match proxy only |
| `target_resolution_accuracy` | N/A | N/A | Not measured in legacy scoring |
| `chronology_phase_accuracy` | N/A | N/A | Not measured in legacy scoring |
| `ordinal_actor_binding_accuracy` | N/A | N/A | Not measured in legacy scoring |
| `exact_marked_object_id_accuracy` | N/A | N/A | Not measured in legacy scoring |
| `runtime_fallback_rate` | N/A | N/A | Not measured in legacy scoring |

Additional legacy-only support metrics:

- `actor_count_match_rate`: `81.34%`
- `object_count_match_rate`: `25.84%`
- `beat_count_match_rate`: `34.93%`

## Human Readout By Metric

This section explains each metric in plain language and ties it to the observed values.

### 1) `json_valid` / `json_parse_rate`

What it means:
- Can the model output be parsed as JSON object at all.

What we see:
- SG v7: `base 34.73%`, `v6 1.53%`, `v7 98.85%`, `v7_orpo 96.56%`.
- Legacy v6: `v6 json_parse_rate 100%`.

Interpretation:
- Under SG v7 contract, `v6` and `base` frequently fail before semantic checks.
- Under legacy contract, `v6` can produce parseable JSON consistently.
- This is a strong sign of contract/prompt mismatch rather than pure "model intelligence".

### 2) `schema_valid`

What it means:
- Parsed JSON also satisfies schema constraints.

What we see:
- SG v7: `base 0.00%`, `v6 1.53%`, `v7 98.85%`, `v7_orpo 96.18%`.
- Legacy v6: `v6 schema_valid_rate 55.02%`.

Interpretation:
- `v7` and `v7_orpo` are production-stable on schema.
- `v6` can pass its old schema in about half cases, but collapses on SG v7 schema.

### 3) `case_strict_success`

What it means:
- Full strict pass of the scoring contract.

What we see:
- SG v7: `base 0.00%`, `v6 0.00%`, `v7 2.29%`, `v7_orpo 2.67%`.
- Legacy proxy (exact match): `v6 0.00%`.

Interpretation:
- Strict gate is intentionally very hard.
- `v7_orpo` is slightly better than `v7` on strict pass, but both are still far from high strict-completion.

### 4) `exact_marked_object_id_accuracy`

What it means:
- Correct preservation of exact marked object identity.

What we see (SG v7):
- `base 0.00%`, `v6 0.00%`, `v7 100.00%`, `v7_orpo 100.00%`.

Interpretation:
- Marker identity handling is fully solved in `v7` generation family.
- Legacy `v6` does not satisfy this modern requirement.

### 5) `ordinal_actor_binding_accuracy`

What it means:
- Correct binding for ordinal actor references ("first/second/third actor" semantics).

What we see (SG v7):
- `base 0.00%`, `v6 0.00%`, `v7 98.26%`, `v7_orpo 95.31%`.

Interpretation:
- Both `v7` variants are strong; ORPO step slightly reduced this metric.

### 6) `target_resolution_accuracy`

What it means:
- Correct resolution of action targets in scene graph.

What we see (SG v7):
- `base 0.00%`, `v6 0.00%`, `v7 6.32%`, `v7_orpo 8.89%`.

Interpretation:
- This is still a weak area overall.
- ORPO improves it, but absolute level remains low.

### 7) `chronology_phase_accuracy`

What it means:
- Correct phase ordering across multi-step/beat chronology.

What we see (SG v7):
- `base 0.00%`, `v6 0.00%`, `v7 4.58%`, `v7_orpo 6.49%`.

Interpretation:
- Same pattern as target resolution: ORPO helps, but this remains a bottleneck.

### 8) `action_recall`

What it means:
- Fraction of expected actions recovered in prediction.

What we see:
- SG v7: `base 0.00%`, `v6 0.00%`, `v7 6.03%`, `v7_orpo 8.42%`.
- Legacy proxy (`action_count_match_rate`): `v6 35.41%` (count-based, not semantic recall).

Interpretation:
- ORPO improves action recovery on SG v7 benchmark.
- Legacy action count match is not directly equivalent to SG v7 action recall.

### 9) `runtime_fallback_rate`

What it means:
- Fraction of cases where runtime falls back (lower is better).

What we see (SG v7):
- `base 100.00%`, `v6 100.00%`, `v7 97.33%`, `v7_orpo 95.80%`.

Interpretation:
- `v7_orpo` reduces fallback usage relative to `v7`.
- Despite high parse/schema rates, runtime semantic gates still reject many outputs.

## `v6` vs `v7` On Their Own Contracts

This is the correct "fairness" view:

- `v6` on legacy contract is not dead:
  - parseability is high (`100%`);
  - schema is moderate (`55.02%`);
  - actor count alignment is high (`81.34%`).
- `v7` on SG v7 contract is far stronger on modern requirements:
  - near-perfect parse+schema (`~99%`);
  - perfect marker identity (`100%`);
  - very high ordinal binding (`98.26%`).

Practical conclusion:
- For legacy tasks, `v6` is still serviceable.
- For current production SG v7 pipeline, `v7`/`v7_orpo` are the only viable choices.
- `v7_orpo` is a tradeoff update over `v7`: better runtime semantics (`target`, `chronology`, `action_recall`, `fallback`), slightly worse parse stability and ordinal binding.

## Iter2 Full Run (`benchmark_results_seed42`)

Run directory:
- [benchmark_results_seed42](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter2/benchmark_results_seed42)

### Setup and scope

From [benchmark_manifest.json](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter2/benchmark_results_seed42/aggregate/benchmark_manifest.json):

- `mode`: `aggregate-only`
- `eval_bundle_dir`: `experiments/sc_benchmark/workspace/eval_bundle_v1`
- `eval_seed`: `20260419`
- `total_runs`: `4`
- `total_pairwise_rows`: `6`
- `slice_recompute_enabled`: `true`
- `slice_gate_baseline_model_id`: `dataset_v7_orpo_iter1`

Compared models in this run:
- `base_qwen3_1_7b`
- `dataset_v7`
- `dataset_v7_orpo_iter1`
- `dataset_v7_orpo_iter2`

### Model metrics (seed 42, same contract)

Values are percentages (`%`), extracted from `reports/*/seed_42/set_metrics.json`.

| Model | json_valid | schema_valid | strict_success | exact_marker_id | ordinal_binding | target_resolution | chronology | action_recall | runtime_fallback |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `base_qwen3_1_7b` | 42.75 | 0.38 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 100.00 |
| `dataset_v7` | 98.85 | 98.85 | 2.29 | 100.00 | 98.26 | 6.32 | 4.58 | 6.03 | 97.33 |
| `dataset_v7_orpo_iter1` | 95.80 | 95.80 | 2.67 | 100.00 | 94.10 | 9.57 | 7.63 | 8.84 | 96.56 |
| `dataset_v7_orpo_iter2` | 95.04 | 94.66 | 3.82 | 98.81 | 93.40 | 11.62 | 8.40 | 11.08 | 94.66 |

Primary observations:
- `iter2` improves semantic-runtime block vs `iter1`:
  - `strict_success`: `2.67% -> 3.82%`
  - `target_resolution`: `9.57% -> 11.62%`
  - `chronology`: `7.63% -> 8.40%`
  - `action_recall`: `8.84% -> 11.08%`
  - `runtime_fallback`: `96.56% -> 94.66%` (lower is better)
- `iter2` regresses parse/identity stability vs `iter1`:
  - `json_valid`: `95.80% -> 95.04%`
  - `schema_valid`: `95.80% -> 94.66%`
  - `exact_marker_id`: `100.00% -> 98.81%`
  - `ordinal_binding`: `94.10% -> 93.40%`

### Pairwise comparisons (seed 42)

From [pairwise_compare.csv](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter2/benchmark_results_seed42/aggregate/pairwise_compare.csv):

- `iter2 vs base`:
  - wins/loss/ties: `249 / 5 / 8`
  - `delta_pp.json_valid_rate`: `+52.29`
  - `delta_pp.exact_marked_object_id_accuracy`: `+98.81`
  - `delta_pp.chronology_phase_accuracy`: `+8.40`
  - `sign_test_pvalue`: `5.97e-67`
- `iter2 vs v7`:
  - wins/loss/ties: `16 / 13 / 233`
  - `delta_pp.json_valid_rate`: `-3.82`
  - `delta_pp.exact_marked_object_id_accuracy`: `-1.19`
  - `delta_pp.chronology_phase_accuracy`: `+3.82`
  - `sign_test_pvalue`: `0.711`
- `iter2 vs iter1`:
  - wins/loss/ties: `9 / 6 / 247`
  - `delta_pp.json_valid_rate`: `-0.76`
  - `delta_pp.exact_marked_object_id_accuracy`: `-1.19`
  - `delta_pp.chronology_phase_accuracy`: `+0.76`
  - `sign_test_pvalue`: `0.607`

Interpretation:
- Against `base`, `iter2` is decisively better.
- Against `v7` and `iter1`, improvements are visible in semantic-runtime metrics, but pairwise significance is weak due many ties.
- Current state is still a tradeoff profile, not a strict Pareto improvement.

### Slice-gate status

From [slice_gate_results.csv](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter2/benchmark_results_seed42/aggregate/slice_gate_results.csv):

- No model passed slice gate in this export.
- Blocking reason for all listed models: `missing_slice_metrics`.
- `model_slice_summary_by_model.csv` and `slice_reason_codes.csv` are empty.

Implication:
- This iter2 export is valid for aggregate/model and pairwise comparisons.
- Slice-level acceptance claims cannot be made from this artifact set.

## Integrity Notes

- `base` SG v7 score used a sanitized prediction file to neutralize malformed list structures in `predicted_script`; metric intent remains unchanged, but the preprocessing step should be disclosed in defense materials.
- Legacy and SG v7 tables are intentionally separated; direct cross-table comparison is informational, not statistically equivalent.
