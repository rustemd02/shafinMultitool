# V1 Chunk-Native Scene Bundle Pipeline

This package contains the research/runtime sidecars for the `v1` chunk-native scene bundle architecture.

Implemented pieces:
- `contracts.py`: typed contracts for `sg_script_document_v1`, `sg_scene_chunk_draft_v1`, `sg_scene_chunk_v1`, `sg_scene_bundle_plan_v1`
- `datasets.py`: builders for
  - `macro_scene_builder`
  - `chunk_anchor_builder`
  - `entity_registry_builder`
  - `chunk_patch_builder`
  - `chunk_preference_builder`
- `eval_artifacts.py`: `stitch_eval_artifacts_builder` for `chunk_raw`, `scene_stitched`, `bundle_compiled`
- CLI helpers:
  - `01_build_v1_chunk_datasets.py`
  - `02_build_v1_chunk_preference_dataset.py`
  - `03_build_v1_eval_artifacts.py`
  - `04_run_v1_local_benchmark.py`

Example:

```bash
python3 /Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/v1/01_build_v1_chunk_datasets.py \
  --documents-jsonl /path/to/exported_document_states.jsonl \
  --output-dir /path/to/v1_train_pack \
  --val-fraction 0.10 \
  --seed 42
```

```bash
python3 /Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/v1/04_run_v1_local_benchmark.py \
  --run-root /Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/v1_0_seed42 \
  --prediction-jsonl /path/to/v1_bundle_predictions.jsonl \
  --model-id dataset_v1_bundle
```

