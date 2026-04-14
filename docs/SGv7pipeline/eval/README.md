# Track 9 Eval Harness

Этот пакет содержит исполнимые артефакты для `Prompt 9 / implement`:
- offline `score` run по frozen eval bundle
- release-gate summary
- bucket reports
- paired `compare` artifacts для A/B

## CLI

### 1. Score checkpoint

```bash
python3 docs/SGv7pipeline/eval/07_eval_local_model.py \
  --mode score \
  --eval-bundle-dir /path/to/eval_bundle \
  --checkpoint-id phase3_candidate_004 \
  --output-dir /path/to/out \
  --seed 20260414
```

### 2. Compare candidate vs baseline

```bash
python3 docs/SGv7pipeline/eval/07_eval_local_model.py \
  --mode compare \
  --candidate-report /path/to/candidate_report \
  --baseline-report /path/to/baseline_report \
  --output-dir /path/to/out
```

## Expected outputs

- `raw_outputs.jsonl`
- `case_results.jsonl`
- `set_metrics.json`
- `bucket_metrics.json`
- `release_gate_summary.json`
- `eval_summary.md`
- `run_manifest.json`
- `ab_summary.json` (если есть baseline/candidate compare)
- `ab_report.md` (если есть baseline/candidate compare)
