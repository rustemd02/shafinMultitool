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
