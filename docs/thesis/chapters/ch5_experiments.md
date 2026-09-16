---
status: needs_update
chapter: experiments
scope: SceneGeneratorModule only; Camera Analysis eval artifacts added separately and chapter structure needs decision
last_updated: 2026-06-15
needs_update_reason: >-
  2026-09-16 EV-CA-PARTIAL-INTAKE-001 records 17 actual assisted photos, 37 issue
  labels, 99 unknowns and real masked backward with zero optimizer steps. No fit,
  calibration or release evaluation can be inferred. EV-SG-BACKEND-PACKAGE-001 is
  local integration/reproducibility evidence and does not measure generation quality.
  2026-09-13 Q05 sync added experiment-evidence entries not yet reflected here: EV-CA-DATA-ANNO-001/
  CL-CA-035 (21-to-8 frozen label mapping with beauty≠KEEP, absence≠negative and absent-delta=mask
  rules; real 547-record queue integrity and licence provenance; full tools/tests 114 passed),
  EV-SG-D05-001/CL-SG-D05-001 (numeric Scene gates pass but the full D05 packet fails on corpus
  RU/EN, provenance, unmeasured gates, unconfirmed floors and scoring an external fine-tuned V9.3
  artifact instead of the on-device provider), EV-REL-GATES-001/CL-REL-GATES-001 (release-candidate
  gate instrument: 0/81 = 3.6309 % Clopper–Pearson, minimum 149 clean advised-good frames for the
  2 % budget, fail-closed exit 2) and EV-CA-ML-002/CL-CA-034 (masked trainer verified but no
  admitted-data training). Do not present a passed D05 packet or a trained v2 candidate.
  2026-09-13 Q05 round 3: EV-CA-ML-005/CL-CA-052 (the v2 export path is validated as tooling
  only — untrained, release_admissible=false, blocked_on=M03/M04; the .mlpackage tree_sha256 is
  not reproducible, weights_sha256 is the stable identity) and EV-REL-RIGHTS-001/CL-REL-RIGHTS-001
  (first-source CC BY 3.0 facts and a fail-closed activation toolkit with 0 admitted corpora) are
  experiment-evidence boundaries; do not present an exported v2 package as a trained candidate.
  2026-09-13 Q05 round 4: EV-REL-PRODUCERS-001/CL-REL-PRODUCERS-001 (six §5 producers that derive
  each block, checked by an executable 36-quantity key-coverage map) and EV-REL-POLICY-001/
  CL-REL-POLICY-001 (the versioned acceptance policy behaviorally bound to the gate instrument)
  are experiment-infrastructure evidence only; EV-REL-REHEARSAL-001/CL-REL-REHEARSAL-001 records
  that chain rehearsals on real artifacts prove connectivity, not data quality. Do not present the
  §5 gate set as passed or the rehearsals as accepted data.
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

Важное ограничение методики: большая таблица в разделе 5.2 является эволюционным сравнением поколений, а не единым однородным leaderboard. Между `v6`, `v7`, `v8` и `v9final` менялись контракт вывода, промежуточное представление, compiler behavior и runtime/scorer policy. Поэтому эту таблицу нельзя просто переименовать в «модель против модели».

Дополнительная перепроверка train/eval overlap показала еще одно ограничение: часть поздних `v8`, `v9.2` и `v9.3` train-corpus строк пересекается с frozen eval bundle либо по explicit origin case id, либо по точному `source_text`, либо по общему `graph_family_key`. В результате не существует одной таблицы, которая одновременно была бы:

1. кросс-поколенной;
2. полностью leakage-free;
3. репрезентативной для исходного 262-case difficulty mix.

Поэтому в главе используются два дополняющих друг друга среза:

1. раздел 5.2 — эволюционная таблица по полному 262-case bundle, полезная для инженерной истории и анализа архитектурного перехода;
2. раздел 5.3 — leakage-aware holdout для более честного формата «model vs model», но уже на существенно более узком и более легком подмножестве.

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

После overlap-аудита эту таблицу корректно читать именно как историю развития инженерного решения. Она показывает, как менялось качество вместе с изменением контракта, compiler/runtime policy и targeted hard-case data, но не доказывает, что один только новый чекпойнт модели обязательно доминирует над всеми предыдущими при строго одинаковых условиях.

Отдельно важно зафиксировать legacy-результат `v6`. На собственном старом контракте `v6` имел `json_parse_rate=100.00%`, `schema_valid_rate=55.02%`, `actor_count_match_rate=81.34%` and `action_count_match_rate=35.41%` на 209 случаях. Однако при проверке на SG v7 contract этот же подход почти полностью проваливает структурные и runtime-метрики. Это не означает, что `v6` был "плохой моделью" в абсолютном смысле; это показывает, что рост требований к контракту сделал прямую генерацию финального JSON недостаточной.

### 5.2.2. Интерпретация эволюционной таблицы

Сравнение `base`, `v7` and `v7_orpo` показывает, что graph-first dataset and validation pipeline резко повышают структурную устойчивость: `v7` достигает `json_valid=98.85%` and `schema_valid=98.85%` против почти полного runtime fallback у `base`. Однако semantic recovery остается слабой: `target_resolution=6.32%`, `chronology=4.58%`, `action_recall=6.03%`. ORPO-итерация улучшает эти semantic-runtime метрики, но ценой некоторого снижения JSON/schema/identity stability.

Переход к `v8` меняет характер ошибки. Модель больше не обязана сразу строить финальный `SceneScript`; она генерирует `ScenePlanIR`, а deterministic compiler превращает план в runtime contract. Это дает заметный рост semantic recovery: `target_resolution` увеличивается до `48.03%`, `action_recall` до `47.41%`, `strict_success` до `10.31%`. Но `schema_valid=56.49%` and `runtime_fallback=71.37%` показывают, что `ScenePlanIR` все еще оставляет модели слишком много структурной ответственности.

`v9final` переносит модельный вывод еще ближе к компактному semantic table: акторы, объекты, действия и порядок событий становятся явными слотами. На frozen seed42 benchmark fresh `dataset_v9_3_event_sft` достигает `strict_success=99.62%`, `target_resolution=99.83%`, `chronology=99.62%`, `action_recall=99.86%` and `runtime_fallback=0.00%`. Поэтому главный экспериментальный вывод состоит в том, что прирост качества связан не только с дообучением, но и с изменением формы задачи: от свободной генерации JSON к ограниченному slot/event contract with deterministic verification and compilation.

## 5.3. Строгий anti-leakage refresh для честного формата «model vs model»

После первоначального leakage-aware анализа был добавлен более строгий normalized matching. Он считает пересечением не только exact `source_text` и exact `graph_family_key`, но и:

1. exact `sample_id`;
2. `normalized_source_hash`;
3. `graph_family_key` с short-hash normalization, когда full family key и его короткий граф-хэш считаются одним family anchor.

Под этим более строгим правилом исходный `eval_bundle_v1` удерживает уже не `140`, а `0` leakage-safe случаев из `262`: все historical benchmark cases пересекаются с checked train corpora по `sample_id` и `graph_family_key`, а часть дополнительно совпадает по surface-text/hash. Значит промежуточный `clean140` нельзя оставлять как финальную «честную» таблицу.

### 5.3.1. Как выглядел benchmark раньше и как выглядит сейчас

| Срез | `N` | Leakage status | Состав | Для чего пригоден | Текущий статус метрик |
|---|---:|---|---|---|---|
| `full262` | 262 | contaminated under strict normalized matching | historical frozen bundle: `109/89/64` | Эволюционная инженерная траектория и сравнение архитектурных поколений на исходном frozen benchmark | Метрики есть и остаются валидными как historical full-bundle trajectory |
| `clean140` | 140 | intermediate, superseded | retained subset after earlier lenient audit: `60/63/17` | Промежуточная попытка fairer all-model slice | Метрики есть, но этот slice больше не считается финальным honest model-vs-model benchmark |
| `fresh262` | 262 | strict clean | newly generated bundle: `109 synthetic_heldout`, `89 hard_heldout`, `64 real_runtime` proxy | Новый честный cross-generation rerun без train/eval overlap | Prediction rerun еще не выполнен, поэтому финальных fresh262 model metrics пока нет |

Здесь важно различать два вопроса:

1. «Какими были measured numbers на frozen historical benchmark?» — на это отвечает section 5.2.
2. «Как получить максимально честный model-vs-model benchmark без leakage?» — на это теперь отвечает `fresh262`, а не `clean140`.

### 5.3.2. Почему `N=262` снова стало возможным

Раньше казалось, что честный all-model compare неизбежно должен схлопнуться до `140`, потому что overlap cases нужно просто выкинуть. Строгий audit показал более неприятную, но более полезную правду: внутренние historical резервуары (`sft_val`, `preference_val`, `accepted_*`, `runtime_preference_candidates`) тоже сидят на train-family overlap. Поэтому корректное решение — не отрезать старый bundle до бесконечности, а materialize-ить новый.

Новый `fresh262` bundle строится так:

1. materialize fresh SG v7 `core` graphs;
2. materialize fresh SG v7 `hard` graphs;
3. generate fresh heuristic source variants;
4. reject any candidate that overlaps checked train corpora by strict normalized policy;
5. сохранить исходные bucket counts `109/89/64`;
6. rebuild `real_runtime` slice as synthetic runtime proxies, потому что leakage-safe unused real-runtime reserve внутри historical SG v7 pools больше не осталось.

Именно поэтому `N=262` теперь возвращается, но не через reuse старых кейсов, а через полный refresh eval bundle.

### 5.3.3. Что это меняет для интерпретации результатов

Из этого следуют три методологических вывода.

1. Полная таблица 5.2 остается корректной как historical engineering trajectory. Она показывает реальный путь `v7 -> v8 -> v9`, включая пользу constrained intermediate contracts, compiler/runtime hardening и targeted hard-case training.
2. Промежуточный `clean140` надо трактовать как exploratory artifact. Его нельзя больше использовать как главный аргумент о «честном» сравнении моделей, потому что stricter matching показал, что исходный bundle целиком contaminated и требует полного refresh.
3. Новый честный model-vs-model answer теперь привязан не к старым `140` метрикам, а к будущему rerun на `fresh262`. Без regenerated predictions для всех сравниваемых checkpoints любые попытки заполнить новую master-table числами были бы методологически нечестными.

Иными словами, section 5.3 в текущей версии работы фиксирует не финальные fresh262 model numbers, а исправление самой benchmark methodology: старый frozen bundle больше нельзя выдавать за leakage-free cross-generation test, а новый strict refresh bundle уже подготовлен и готов к полному rerun.

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
2. Большая таблица 5.2 включает разные поколения output contract. Она показывает эволюцию инженерного решения, но не должна читаться как единый homogeneous leaderboard.
3. Leakage-aware holdout из раздела 5.3 честнее в смысле train/eval overlap, но он materially easier than the original benchmark: из 64 `real_runtime` cases остается только 17, а многие поздние targeted hard/runtime families исключаются полностью.
4. Поэтому в этой работе нет одной универсальной «идеальной» таблицы. Полный 262-case bundle лучше отражает исходную трудность задачи, а 140-case clean holdout лучше отвечает на узкий вопрос о более честном model-vs-model сравнении.
5. Legacy `v6` metrics on its own contract and SG v7 stress-test metrics answer different questions. Их можно обсуждать рядом, но нельзя считать прямым A/B.
6. Policy replay V9.2 demonstrates scorer/runtime alignment; it is not a retrained checkpoint result.
7. `v9final` имеет очень высокие метрики на benchmark, но failure mining still records one hard case, а leakage-aware holdout показывает one retained hard-case miss for fresh V9.3. Поэтому нельзя писать, что Scene Generator полностью решает задачу генерации структурированных сцен.
8. Live-smoke данные из `diploma.md` полезны как инженерная история, но для финального доказательства качества лучше опираться на frozen benchmark artifacts and attach live parity logs separately before defense.

## 5.7. Выводы

Эксперименты показывают, что главный прирост качества Scene Generator достигается при изменении формы модельной задачи. Direct generation of final `SceneScript` gives high structural fragility and high runtime fallback. SG v7 stabilizes JSON/schema behavior through graph-first data and validators, but remains weak on semantic recovery. SG v8 improves target and action recovery by moving to `ScenePlanIR`, but still leaves enough ambiguity to produce schema/runtime failures. SG v9-family reaches near-complete strict success on the frozen benchmark because the model outputs a compact event table, while deterministic verifier and compiler own the final runtime contract.

При этом честная итоговая интерпретация должна быть двухслойной. Полная 262-case таблица подтверждает архитектурную гипотезу о пользе constrained intermediate representation, compiler and policy hardening на реальном инженерном trajectory. Leakage-aware 140-case holdout показывает более строгую model-vs-model картину: cross-generation progress `v7 -> v8 -> v9` сохраняется, но внутри поздней V9 family retained clean slice уже не подтверждает narrative о безусловном доминировании fresh V9.3 checkpoint над V9.0.

Таким образом, экспериментальная часть подтверждает архитектурную гипотезу работы: для мобильного сценарного генератора надежность повышается не только за счет fine-tuning, but by designing a constrained intermediate representation that makes model errors observable, recoverable and checkable before runtime use. Одновременно перепроверка метрик показывает, что финальные диссертационные claims должны разделять architecture-level progress, policy alignment and pure checkpoint-vs-checkpoint evidence, rather than conflating them into one oversimplified leaderboard.
