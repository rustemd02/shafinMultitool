# Track 8 Training Harness

Этот пакет содержит исполнимые артефакты для `Prompt 8 / implement`:
- materialization phase views для `phase1/phase2/phase3/phase4`
- checkpoint compare и promotion artifacts
- reproducible experiment registry

## CLI

### 1. Build phase view

```bash
python3 docs/SGv7pipeline/training/08_build_phase_view.py \
  --phase phase3 \
  --sft-train-jsonl /path/to/sft_train.jsonl \
  --split-manifest-json /path/to/split_manifest.json \
  --output-dir /path/to/out \
  --seed 20260414
```

### 2. Compare checkpoints

```bash
python3 docs/SGv7pipeline/training/09_compare_checkpoints.py \
  --phase phase3 \
  --checkpoints-jsonl /path/to/checkpoints.jsonl \
  --reference-checkpoint-id phase2_winner \
  --output-dir /path/to/out \
  --seed 20260414
```

### 3. Register reproducible experiment note

```bash
python3 docs/SGv7pipeline/training/10_register_experiment.py \
  --experiment-id exp_phase3_001 \
  --phase phase3 \
  --config-path docs/SGv7pipeline/training/phase_configs/phase3_hard.json \
  --input-artifact /path/to/out/checkpoint_table.json \
  --input-artifact /path/to/out/bucket_deltas.json \
  --output-dir /path/to/registry
```

## Expected compare outputs

- `checkpoint_table.json`
- `checkpoint_compare.md`
- `bucket_deltas.json`
- `promotion_decision.md`
- `preference_eval.json` (для `phase4`)
