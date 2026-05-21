# V9.3 Train + Benchmark Runbook

## 0. What Changed

V9.3 is not a blind retrain. The fallback audit showed that most V9.2 fallback was artificial:

- `stand` was incorrectly treated as target-required.
- `pred_confidence_below_rule` rejected compact but semantically correct V9 outputs.
- The Python scorer/export mirror and legacy Swift fallback target policy were aligned so `stand` is not a target-required action.

After the policy fix, the same frozen V9.2 predictions score:

| Metric | Value |
|---|---:|
| `schema_valid_rate` | `1.0000` |
| `runtime_fallback_rate` | `0.0038` |
| `case_strict_success_rate` | `0.9695` |
| `target_resolution_accuracy` | `0.9812` |
| `chronology_phase_accuracy` | `0.9695` |
| `action_recall` | `0.9846` |

Remaining V9.3 target is now narrow: improve the 8 real semantic misses, mostly:

- dialogue collapsed with `put_down`;
- three-actor ordinal cases where second actor should `look_at` first and third should `stand`;
- dialogue -> `pick_up` -> `give` to third actor.

## 1. Local Artifacts

Main upload zip:

```bash
docs/SGv9pipeline/runs/v9_3_seed42/colab_upload/v9_3_event_sft_mixed_upload.zip
```

Upload zip manifest/checksum:

```bash
docs/SGv9pipeline/runs/v9_3_seed42/colab_upload/v9_3_event_sft_mixed_upload_manifest.json
```

Expected SHA-256:

```text
c57e83c839e3ce84a5963e91a141801ab0506f7c00d3b856e5732699e617b297
```

Before uploading to Colab, run the local pretrain verifier:

```bash
python3 docs/SGv9pipeline/v9/14_verify_v9_3_pretrain_artifacts.py
```

Expected result: `"pass": true`.

Mixed dataset:

```bash
docs/SGv9pipeline/runs/v9_3_seed42/mixed_event_sft/v9_3_event_sft_mixed_all.jsonl
docs/SGv9pipeline/runs/v9_3_seed42/mixed_event_sft/v9_3_event_sft_mixed_train.jsonl
docs/SGv9pipeline/runs/v9_3_seed42/mixed_event_sft/v9_3_event_sft_mixed_val.jsonl
docs/SGv9pipeline/runs/v9_3_seed42/mixed_event_sft/v9_3_event_sft_mixed_manifest.json
```

Dataset size:

| Split | Rows |
|---|---:|
| all | `5564` |
| train | `4730` |
| val | `834` |
| new V9.3 targeted | `278` |

## 2. Colab Training Changes

Upload this file to Colab or Drive:

```bash
v9_3_event_sft_mixed_upload.zip
```

In notebook, change only the V9.3 input/output names. Keep the eval bundle the same, because frozen eval cases must not change between V9.2 and V9.3.

```python
from pathlib import Path

V9_ROOT = Path("/content/drive/MyDrive/sgv9_eval_runs")
event_zip = Path("/content/drive/MyDrive/v9_3_event_sft_mixed_upload.zip")
eval_zip = Path("/content/drive/MyDrive/v9_eval_bundle_v1_upload.zip")

EVENT_DIR = V9_ROOT / "mixed_event_sft"
ADAPTER_DIR = V9_ROOT / "adapters" / "sgv9_3_qwen3_event_sft_lora"
EXPORT_DIR = V9_ROOT / "sgv9_3_eval_export_seed42"
ZIP_PATH = EXPORT_DIR / "sgv9_3_event_eval_pack_seed42.zip"
```

Train files:

```python
train_raw = read_jsonl(EVENT_DIR / "v9_3_event_sft_mixed_train.jsonl")
val_raw = read_jsonl(EVENT_DIR / "v9_3_event_sft_mixed_val.jsonl")
```

Prediction output should be named:

```bash
dataset_v9_3_event_sft_seed42.event_predictions.jsonl
```

## 3. Benchmark Command

After Colab produces `dataset_v9_3_event_sft_seed42.event_predictions.jsonl`, place it here:

```bash
experiments/sc_benchmark/dataset_v9_3_event_sft_seed42.event_predictions.jsonl
```

Preferred one-command post-train evaluation:

```bash
python3 docs/SGv9pipeline/v9/13_run_v9_3_post_train_eval.py
```

This wrapper runs:

- benchmark on the frozen eval bundle;
- post-benchmark failure mining;
- non-AR demo-parity validation.
- acceptance gate for the V9.3 goal metrics.

It writes:

```bash
docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/v9_3_post_train_eval_summary.json
```

Default wrapper thresholds:

| Metric | Threshold |
|---|---:|
| `case_strict_success_rate` | `>= 0.65` |
| `target_resolution_accuracy` | `>= 0.99` |
| `chronology_phase_accuracy` | `>= 0.985` |
| `action_recall` | `>= 0.99` |
| `runtime_fallback_rate` | `<= 0.25` |

The wrapper exits non-zero if any threshold fails or if demo-parity fails.
The gate behavior is covered by `docs/SGv9pipeline/v9/tests/test_v9_post_train_eval.py`.

Manual benchmark command, if you want to run steps separately:

```bash
PYTHONPATH="$PWD/docs/SGv7pipeline:$PWD/docs/SGv8pipeline" \
python3 docs/SGv9pipeline/v9/04_run_v9_local_benchmark.py \
  --run-root docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions \
  --event-predictions-jsonl experiments/sc_benchmark/dataset_v9_3_event_sft_seed42.event_predictions.jsonl \
  --model-id dataset_v9_3_event_sft \
  --model-name "V9.3 slot-event SFT"
```

If the runner asks for V8 baseline artifacts, copy the frozen baseline:

```bash
mkdir -p docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/eval_artifacts
cp \
  docs/SGv9pipeline/runs/v9_0_seed42/eval_artifacts/dataset_v8_plan_orpo_iter1_seed42.compiled_predictions.jsonl \
  docs/SGv9pipeline/runs/v9_0_seed42/eval_artifacts/dataset_v8_plan_orpo_iter1_seed42.plan_case_results.jsonl \
  docs/SGv9pipeline/runs/v9_0_seed42/eval_artifacts/dataset_v8_plan_orpo_iter1_seed42.plan_case_results.manifest.json \
  docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/eval_artifacts/
```

Then rerun the benchmark command.

## 4. Acceptance Targets

V9.3 should be judged against the policy-corrected V9.2 baseline, not the stale pre-fix fallback numbers.

Minimum target:

| Metric | Target |
|---|---:|
| `case_strict_success_rate` | `>= 0.985` |
| `target_resolution_accuracy` | `>= 0.990` |
| `chronology_phase_accuracy` | `>= 0.985` |
| `action_recall` | `>= 0.990` |
| `runtime_fallback_rate` | `<= 0.010` |
| `schema_valid_rate` | `1.000` |

If `runtime_fallback_rate` rises above `0.010`, treat it as regression unless the case is a genuine safety failure (`empty actions`, object loss, dangling target, missing marked object).

The stricter table above is the preferred V9.3 quality target. The wrapper's default thresholds match the original project goal and can be tightened with CLI flags if needed:

```bash
python3 docs/SGv9pipeline/v9/13_run_v9_3_post_train_eval.py \
  --min-case-strict-success 0.985 \
  --min-target-resolution 0.99 \
  --min-chronology-phase 0.985 \
  --min-action-recall 0.99 \
  --max-runtime-fallback 0.01
```

## 5. Post-Benchmark Failure Mining

After benchmark:

```bash
python3 docs/SGv9pipeline/v9/05_mine_v9_hard_cases.py \
  --eval-cases experiments/sc_benchmark/workspace/eval_bundle_v1/eval_cases.jsonl \
  --event-case-results docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/eval_artifacts/dataset_v9_3_event_sft_seed42.event_case_results.jsonl \
  --output-dir docs/SGv9pipeline/runs/v9_3_seed42/post_benchmark_failure_mining \
  --max-per-cluster 80
```

If total mined failures is `0-2`, V9.3 is likely good enough for thesis/demo. If failures remain clustered around the same patterns, generate V9.4 only for those clusters.

## 6. Demo-Parity Validation

Do not use AR as the first validation. First check the model/parser output without AR:

- dialogue + action split: `talk` beat must not swallow later `put_down`;
- three actors: `first`, `second`, `third` remain distinct;
- second actor `pick_up` then `give` targets `actor_3`;
- targetless `stand` is schema-valid;
- runtime fallback only happens for genuine safety failures.

For defense/demo, use the canonical scenario:

```text
Дима говорит: «Отдай блокнот третьему», а Лиза отвечает: «Принял, передам».
Потом второй берёт блокнот и передаёт его Борису — в итоге блокнот получает именно третий.
```

Expected event table intent:

- beat 1: `actor_1 talk -> actor_2`, `actor_2 talk -> actor_1`;
- beat 2: `actor_2 pick_up -> object_1`;
- beat 3: `actor_2 give -> actor_3`, holding `object_1`.

Only after this passes in non-AR parsing should you test visual playback.

Runnable non-AR checker:

```bash
python3 docs/SGv9pipeline/v9/12_validate_v9_demo_parity.py \
  --compiled-predictions docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/eval_artifacts/dataset_v9_3_event_sft_seed42.compiled_predictions.jsonl \
  --output-dir docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/demo_parity_validation
```

For reference, the same checker intentionally fails on the policy-corrected V9.2 predictions:

```bash
python3 docs/SGv9pipeline/v9/12_validate_v9_demo_parity.py \
  --compiled-predictions docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions_policy_v93/eval_artifacts/dataset_v9_2_event_sft_policy_v93_seed42.compiled_predictions.jsonl \
  --output-dir docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions_policy_v93/demo_parity_validation
```

V9.2 baseline result:

```text
passed=0/3
dialogue_put_down: missing actor_2 put_down
three_actor_give: missing talk/pick_up/give sequence
three_actor_ordinal_status: actor_2 stand instead of look_at actor_1
```

V9.3 should pass `3/3` before claiming demo readiness.
