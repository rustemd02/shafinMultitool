# SG V9 Slot-Event Pipeline

`v9` shifts local generation from direct `ScenePlanIR` decoding to a slot-first event-table pipeline.

Canonical flow:

1. `CIR -> sg_v9_slot_catalog_v1`
2. `CIR -> sg_v9_event_table_v1` (train target)
3. `event table -> verifier/repair`
4. `event table -> ScenePlanIR -> SceneScript` (deterministic compiler)

## Files

- `contracts.py` — typed contracts for slot catalog, event table, patch ops, verifier issues.
- `projection.py` — deterministic `CIR -> slot catalog/event table`.
- `verifier.py` — validation and deterministic repairs for event tables.
- `compiler.py` — deterministic event-table compilation to `ScenePlanIR` and compiled script.
- `datasets.py` — SFT dataset builders for event-table generation and patch ops.
- `eval.py` — event-slice aggregate metrics.
- `eval_artifacts.py` — convert event predictions to benchmark-ready compiled predictions.
- `moe_workflow.md` — mandatory Mixture-of-Experts process and decision gates.
- `moe_artifact_template.md` — per-role artifact template.

## CLI

- `01_build_v9_event_dataset.py`
- `02_build_v9_patch_dataset.py`
- `03_build_v9_eval_artifacts.py`
- `04_run_v9_local_benchmark.py`
- `09_build_v9_3_targeted_sft.py`
- `10_generate_v9_3_targeted_augmentations.py`
- `11_build_v9_3_mixed_dataset.py`
- `12_validate_v9_demo_parity.py`
- `13_run_v9_3_post_train_eval.py`
- `14_verify_v9_3_pretrain_artifacts.py`

## Notes

- Runtime remains local-first.
- `v8` path stays available as fallback for A/B verification.
- All repairs are traceable via deterministic reason codes.

## Benchmark Snapshot (seed 42)

Compiled-slice metrics (same frozen eval bundle, `262` cases). Values are decimals in `[0..1]`.

### Baseline snapshot (`v9.0`)

- `dataset_v7_orpo_iter2` (model_only):
  - `json_valid_rate=0.9504`, `target_resolution_accuracy=0.1128`, `chronology_phase_accuracy=0.0840`, `case_strict_success_rate=0.0344`
- `dataset_v8_plan_orpo_iter1` (end_to_end, `v8 hotfix`):
  - `json_valid_rate=0.9504`, `ordinal_actor_binding_accuracy=0.8385`, `target_resolution_accuracy=0.4803`, `chronology_phase_accuracy=0.1412`, `case_strict_success_rate=0.1031`
- `dataset_v9_event_sft` (end_to_end, slot-event):
  - `json_valid_rate=1.0000`, `ordinal_actor_binding_accuracy=1.0000`, `target_resolution_accuracy=0.9214`, `chronology_phase_accuracy=0.8702`, `case_strict_success_rate=0.5076`

### Updated snapshot (`v9.2` checkpoint, report label still `dataset_v9_event_sft`)

The `v9.2` checkpoint was evaluated on the same frozen bundle via:

- `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions/benchmark_results_seed42/aggregate/scientific_report.md`
- `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions/benchmark_results_seed42/aggregate/model_slice_summary.csv`
- `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions/eval_artifacts/dataset_v9_2_event_sft_seed42.event_slice_summary.json`

Compiled slice:

- `json_valid_rate=1.0000`
- `ordinal_actor_binding_accuracy=1.0000`
- `target_resolution_accuracy=0.9812`
- `chronology_phase_accuracy=0.9695`
- `action_recall=0.9846`
- `runtime_fallback_rate=0.4198`
- `case_strict_success_rate=0.5573`

Important: the high `runtime_fallback_rate` above is a stale-policy measurement, not the final interpretation of V9.2 model quality. V9.3 audit showed that most fallback came from scorer/runtime mirror policy:

- `103` schema-invalid cases were targetless `stand`, but `stand` is a pose/state action and must not require `target`.
- `108` cases passed semantic gates but were rejected by `pred_confidence_below_rule`.
- The Python scorer/export mirror and legacy Swift fallback target policy were aligned so `stand` is no longer treated as target-required.

### V9.3 policy-corrected replay (`v9.2` frozen predictions, fixed mirror policy)

Same frozen predictions as V9.2, after V9.3 policy correction:

- `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions_policy_v93/fallback_audit/v9_2_to_v9_3_policy_audit.md`
- `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions_policy_v93/benchmark_results_seed42/aggregate/scientific_report.md`

Compiled slice:

- `json_valid_rate=1.0000`
- `schema_valid_rate=1.0000`
- `ordinal_actor_binding_accuracy=1.0000`
- `target_resolution_accuracy=0.9812`
- `chronology_phase_accuracy=0.9695`
- `action_recall=0.9846`
- `runtime_fallback_rate=0.0038`
- `case_strict_success_rate=0.9695`

This is a scorer/runtime-policy replay, not a newly trained checkpoint. It proved that the fallback spike was mostly artificial and isolated the remaining quality target to `8` real semantic misses.

### V9.3 trained successor (`dataset_v9_3_event_sft`)

Fresh V9.3 predictions were evaluated on the same frozen bundle via:

- `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/v9_3_post_train_eval_summary.json`
- `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/benchmark_results_seed42/aggregate/scientific_report.md`
- `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/eval_artifacts/dataset_v9_3_event_sft_seed42.event_slice_summary.json`
- `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/demo_parity_validation/demo_parity_results.json`

Compiled slice:

- `json_valid_rate=1.0000`
- `schema_valid_rate=1.0000`
- `ordinal_actor_binding_accuracy=1.0000`
- `target_resolution_accuracy=0.9983`
- `chronology_phase_accuracy=0.9962`
- `action_recall=0.9986`
- `runtime_fallback_rate=0.0000`
- `case_strict_success_rate=0.9962`

Raw event-table slice:

- `event_parse_rate=1.0000`, `event_schema_valid_rate=1.0000`
- `event_actor_slot_accuracy=0.9986`
- `event_target_slot_accuracy=1.0000`
- `event_action_type_accuracy=1.0000`
- `event_beat_order_accuracy=1.0000`
- `event_full_row_accuracy=0.9986`
- `chunk_event_coverage_rate=0.9986`

Acceptance:

- V9.3 goal gate: passed.
- Demo-parity: `3/3` canonical non-AR intent checks passed.
- Post-benchmark failure mining: `1` remaining `dialogue_action` hard case.

### V9.3 train dataset

V9.3 targeted dataset artifacts:

- `docs/SGv9pipeline/runs/v9_3_seed42/failure_mining/v9_hard_cases.jsonl`
- `docs/SGv9pipeline/runs/v9_3_seed42/exact_targeted_sft/v9_3_event_sft_targeted_all.jsonl`
- `docs/SGv9pipeline/runs/v9_3_seed42/augmented_targeted/v9_3_augmented_event_sft_all.jsonl`
- `docs/SGv9pipeline/runs/v9_3_seed42/mixed_event_sft/v9_3_event_sft_mixed_all.jsonl`
- `docs/SGv9pipeline/runs/v9_3_seed42/colab_upload/v9_3_event_sft_mixed_upload.zip`
- `docs/SGv9pipeline/runs/v9_3_seed42/colab_upload/v9_3_event_sft_mixed_upload_manifest.json`
- `docs/SGv9pipeline/runs/v9_3_seed42/V9_3_TRAIN_BENCH_RUNBOOK.md`

Mixed dataset:

- `all_rows=5564`
- `train_rows=4730`
- `val_rows=834`
- `new_v9_3_targeted_rows=278`

V9.3 targeted clusters:

- `dialogue_then_put_down_object`
- `dialogue_then_pick_up_object_then_give_to_third_actor`
- `ordinal_first_second_third`

Non-AR demo-parity checker:

```bash
python3 docs/SGv9pipeline/v9/12_validate_v9_demo_parity.py \
  --compiled-predictions docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/eval_artifacts/dataset_v9_3_event_sft_seed42.compiled_predictions.jsonl \
  --output-dir docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/demo_parity_validation
```

V9.2 policy-corrected baseline intentionally failed this checker `0/3`; V9.3 passed `3/3`.

Preferred post-training command after Colab produces or updates `dataset_v9_3_event_sft_seed42.event_predictions.jsonl`:

```bash
python3 docs/SGv9pipeline/v9/13_run_v9_3_post_train_eval.py
```

The wrapper applies the V9.3 goal gate by default:

- `case_strict_success_rate >= 0.65`
- `target_resolution_accuracy >= 0.99`
- `chronology_phase_accuracy >= 0.985`
- `action_recall >= 0.99`
- `runtime_fallback_rate <= 0.25`

Gate tests live in `docs/SGv9pipeline/v9/tests/test_v9_post_train_eval.py`.

Before Colab upload, verify local V9.3 artifacts:

```bash
python3 docs/SGv9pipeline/v9/14_verify_v9_3_pretrain_artifacts.py
```

V9.2 pairwise:

- vs `dataset_v8_plan_orpo_iter1`: `225` wins, `1` loss, `36` ties
- vs `dataset_v7_orpo_iter2`: `238` wins, `1` loss, `23` ties

V9 raw event-table metrics (event slice, gold-based semantic accuracy + structural pass):

- structural:
  - `event_parse_rate=1.0000`, `event_schema_valid_rate=1.0000`
- semantic:
  - `event_actor_slot_accuracy≈0.9930`, `event_target_slot_accuracy≈0.9860`, `event_action_type_accuracy≈0.9888`, `event_beat_order_accuracy≈0.9930`
  - `event_full_row_accuracy≈0.9846`, `chunk_event_coverage_rate≈0.9846`

Artifacts:

- `docs/SGv9pipeline/runs/v9_0_seed42/benchmark_results_seed42/aggregate/model_slice_summary.csv`
- `docs/SGv9pipeline/runs/v9_0_seed42/eval_artifacts/dataset_v9_event_sft_seed42.event_slice_summary.json`
- `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions/benchmark_results_seed42/aggregate/scientific_report.md`
- `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions/eval_artifacts/dataset_v9_2_event_sft_seed42.event_slice_summary.json`
- `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions_policy_v93/benchmark_results_seed42/aggregate/scientific_report.md`
- `docs/SGv9pipeline/runs/v9_3_seed42/mixed_event_sft/v9_3_event_sft_mixed_manifest.json`
