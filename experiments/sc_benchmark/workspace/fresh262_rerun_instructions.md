# Fresh 262 benchmark rerun

Этот bundle честно очищен от overlap со всеми train-корпусами сравниваемых поколений.

## Что уже готово

- eval bundle: `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/eval_bundle_v2_fresh262_all_models`
- benchmark config template: `/Users/unterlantas/Documents/XCode/shafinMultitool/experiments/sc_benchmark/workspace/benchmark_config.seed42.fresh262_all_models.json`

## Что ещё нужно

1. Сгенерировать новые predictions JSONL для всех моделей на этом bundle.
2. Только после этого запускать `run_scientific_benchmark.py`.

Старые prediction exports на bundle v1 переиспользовать нельзя: `eval_case_id` и тексты уже другие.

## Почему runtime-срез помечен как proxy

В старых внутренних пулах не осталось leakage-safe real runtime кейсов.
Поэтому 64 runtime-case replacement materialized как synthetic runtime proxies:
- gold берётся из fresh CIR projection;
- rule_based_reference_json получается детерминированной деградацией gold;
- provenance это явно фиксирует.
