# Camera intent pilot (variant A feasibility)

Research-only pilot for the intent-source decision (`docs/cameraanalysis/35-intent-source-proposal.md`).
Everything here is `research_only=true, human_gold=false`; the model must not be
bundled into the app or promoted to production.

## Contents

- `build_intent_dataset.py` — parses an INTENTDUMP full-replay dump
  (`evidence-m2/intent-features-full-dump-20260912.txt`) + the curated labels
  into a deterministic stratified train/test dataset (seed 20260912,
  122/52 records).
- `train_intent_pilot.py` — softmax regression (numpy only), hyperparameters
  selected on a validation split carved from train (lr 0.05, iters 800);
  holdout metrics + 5 resplit variance runs; saves model + metrics.

## Reproduce

```sh
python3 build_intent_dataset.py \
  --dump ../../../docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m2/intent-features-full-dump-20260912.txt \
  --labels ../../../shafinMultitool/Resources/DeviceBenchmark/camera_device_benchmark_pack_v1/camera_full_labels.jsonl \
  --out-dir dataset
python3 train_intent_pilot.py --dataset-dir dataset --out-dir run
```

## Result (canonical run)

- 3-class test accuracy **0.673** (majority baseline 0.466); resplit variance
  mean 0.676.
- Per class: good F1 0.702, bad F1 0.698, mixed F1 0.0 (support 4 — not
  learnable at this scale).
- Confirmed by the separability study: `aesthetic_score` is the only strong
  feature (AUC 0.846 good-vs-bad), but the lightweight estimator
  systematically under-rates intentional low-key frames — a single-threshold
  gate yields 18 false keeps.

## Interpretation

The current low-level feature set carries real but insufficient signal for a
deterministic intent gate (variant A-lite is excluded). Variant A requires a
qualified model trained on an intent-labelled corpus larger than this 174-record
pack; this pilot is the reproducible baseline that future feature/model work
must beat.
