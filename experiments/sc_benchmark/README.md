# Scientific Benchmark Orchestrator

Файл-оркестратор:
- [run_scientific_benchmark.py](/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/run_scientific_benchmark.py)

Пример конфига:
- [benchmark_config.example.json](/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/benchmark_config.example.json)

Подготовка `eval_bundle_v1` и тестовых predictions:
- [prepare_experiment_assets.py](/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/prepare_experiment_assets.py)

Автогенерация real predictions с endpoint (OpenAI-compatible):
- [generate_predictions_from_endpoint.py](/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/generate_predictions_from_endpoint.py)

## Что автоматизирует

Поддерживаемая схема сравнения по умолчанию: `base_qwen3_1_7b` vs `dataset_v6` vs `dataset_v7` vs `dataset_v7_orpo`.

1. Прогон `score` для всех моделей и seed'ов через:
   - `/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/eval/07_eval_local_model.py --mode score`
2. Прогон `compare` для всех пар подходов и seed'ов:
   - `--mode compare`
3. Сбор агрегированных артефактов:
   - `aggregate/runs_scored.csv`
   - `aggregate/model_summary.csv`
   - `aggregate/pairwise_compare.csv`
   - `aggregate/v8_plan_slice_summary.csv` (optional, если заданы `v8_plan_case_results_*`)
   - `aggregate/scientific_report.md`
   - `aggregate/benchmark_manifest.json`

## Граница ответственности папок

`experiments/sc_benchmark/` хранит:
- benchmark code
- reusable configs
- frozen workspace assets (`eval_bundle`, template predictions, serving maps)

Конкретные run-артефакты и исследовательские прогоны лучше хранить в:
- [`docs/SGv7pipeline/runs/...`](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs)

Практическое правило:
- если файл нужен как reusable benchmark infrastructure, его место в `experiments/sc_benchmark`
- если это результат конкретного прогона модели, Colab export, benchmark result, manual review pack или corpus attempt, его место в `docs/SGv7pipeline/runs/...`

## Базовый запуск

```bash
python3 /Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/run_scientific_benchmark.py \
  --config /Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/benchmark_config.example.json \
  --output-dir /tmp/sc_benchmark_run \
  --mode full
```

## Быстрый bootstrap всех артефактов

```bash
python3 /Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/prepare_experiment_assets.py
```

После этого появятся:
- `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/eval_bundle_v1`
- `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/predictions_oracle_v1`
- `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/benchmark_config.v1.json`
- `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/predictions_real_v1`
- `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/benchmark_config.real.v1.json`

## Автогенерация real predictions

```bash
python3 /Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/generate_predictions_from_endpoint.py \
  --eval-bundle-dir /Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/eval_bundle_v1 \
  --output-dir /Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/predictions_real_v1 \
  --models base_qwen3_1_7b,dataset_v6,dataset_v7,dataset_v7_orpo \
  --seeds 42,43,44 \
  --api-base-url http://127.0.0.1:8000/v1 \
  --serving-model-map-json /Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/serving_model_map.template.json
```

## Режимы

- `--mode full`: score + compare + aggregate
- `--mode score-only`: только score + aggregate
- `--mode aggregate-only`: только чтение уже готовых отчётов и построение итоговых таблиц

## Если predictions ещё не готовы

Можно прописать в `models[*].generate_predictions_cmd` shell-команду генерации predictions.
Тогда запускай с флагом:

```bash
--allow-generate-predictions
```

Шаблонные переменные внутри команды:
- `{model_id}`, `{model_name}`, `{seed}`, `{checkpoint_id}`, `{predictions_jsonl}`, `{report_dir}`

## Optional: V8 Plan Slice

Если для модели есть sidecar JSONL с case-level `ScenePlanIR` eval rows, можно добавить один из ключей:
- `v8_plan_case_results_path`
- `v8_plan_case_results_path_template`
- `v8_plan_case_results_by_seed`

Тогда orchestrator дополнительно посчитает:
- `aggregate/v8_plan_slice_summary.csv`
- `aggregate/v8_plan_slice_summary_by_model.csv`

Ожидаемые поля на строку:
- `plan_parse_ok`
- `plan_reference_binding_pass`
- `plan_beat_integrity_pass`
