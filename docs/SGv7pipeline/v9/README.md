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

## Notes

- Runtime remains local-first.
- `v8` path stays available as fallback for A/B verification.
- All repairs are traceable via deterministic reason codes.

## Benchmark Snapshot (seed 42)

Compiled-slice metrics (same frozen eval bundle, `262` cases). Values are decimals in `[0..1]`:

- `dataset_v7_orpo_iter2` (model_only):
  - `json_valid_rate=0.9504`, `target_resolution_accuracy=0.1128`, `chronology_phase_accuracy=0.0840`, `case_strict_success_rate=0.0344`
- `dataset_v8_plan_orpo_iter1` (end_to_end, `v8 hotfix`):
  - `json_valid_rate=0.9504`, `ordinal_actor_binding_accuracy=0.8385`, `target_resolution_accuracy=0.4803`, `chronology_phase_accuracy=0.1412`, `case_strict_success_rate=0.1031`
- `dataset_v9_event_sft` (end_to_end, slot-event):
  - `json_valid_rate=1.0000`, `ordinal_actor_binding_accuracy=1.0000`, `target_resolution_accuracy=0.9214`, `chronology_phase_accuracy=0.8702`, `case_strict_success_rate=0.5076`

V9 raw event-table metrics (event slice, gold-based semantic accuracy + structural pass):

- structural:
  - `event_parse_rate=1.0000`, `event_schema_valid_rate=1.0000`
- semantic:
  - `event_actor_slot_accuracy≈0.9691`, `event_target_slot_accuracy≈0.9439`, `event_action_type_accuracy≈0.9621`, `event_beat_order_accuracy≈0.9677`

Artifacts:

- `docs/SGv7pipeline/runs/v9_0_seed42/benchmark_results_seed42/aggregate/model_slice_summary.csv`
- `docs/SGv7pipeline/runs/v9_0_seed42/eval_artifacts/dataset_v9_event_sft_seed42.event_slice_summary.json`
