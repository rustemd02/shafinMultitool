---
status: draft_scene_generator_experiments
chapter: experiments
scope: SceneGeneratorModule only
last_updated: 2026-06-04
---

# 5. Эксперименты

В этой главе рассматривается экспериментальная оценка модуля генерации структурированного описания сцены. Цель экспериментов состоит не только в сравнении отдельных обученных чекпойнтов, но и в проверке основного инженерного предположения работы: надежность мобильного Scene Generator повышается, когда модель не генерирует финальный `SceneScript` напрямую, а заполняет более ограниченный промежуточный контракт, который затем проверяется и компилируется детерминированным слоем.

Глава ограничена модулем `SceneGeneratorModule`. Эксперименты по анализу изображения и рекомендациям в этот раздел не включаются, поскольку для них используется другой набор данных, другая постановка задачи и другая шкала качества.

## 5.1. Методика экспериментальной оценки

Основной воспроизводимый контур оценки Scene Generator построен вокруг frozen benchmark bundle `sgv7_eval_bundle_v1`. Набор содержит 262 тестовых случая и разделен на три группы: `synthetic_heldout` - 109 случаев, `hard_heldout` - 89 случаев и `real_runtime` - 64 случая. Вместе с набором зафиксированы snapshots prompt, decoding, grammar, normalization and runtime policy, что снижает риск скрытого изменения условий оценки между прогонами.

Оценка выполняется как scoring уже сохраненных predictions. В рамках этой главы новые predictions не генерировались: используются существующие benchmark artifacts, сохраненные в репозитории. Такой выбор делает результаты воспроизводимыми и не смешивает качество модели с изменчивостью локального запуска, endpoint serving или Colab environment.

Используемые группы метрик:

| Группа | Метрики | Смысл |
|---|---|---|
| Structural validity | `json_valid`, `schema_valid` | Может ли результат быть разобран и пройти структурный контракт. |
| Semantic recovery | `target_resolution`, `chronology`, `action_recall`, `ordinal_binding` | Насколько корректно восстановлены цели действий, порядок, действия и привязка актеров. |
| Runtime behavior | `runtime_fallback` | Доля случаев, где runtime вынужден отклонить результат и перейти к fallback; ниже лучше. |
| End-to-end strictness | `strict_success` | Доля случаев, где выполнены ключевые структурные, семантические и runtime-условия. |

Важное ограничение методики: большая таблица в разделе 5.2 является эволюционным сравнением поколений, а не единым однородным leaderboard. Между `v6`, `v7`, `v8` и `v9final` менялись контракт вывода, промежуточное представление и runtime/scorer policy. Поэтому в таблице явно указаны контекст и источник каждой строки. Строго сопоставимый срез, где строки оценены в одном финальном benchmark context, вынесен отдельно в раздел 5.3.

При чтении benchmark reports также нельзя смешивать `Model Summary` and `Slice Summary`. В `Model Summary` поле `real_runtime.runtime_fallback_rate` относится к подмножеству `real_runtime`, а в таблицах этой главы используется overall/end-to-end `runtime_fallback_rate`, поскольку он соответствует полной 262-case оценке.

## 5.2. Эволюция подходов Scene Generator

Развитие Scene Generator можно описать как последовательный перенос ответственности с LLM на более проверяемые промежуточные представления и deterministic compiler:

| Подход | Представление | Роль модели | Роль deterministic слоя |
|---|---|---|---|
| `base` | прямой `SceneScript` JSON | Сразу генерирует финальную структуру. | Только проверяет/отклоняет результат. |
| `v6` | legacy direct JSON | Генерирует структуру старого контракта. | Проверяет старый schema contract; плохо переносится на SG v7 contract. |
| `v7` | graph-first / canonical semantics | Учится на данных, где canonical scene semantics формируются до surface variants. | Валидаторы удерживают идентификаторы, ordinal bindings and runtime constraints. |
| `v7_orpo` | SG v7 direct JSON + preference optimization | Улучшает часть runtime-semantics по сравнению с `v7`. | Тот же runtime/scoring слой выявляет tradeoff между semantic recall and structural stability. |
| `v8` | `ScenePlanIR -> SceneScript` | Генерирует промежуточный план вместо финального сценария. | Компилирует план в `SceneScript`, снижая нагрузку на модель. |
| `v9final` | slot/event table -> verifier -> compiler | Заполняет компактную таблицу слотов и событий. | Проверяет, чинит ограниченные случаи и детерминированно компилирует итоговый сценарий. |

### 5.2.1. Основная таблица результатов

В таблице ниже значения приведены в процентах. `runtime_fallback` интерпретируется обратно остальным метрикам: меньшее значение означает лучший результат. Колонка "контекст" показывает, почему отдельные строки нельзя читать как полностью однородный leaderboard.

| Подход | Контекст оценки | `json_valid` | `schema_valid` | `target_resolution` | `chronology` | `action_recall` | `strict_success` | `runtime_fallback` |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `base` | SG v7 frozen bundle, direct baseline, sanitized prediction export | 42.75 | 0.38 | 0.00 | 0.00 | 0.00 | 0.00 | 100.00 |
| `v6` | SG v7 contract stress-test; legacy model on newer contract | 1.53 | 1.53 | 0.00 | 0.00 | 0.00 | 0.00 | 100.00 |
| `v7` | SG v7 graph-first dataset, direct `SceneScript` scoring | 98.85 | 98.85 | 6.32 | 4.58 | 6.03 | 2.29 | 97.33 |
| `v7_orpo` | Latest SG v7 ORPO iter2 profile | 95.04 | 94.66 | 11.62 | 8.40 | 11.08 | 3.82 | 94.66 |
| `v8` | `ScenePlanIR -> compiler`, release-era V8 benchmark | 95.04 | 56.49 | 48.03 | 14.12 | 47.41 | 10.31 | 71.37 |
| `v9final` | Fresh `dataset_v9_3_event_sft`, final frozen seed42 benchmark | 100.00 | 100.00 | 99.83 | 99.62 | 99.86 | 99.62 | 0.00 |

Источники таблицы:

| Строки | Источник |
|---|---|
| `base`, `v7`, `v7_orpo` | `experiments/sc_benchmark/reports/v6_v7/combined_eval_base_v6_v7_v7_orpo.md`, `docs/SGv7pipeline/runs/sgv7_full_20260417/iter2/benchmark_results_seed42/aggregate/scientific_report.md` |
| `v6` | `experiments/sc_benchmark/reports/v6_v7/combined_eval_base_v6_v7_v7_orpo.md`, `experiments/sc_benchmark/v6/legacy/legacy_v6_summary_corrected.json` |
| `v8` | `docs/SGv8pipeline/runs/v8_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md` |
| `v9final` | `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/benchmark_results_seed42/aggregate/scientific_report.md`, `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/v9_3_post_train_eval_summary.json` |

Отдельно важно зафиксировать legacy-результат `v6`. На собственном старом контракте `v6` имел `json_parse_rate=100.00%`, `schema_valid_rate=55.02%`, `actor_count_match_rate=81.34%` and `action_count_match_rate=35.41%` на 209 случаях. Однако при проверке на SG v7 contract этот же подход почти полностью проваливает структурные и runtime-метрики. Это не означает, что `v6` был "плохой моделью" в абсолютном смысле; это показывает, что рост требований к контракту сделал прямую генерацию финального JSON недостаточной.

### 5.2.2. Интерпретация эволюционной таблицы

Сравнение `base`, `v7` and `v7_orpo` показывает, что graph-first dataset and validation pipeline резко повышают структурную устойчивость: `v7` достигает `json_valid=98.85%` and `schema_valid=98.85%` против почти полного runtime fallback у `base`. Однако semantic recovery остается слабой: `target_resolution=6.32%`, `chronology=4.58%`, `action_recall=6.03%`. ORPO-итерация улучшает эти semantic-runtime метрики, но ценой некоторого снижения JSON/schema/identity stability.

Переход к `v8` меняет характер ошибки. Модель больше не обязана сразу строить финальный `SceneScript`; она генерирует `ScenePlanIR`, а deterministic compiler превращает план в runtime contract. Это дает заметный рост semantic recovery: `target_resolution` увеличивается до `48.03%`, `action_recall` до `47.41%`, `strict_success` до `10.31%`. Но `schema_valid=56.49%` and `runtime_fallback=71.37%` показывают, что `ScenePlanIR` все еще оставляет модели слишком много структурной ответственности.

`v9final` переносит модельный вывод еще ближе к компактному semantic table: акторы, объекты, действия и порядок событий становятся явными слотами. На frozen seed42 benchmark fresh `dataset_v9_3_event_sft` достигает `strict_success=99.62%`, `target_resolution=99.83%`, `chronology=99.62%`, `action_recall=99.86%` and `runtime_fallback=0.00%`. Поэтому главный экспериментальный вывод состоит в том, что прирост качества связан не только с дообучением, но и с изменением формы задачи: от свободной генерации JSON к ограниченному slot/event contract with deterministic verification and compilation.

## 5.3. Строго сопоставимый срез на финальном frozen benchmark

Чтобы отделить историческую эволюцию от более строгого сравнения, ниже приведен срез из финального V9.3 benchmark context. В нем `dataset_v7_orpo_iter2`, `dataset_v8_plan_orpo_iter1` and `dataset_v9_3_event_sft` оценены на одном frozen seed42 bundle and final scorer/runtime policy.

| Модель | `json_valid` | `schema_valid` | `ordinal_binding` | `target_resolution` | `chronology` | `action_recall` | `strict_success` | `runtime_fallback` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `dataset_v7_orpo_iter2` | 59.16 | 59.16 | 52.60 | 12.82 | 3.44 | 12.06 | 3.44 | 50.76 |
| `dataset_v8_plan_orpo_iter1` | 95.04 | 95.04 | 83.85 | 48.03 | 14.12 | 47.41 | 14.12 | 39.31 |
| `dataset_v9_3_event_sft` | 100.00 | 100.00 | 100.00 | 99.83 | 99.62 | 99.86 | 99.62 | 0.00 |

Источник: `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/benchmark_results_seed42/aggregate/scientific_report.md`.

Pairwise comparison in the same report:

| Candidate | Baseline | Wins | Baseline wins | Ties | `sign_test_pvalue` | Delta `json_valid`, pp | Delta `chronology`, pp |
|---|---|---:|---:|---:|---:|---:|---:|
| `dataset_v8_plan_orpo_iter1` | `dataset_v7_orpo_iter2` | 149 | 84 | 29 | 0.000025 | 0.000 | +5.725 |
| `dataset_v9_3_event_sft` | `dataset_v8_plan_orpo_iter1` | 224 | 0 | 38 | 0.000000 | +4.962 | +85.496 |
| `dataset_v9_3_event_sft` | `dataset_v7_orpo_iter2` | 240 | 0 | 22 | 0.000000 | +4.962 | +91.221 |

Эта таблица является более сильным основанием для утверждения, что `v9final` лучше предыдущих архитектурных вариантов на данном frozen benchmark. В отличие от большой эволюционной таблицы, здесь сравнение происходит в одном оценочном контексте.

## 5.4. Диагностика промежуточных представлений

Дополнительные representation-specific metrics помогают объяснить, почему меняется качество.

Для `v8` raw plan slice показывает, что план разбирается достаточно часто, но его внутренняя связанность еще ограничена:

| Модель | `plan_parse` | `reference_binding` | `beat_integrity` |
|---|---:|---:|---:|
| `dataset_v8_plan_sft` | 95.80 | 76.34 | 27.48 |
| `dataset_v8_plan_orpo_iter1` | 95.80 | 75.95 | 27.86 |

Источник: `docs/SGv8pipeline/runs/v8_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md`.

Для `v9final` raw event-table metrics показывают почти полное восстановление semantic rows:

| Метрика | Значение |
|---|---:|
| `event_parse_rate` | 100.00 |
| `event_schema_valid_rate` | 100.00 |
| `event_actor_slot_accuracy` | 99.86 |
| `event_target_slot_accuracy` | 100.00 |
| `event_action_type_accuracy` | 100.00 |
| `event_beat_order_accuracy` | 100.00 |
| `event_full_row_accuracy` | 99.86 |

Источник: `docs/SGv9pipeline/runs/v9_3_seed42/from_user_predictions/eval_artifacts/dataset_v9_3_event_sft_seed42.event_slice_summary.json`.

Эта диагностика поддерживает основной вывод: `v8` уже улучшает semantic recovery за счет промежуточного плана, но `v9` делает ключевые зависимости более локальными и проверяемыми. Вместо свободного описания плана модель заполняет более компактные события, где actor, target, action type and order are explicit fields.

## 5.5. Failure analysis and policy audit

Отдельный audit V9.2 показал, что высокий fallback не всегда означает ошибку модели. В `dataset_v9_2_event_sft` часть отказов была вызвана stale V7/V8 mirror runtime policy:

| Наблюдение | До policy fix | После policy fix |
|---|---:|---:|
| Runtime accepts | 152 / 262 | 261 / 262 |
| Runtime rejects | 110 / 262 | 1 / 262 |
| Schema-valid cases | 159 / 262 | 262 / 262 |
| Strict-success cases | 146 / 262 | 254 / 262 |
| Semantic gates pass but rejected | 108 | 0 |

Источник: `docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions_policy_v93/fallback_audit/v9_2_to_v9_3_policy_audit.md`.

Причины были конкретными: действие `stand` ошибочно считалось target-required, а `pred_confidence_below_rule` применял старую confidence logic к compact event-table output. После исправления policy replay на тех же frozen V9.2 predictions достиг `schema_valid=100.00%`, `runtime_fallback=0.38%`, `strict_success=96.95%`, `target_resolution=98.12%`, `chronology=96.95%` and `action_recall=98.46%`. Это не считается результатом новой обученной модели, но является важным методологическим результатом: benchmark должен соответствовать актуальному output contract.

Fresh `v9final` затем проверялся уже как новый successor checkpoint. Его post-train wrapper прошел acceptance gate and demo-parity `3/3`, но post-benchmark hard-case mining все еще нашел 1 remaining `dialogue_action` case. Поэтому корректная формулировка результата: модель достигла высоких measured metrics на frozen benchmark, но это не доказывает универсальное решение всех случаев scene parsing.

## 5.6. Угрозы валидности

1. Сравнение проводится на frozen seed42 bundle. Это хорошо для воспроизводимости, но не заменяет проверку на дополнительных seeds and external datasets.
2. Большая таблица включает разные поколения output contract. Она показывает эволюцию инженерного решения, но не должна читаться как единый homogeneous leaderboard.
3. Legacy `v6` metrics on its own contract and SG v7 stress-test metrics answer different questions. Их можно обсуждать рядом, но нельзя считать прямым A/B.
4. Policy replay V9.2 demonstrates scorer/runtime alignment; it is not a retrained checkpoint result.
5. `v9final` имеет очень высокие метрики на benchmark, но failure mining still records one hard case. Поэтому нельзя писать, что Scene Generator полностью решает задачу генерации структурированных сцен.
6. Live-smoke данные из `diploma.md` полезны как инженерная история, но для финального доказательства качества лучше опираться на frozen benchmark artifacts and attach live parity logs separately before defense.

## 5.7. Выводы

Эксперименты показывают, что главный прирост качества Scene Generator достигается при изменении формы модельной задачи. Direct generation of final `SceneScript` gives high structural fragility and high runtime fallback. SG v7 stabilizes JSON/schema behavior through graph-first data and validators, but remains weak on semantic recovery. SG v8 improves target and action recovery by moving to `ScenePlanIR`, but still leaves enough ambiguity to produce schema/runtime failures. SG v9final reaches near-complete strict success on the frozen benchmark because the model outputs a compact event table, while deterministic verifier and compiler own the final runtime contract.

Таким образом, экспериментальная часть подтверждает архитектурную гипотезу работы: для мобильного сценарного генератора надежность повышается не только за счет fine-tuning, but by designing a constrained intermediate representation that makes model errors observable, recoverable and checkable before runtime use.
