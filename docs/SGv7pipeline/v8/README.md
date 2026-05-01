# V8 Contracts

`v8` переводит систему с прямой генерации `SceneScript` на внутренний `ScenePlanIR`.

Модули в этой папке дают минимальный рабочий foundation для:
- `CIR -> ScenePlanIR` projection
- deterministic `ScenePlanIR -> SceneScript` compilation
- envelope-compatible dataset builders для:
  - `plan_sft`
  - `subtask_sft`
  - `plan_preference`
  - `critic_rank`
- slice-level eval helpers для `local_plan_raw`
- отдельный CLI для score `ScenePlanIR` plan slices: `02_score_v8_plan_slice.py`
- CLI для сборки eval artifacts из plan predictions: `06_build_v8_eval_artifacts.py`
- optional sidecar integration с `experiments/sc_benchmark/run_scientific_benchmark.py`

Это intentionally internal-only слой: публичный product contract остаётся `SceneScript`.

В runtime это соответствует новому local-first маршруту:
- `SceneAnchorExtractor`
- `SceneMetadataExtractor`
- `LocalScenePlanProvider`
- `ScenePlanCompiler`
- `SceneQualityGate`
- `SceneParseCoordinator`

Router outcomes в текущем foundation:
- `accept_local`
- `fallback_rule_only`
- `offload_remote` (интерфейс заложен, production offload пока feature-flagged)
- `needs_clarification`

Дополнительно:
- `SceneChunkState` поднимается наружу из `SceneParserService` и проходит через `SceneGeneratorViewModel`
- top-level `SceneScript` metadata (`sceneHeading`, `locationName`, `interiorExterior`, `timeOfDay`) извлекаются детерминированно и компилируются вместе с итоговым JSON

Если `ScenePlanIR` case-level rows экспортируются отдельно, benchmark orchestrator может агрегировать их через:
- `v8_plan_case_results_path`
- `v8_plan_case_results_path_template`
- `v8_plan_case_results_by_seed`

Итоговые артефакты:
- `aggregate/v8_plan_slice_summary.csv`
- `aggregate/v8_plan_slice_summary_by_model.csv`

## Dataset builders

Если не хочется копировать длинный shell-блок руками, можно собрать весь первый train-pack одной командой:

```bash
bash docs/SGv7pipeline/v8/build_v8_train_pack.sh
```

Скрипт пишет артефакты в:
- `docs/SGv7pipeline/runs/v8_0_seed42`
- итоговый upload pack: `.../v8_0_seed42/sgv8_train_pack`

### 1. `plan_sft`

```bash
python3 docs/SGv7pipeline/v8/01_build_v8_plan_dataset.py \
  --cir-jsonl /path/to/cir_merged.jsonl \
  --output-jsonl /path/to/v8_plan_sft.jsonl
```

Rows keep the familiar training envelope:
- `task_type = "sft"`
- `messages`
- `source_text`
- `packaging_metadata`

Primary supervision is now plan-native:
- `target_plan_ir`
- `compiled_target_json` as deterministic sidecar

### 2. `subtask_sft`

```bash
python3 docs/SGv7pipeline/v8/03_build_v8_subtask_datasets.py \
  --cir-jsonl /path/to/cir_merged.jsonl \
  --output-dir /path/to/v8_subtasks
```

Writes merged and per-subtask corpora for:
- `anchor_extraction`
- `beat_plan`
- `target_linking`
- `ordinal_linking`

### 3. `plan_preference`

```bash
python3 docs/SGv7pipeline/v8/04_build_v8_plan_preference_dataset.py \
  --eval-cases-jsonl /path/to/eval_cases.jsonl \
  --candidate-predictions-jsonl /path/to/iter2_predictions.jsonl \
  --baseline-predictions-jsonl /path/to/v7_predictions.jsonl \
  --candidate-case-results-jsonl /path/to/iter2_case_results.jsonl \
  --baseline-case-results-jsonl /path/to/v7_case_results.jsonl \
  --candidate-model-id iter2 \
  --baseline-model-id v7 \
  --paired-case-results-jsonl /path/to/paired_case_results.jsonl \
  --output-dir /path/to/v8_plan_preference
```

Preference rows keep the old envelope:
- `task_type = "preference"`
- `messages`
- `chosen` / `rejected` as canonical JSON strings
- `packaging_metadata`

But `chosen` / `rejected` now contain canonical `ScenePlanIR` JSON, not final `SceneScript`.

Sidecars:
- `chosen_plan_ir`
- `rejected_plan_ir`
- `chosen_compiled_json`
- `rejected_compiled_json`

Builder is raw-first for predictions:
- prefers `model_only_predicted_script`
- falls back to `raw_output_json` / `predicted_script` only when needed

### 4. `critic_rank`

```bash
python3 docs/SGv7pipeline/v8/05_build_v8_critic_rank_dataset.py \
  --eval-cases-jsonl /path/to/eval_cases.jsonl \
  --candidate-predictions-jsonl /path/to/iter2_predictions.jsonl \
  --baseline-predictions-jsonl /path/to/v7_predictions.jsonl \
  --candidate-case-results-jsonl /path/to/iter2_case_results.jsonl \
  --baseline-case-results-jsonl /path/to/v7_case_results.jsonl \
  --candidate-model-id iter2 \
  --baseline-model-id v7 \
  --paired-case-results-jsonl /path/to/paired_case_results.jsonl \
  --output-dir /path/to/v8_critic_rank
```

This emits pairwise ranking rows with:
- `candidate_a` / `candidate_b`
- `preferred_side`
- `preferred_model_id`
- `candidate_a_plan_ir` / `candidate_b_plan_ir`
- case-level metric sidecars

### 5. `eval_artifacts`

```bash
python3 docs/SGv7pipeline/v8/06_build_v8_eval_artifacts.py \
  --eval-cases-jsonl /path/to/eval_cases.jsonl \
  --plan-predictions-jsonl /path/to/v8_plan_predictions.jsonl \
  --output-plan-case-results-jsonl /path/to/v8_plan_case_results.jsonl \
  --output-compiled-predictions-jsonl /path/to/v8_compiled_predictions.jsonl
```

This converts `ScenePlanIR` predictions into two benchmark-ready artifacts:
- `v8_plan_case_results.jsonl` for `local_plan_raw` slice aggregation
- `v8_compiled_predictions.jsonl` for normal `SceneScript` product metrics

Lenient compile notes are propagated for traceability:
- `v8.targetless_action_downgraded`
- `v8.invalid_spatial_relation_skipped`

These notes are exported into:
- `plan_case_results.compile_notes`
- `compiled_predictions.slice_reason_codes`

### 6. `local_benchmark` (one command)

Когда Colab уже отдал `sgv8_eval_pack_seed42.zip`, локальный benchmark можно прогнать одной командой:

```bash
python3 docs/SGv7pipeline/v8/07_run_v8_local_benchmark.py
```

Скрипт сам:
- распакует `sgv8_eval_pack_seed42.zip` из `.../v8_0_seed42/sgv8_eval_export_seed42`
- соберёт `eval_artifacts` через `06_build_v8_eval_artifacts.py`
- пересоберёт `benchmark_config.v8.seed42.json`
- запустит `experiments/sc_benchmark/run_scientific_benchmark.py --mode full`

Итоговые метрики:
- `.../benchmark_results_seed42/aggregate/runs_scored.csv`
- `.../benchmark_results_seed42/aggregate/pairwise_compare.csv`
- `.../benchmark_results_seed42/aggregate/model_slice_summary.csv`
- `.../benchmark_results_seed42/aggregate/v8_plan_slice_summary.csv`
- `.../benchmark_results_seed42/aggregate/scientific_report.md`

## Compatibility note

`v8` keeps the existing training envelope on purpose so split/balance/phase tooling can be reused more easily:
- `messages`
- `source_text`
- `packaging_metadata`

New v8-specific markers live in `packaging_metadata`:
- `v8_task_type`
- `training_target`
- `plan_contract_version`
- `anchor_contract_version`
- `compiler_version`
