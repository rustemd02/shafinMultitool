## proposal
- Проведён финальный Data/Eval review по текущему V9 состоянию в файлах:
  - `docs/SGv7pipeline/v9/eval.py`
  - `docs/SGv7pipeline/v9/eval_artifacts.py`
  - `docs/SGv7pipeline/v9/03_build_v9_eval_artifacts.py`
  - `docs/SGv7pipeline/v9/04_run_v9_local_benchmark.py`
  - `docs/SGv7pipeline/v9/tests/test_v9_datasets_eval.py`
- Подтверждаю, что separation structural vs semantic реализован:
  - structural: `event_*_structural_pass_rate` в `summarize_event_slice_metrics`
  - semantic: gold-based `event_*_accuracy` через row-level hit counts (`semantic_*_hit_count / semantic_row_total`)
  - отчётные секции разделены как `overall`, `structural`, `semantic`, `degradation`.
- Подтверждаю, что деградационные counters реализованы и агрегируются:
  - `targetless_event_repaired_rate`
  - `unknown_slot_blocked_rate`
  - `dropped_event_row_rate`
  - а также counts/totals для аудита.
- Подтверждаю, что live-vs-offline gap report реализован:
  - `04_run_v9_local_benchmark.py` пишет JSON артефакт в `eval_artifacts`
  - считает per-metric delta как `end_to_end - model_only`
  - корректно маркирует skipped-сценарии (`model_slice_summary_missing`, `required_slices_missing`).
- Подтверждаю backward compatibility на отсутствии gold:
  - semantic метрики null-safe (`None` при нулевом denominator)
  - старые поля `event_*_pass` сохранены как deprecated aliases.

## risks
- Semantic alignment fallback в `eval_artifacts.py` при невозможности rowId matching переходит на index-based сопоставление; это полезно для устойчивости, но может слегка сгладить реальные semantic regressions при сильном reorder.
- `live_vs_offline_gap` сейчас строится по `aggregate/model_slice_summary.csv`, то есть охватывает только метрики, реально попавшие в этот CSV. Если туда не заведены новые V9 event-метрики, gap-файл не покажет их дельты.
- Нет отдельного unit/integration теста, который напрямую валидирует генерацию `live_vs_offline_gap.json` в раннере (логика есть, автоматический regression-check пока косвенный).

## required_tests
- Уже пройдено:
  - `python3 -m unittest docs/SGv7pipeline/v9/tests/test_v9_datasets_eval.py docs/SGv7pipeline/v9/tests/test_v9_projection.py`
  - результат: `Ran 8 tests ... OK`.
- Рекомендую добавить в ближайший цикл (как закрытие residual risk):
  - unit test на `_build_live_vs_offline_gap_report`:
    - happy path с обеими slices;
    - skipped path без `model_only`/`end_to_end`;
    - проверка `delta_definition == live_minus_offline`.
  - integration smoke для `04_run_v9_local_benchmark.py` на мини-фикстуре с проверкой наличия `*.live_vs_offline_gap.json`.

## open_conflicts
- `eval_gate` на уровне Data/Eval по текущему scope считаю закрытым, но на уровне всей программы V9-Full остаётся внешняя зависимость от того, экспортируются ли все нужные event-метрики в глобальные benchmark aggregates (вне этого ownership).
- Для полного “no ambiguity” в научном отчёте желательно явный блок в top-level report:
  - `Structural Recovery`
  - `Semantic Fidelity Cost`
  Сейчас разделение есть в V9 summary JSON, но не гарантировано в каждом внешнем агрегаторе.

## votes
- `data_gate`: **PASS**
  - Обоснование: contracts и eval artifacts консистентны, duplicate handling fail-fast, null-safe поведение без gold, тесты зелёные.
- `eval_gate`: **PASS (conditional-hardening)**
  - Обоснование: structural/semantic separation и degradation counters реализованы корректно, gold-aware semantic scoring есть, gap artifact есть.
  - Условие-hardening до финального release freeze: добавить прямой автотест на `live_vs_offline_gap` генерацию и убедиться, что новые V9 event-метрики включаются в конечные aggregate-репорты.
