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

### 4. Build iter3 curated corpora

```bash
python3 docs/SGv7pipeline/training/11_build_iter3_corpus.py \
  --eval-cases-jsonl experiments/sc_benchmark/workspace/eval_bundle_v1/eval_cases.jsonl \
  --cir-jsonl docs/SGv7pipeline/runs/sgv7_full_20260417/final/cir_merged.jsonl \
  --v7-case-results-jsonl /path/to/reports/dataset_v7/seed_42/case_results.jsonl \
  --iter1-case-results-jsonl /path/to/reports/dataset_v7_orpo_iter1/seed_42/case_results.jsonl \
  --iter2-case-results-jsonl /path/to/reports/dataset_v7_orpo_iter2/seed_42/case_results.jsonl \
  --v7-predictions-jsonl /path/to/predictions_real_v1/dataset_v7_seed42.jsonl \
  --iter1-predictions-jsonl /path/to/predictions_real_v1/dataset_v7_orpo_iter1_seed42.jsonl \
  --iter2-predictions-jsonl /path/to/predictions_real_v1/dataset_v7_orpo_iter2_seed42.jsonl \
  --iter2-vs-iter1-paired-jsonl /path/to/compares/dataset_v7_orpo_iter2_vs_dataset_v7_orpo_iter1/seed_42/paired_case_results.jsonl \
  --iter2-vs-v7-paired-jsonl /path/to/compares/dataset_v7_orpo_iter2_vs_dataset_v7/seed_42/paired_case_results.jsonl \
  --delta-sft-max-family-share 0.50 \
  --output-dir /path/to/iter3_corpus \
  --seed 20260421
```

Artifacts:
- `iter3_delta_sft.jsonl`
- `iter3_delta_sft_train.jsonl`
- `iter3_delta_sft_val.jsonl`
- `iter3_preference.jsonl`
- `iter3_preference_train.jsonl`
- `iter3_preference_val.jsonl`
- `iter3_manual_review_samples.json`
- `iter3_manifest.json`

### 5. Evaluate iter3 release gate

```bash
python3 docs/SGv7pipeline/training/12_evaluate_iter3_release_gate.py \
  --runs-scored-csv /path/to/aggregate/runs_scored.csv \
  --model-slice-summary-csv /path/to/aggregate/model_slice_summary.csv \
  --iter3-manifest-json /path/to/iter3_corpus/iter3_manifest.json \
  --candidate-model-only-case-results-jsonl /path/to/aggregate/slice_case_results/dataset_v7_orpo_iter3/seed_42/model_only_case_results.jsonl \
  --baseline-model-only-case-results-jsonl /path/to/aggregate/slice_case_results/dataset_v7_orpo_iter2/seed_42/model_only_case_results.jsonl \
  --candidate-model-id dataset_v7_orpo_iter3 \
  --baseline-model-id dataset_v7_orpo_iter2 \
  --seed 42 \
  --output-dir /path/to/iter3_gate
```

If manual review is already complete, add:

```bash
  --manual-review-json /path/to/manual_review_pass.json
```

## Expected compare outputs

- `checkpoint_table.json`
- `checkpoint_compare.md`
- `bucket_deltas.json`
- `promotion_decision.md`
- `preference_eval.json` (для `phase4`)

## Iter3 notes

- iter3 corpora are intentionally built on top of `dataset_v7` supervision, not on top of `iter1/iter2` adapters.
- iter3 corpus build is transfer-first: `chosen` can come only from `model_only_predicted_script`; dual-slice prediction exports are required and legacy `predicted_script` fallback is intentionally rejected.
- pairwise compare artifacts are required inputs for iter3 selection; disagreement mining is not considered valid without them.
- pairwise confirmation for `iter2` is semantic-aware: `winner=candidate` is not enough by itself; iter2 must also show raw case-level semantic lift without integrity regressions.
- `delta-SFT` now has its own family-cap (`--delta-sft-max-family-share`) in addition to family floors, so SFT hardening is balanced independently of phase4 preference balancing.
- iter3 release gate is also raw-first for targeted families: use the exported `aggregate/slice_case_results/.../model_only_case_results.jsonl` files, not repaired `end_to_end` case summaries.
- For final benchmark export, always use prediction generation with `--report-slice both`; otherwise slice reports stay incomplete and the run should not be treated as final.
- Optional phase-view balancing for iter3 preference data can use [`phase4_preference_iter3.json`](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/phase_configs/phase4_preference_iter3.json).
