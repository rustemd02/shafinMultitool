# 09. Eval And Release

## Цель

Выпускать новую модель только по метрикам, а не по впечатлению от нескольких удачных примеров.

## Eval sets

### 1. Synthetic held-out

Нужен для:
- общей regression проверки

### 2. Hard held-out

Нужен для:
- stress cases

### 3. Real runtime eval

Нужен для:
- проверки реальных пользовательских формулировок

## Core metrics

- `json_valid_rate`
- `marked_object_recall`
- `exact_marked_object_id_accuracy`
- `beat_count_accuracy`
- `action_recall`
- `described_action_precision`
- `dangling_target_rate`
- `ordinal_actor_binding_accuracy`
- `target_resolution_accuracy`
- `chronology_phase_accuracy`
- `llm_accept_rate`
- `llm_merge_rate`
- `llm_reject_rate`
- `runtime_fallback_rate`

## Must-have bucket metrics

Отдельно считать:
- `ordinal_cases`
- `marked_object_morphology`
- `same_type_markers`
- `unsupported_action_cases`
- `three_beat_cases`
- `exact_marker_identity_cases`
- `reviewed_merge_cases`

## Metric Semantics

- `exact_marked_object_id_accuracy` проверяет не просто наличие объекта, а совпадение exact `object_marked_*`
- `ordinal_actor_binding_accuracy` проверяет, что `first/second` привязаны к правильным actor ids
- `target_resolution_accuracy` проверяет, что все action targets существуют и указывают на правильный actor/object
- `chronology_phase_accuracy` проверяет, что multi-phase scenes не схлопнулись и не переставлены местами

## Release gate

Новая модель идёт в прод только если:
- нет деградации на core metrics
- нет деградации на `exact_marked_object_id_accuracy`
- нет деградации на `ordinal_actor_binding_accuracy`
- нет деградации на `target_resolution_accuracy`
- есть улучшение на critical buckets
- fallback rate падает
- dangling target rate не растёт
- hard runtime prompts не ухудшились

## A/B protocol

- одинаковый prompt set
- одинаковый runtime prompt format
- одинаковый accept/merge policy
- логирование raw outputs

## Current Snapshot: Iter3.1 Prep (`seed42`, 2026-04-21)

Ниже зафиксирован человекочитаемый вывод по последнему честному prep-eval для:
- `dataset_v7`
- `dataset_v7_orpo_iter1`
- `dataset_v7_orpo_iter2`

Источник артефактов:
- [scientific_report.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/benchmark_results_seed42/aggregate/scientific_report.md)
- [runs_scored.csv](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/benchmark_results_seed42/aggregate/runs_scored.csv)
- [pairwise_compare.csv](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/benchmark_results_seed42/aggregate/pairwise_compare.csv)
- [model_slice_summary.csv](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/iter3_1_prep_seed42/benchmark_results_seed42/aggregate/model_slice_summary.csv)

### Короткий вывод

- `dataset_v7` остаётся лучшей моделью по structural/raw stability.
- `dataset_v7_orpo_iter1` и особенно `dataset_v7_orpo_iter2` дают ощутимый semantic gain.
- `dataset_v7_orpo_iter2` сейчас лучший по смысловым метрикам, но этот выигрыш всё ещё достигается ценой деградации raw structure.
- Из-за этого честный `iter3.1` transfer-first corpus пока не проходит quality gate и не должен идти в train как есть.

### Что показал `model_only` slice

#### `dataset_v7`

Сильные стороны:
- лучший `json_valid_rate`: `0.9809`
- лучший `exact_marked_object_id_accuracy`: `1.0000`
- лучший `ordinal_actor_binding_accuracy`: `0.9722`

Слабые стороны:
- слабый `target_resolution_accuracy`: `0.0564`
- слабый `chronology_phase_accuracy`: `0.0420`
- слабый `case_strict_success_rate`: `0.0191`

Интерпретация:
- `dataset_v7` хорошо держит форму ответа и привязки сущностей,
- но часто недособирает multi-beat semantics и chronology.

#### `dataset_v7_orpo_iter1`

Относительно `dataset_v7`:
- `target_resolution_accuracy` вырос: `0.0940` против `0.0564`
- `chronology_phase_accuracy` вырос: `0.0725` против `0.0420`
- `case_strict_success_rate` вырос: `0.0267` против `0.0191`

Цена улучшения:
- `json_valid_rate` просел до `0.9656`
- `schema_valid_rate` просел до `0.9618`
- `ordinal_actor_binding_accuracy` просел до `0.9514`

Интерпретация:
- `iter1` уже переносит часть нужной семантики,
- но начинает терять ту structural discipline, за которую ценен `dataset_v7`.

#### `dataset_v7_orpo_iter2`

Относительно `dataset_v7`:
- `target_resolution_accuracy` вырос до `0.1128`
- `chronology_phase_accuracy` вырос до `0.0840`
- `action_recall` вырос до `0.1066`
- `case_strict_success_rate` вырос до `0.0344`

Но structural regressions усилились:
- `json_valid_rate` упал до `0.9504`
- `schema_valid_rate` упал до `0.9466`
- `exact_marked_object_id_accuracy` упал до `0.9881`
- `ordinal_actor_binding_accuracy` упал до `0.9340`

Интерпретация:
- `iter2` сейчас лучший semantic candidate,
- но raw-output quality всё ещё недостаточно стабильна, чтобы строить на ней честный transfer-first iter3 без очень тяжёлого gold fallback.

### Pairwise comparison по-человечески

#### `iter1` vs `v7`

- побед у `iter1`: `19`
- побед у `v7`: `7`
- статистически это выглядит как реальное улучшение (`p ≈ 0.029`)

Что именно улучшилось:
- chronology
- target resolution

Что ухудшилось:
- `json_valid_rate`
- `ordinal_actor_binding_accuracy`

Итог:
- `iter1` лучше по смыслу, но не безусловно лучше как production-замена `v7`.

#### `iter2` vs `v7`

- побед у `iter2`: `31`
- побед у `v7`: `14`
- improvement ещё заметнее (`p ≈ 0.016`)

Что улучшилось:
- chronology
- target resolution
- strict success

Что ухудшилось:
- `json_valid_rate`
- `exact_marked_object_id_accuracy`
- `ordinal_actor_binding_accuracy`

Итог:
- `iter2` самый сильный semantic improvement относительно `v7`,
- но этот improvement всё ещё не бесплатный и приходит с заметным structural drift.

#### `iter2` vs `iter1`

- побед у `iter2`: `18`
- побед у `iter1`: `13`
- статистически это уже не выглядит как уверенный отрыв (`p ≈ 0.47`)

Итог:
- `iter2` выглядит как более сильный semantic вариант,
- но его преимущество над `iter1` уже не настолько чистое и однозначное.

### Почему мы не пошли сразу в `iter3` train

После свежего prep-export был собран honest `iter3.1` corpus build attempt.

Он **не прошёл gate**:
- `gold_chosen_share_overall = 0.948`
- `model_chosen_share_overall = 0.052`

Это означает:
- модельные `model_only` outputs всё ещё слишком редко проходят canonical/family integrity checks,
- и corpus builder вынужден почти полностью опираться на `gold_target_json`,
- а значит такой `iter3` train был бы нечестным и маскировал бы проблему вместо её решения.

### Практический вывод

На текущем шаге лучший честный вывод такой:
- `dataset_v7` — лучший structural baseline
- `dataset_v7_orpo_iter2` — лучший semantic candidate
- `best of both worlds` ещё не достигнут

Следующий шаг должен улучшать не только preference-corpus, а именно raw generation contract:
- prompt / decoding / output-shape discipline
- family-specific integrity на `open_then_pick_up`, `give_to_third_actor`, `ordinal`, `three_beat`
- и только потом новый prep-export и новый `iter3` corpus build

Иначе мы просто ещё раз обучим модель на gold-heavy surrogate вместо реального transfer signal.

## Current Snapshot: V8 Hotfix Benchmark (`seed42`, 2026-04-22)

Ниже зафиксирован человекочитаемый вывод по post-hotfix benchmark для:
- `dataset_v8_plan_sft`
- `dataset_v8_plan_orpo_iter1`

Источник артефактов:
- [scientific_report.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/v8_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md)
- [runs_scored.csv](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/v8_0_seed42/benchmark_results_seed42/aggregate/runs_scored.csv)
- [pairwise_compare.csv](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/v8_0_seed42/benchmark_results_seed42/aggregate/pairwise_compare.csv)
- [v8_plan_slice_summary.csv](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/v8_0_seed42/benchmark_results_seed42/aggregate/v8_plan_slice_summary.csv)
- [slice_reason_codes.csv](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runs/sgv7_full_20260417/v8_0_seed42/benchmark_results_seed42/aggregate/slice_reason_codes.csv)

### Короткий вывод

- `dataset_v8_plan_sft` и `dataset_v8_plan_orpo_iter1` после hotfix больше не выглядят как структурно сломанный эксперимент.
- `dataset_v8_plan_orpo_iter1` удерживает `json_valid_rate` на уровне `dataset_v7_orpo_iter2`, но при этом сильно выигрывает по semantic метрикам.
- Главная недожатая зона `v8` теперь уже не compile-path, а `ordinal_actor_binding_accuracy` и общая plan integrity.

### Что показал `model_only` slice

#### `dataset_v8_plan_sft`

Сильные стороны:
- `json_valid_rate`: `0.9466`
- `target_resolution_accuracy`: `0.4684`
- `chronology_phase_accuracy`: `0.1412`
- `case_strict_success_rate`: `0.0954`
- `runtime_fallback_rate`: `0.7099`

Слабые стороны:
- `ordinal_actor_binding_accuracy`: `0.8403`
- structural binding всё ещё слабее `dataset_v7`/`dataset_v7_orpo_iter2`

Интерпретация:
- уже базовый `plan_sft` приносит большой semantic gain,
- но symbolic actor binding и integrity между beats/actions всё ещё требуют отдельного дожима.

#### `dataset_v8_plan_orpo_iter1`

Относительно `dataset_v7_orpo_iter2`:
- `json_valid_rate` удержан на том же уровне: `0.9504` против `0.9504`
- `target_resolution_accuracy` вырос до `0.4803` против `0.1778`
- `chronology_phase_accuracy` вырос до `0.1412` против `0.0840`
- `case_strict_success_rate` вырос до `0.1031` против `0.0344`
- `runtime_fallback_rate` снизился до `0.7137` против `0.8435`

Оставшаяся цена улучшения:
- `ordinal_actor_binding_accuracy` всё ещё ниже: `0.8385` против `0.9340`

Интерпретация:
- после hotfix `v8_plan_orpo_iter1` уже выглядит как реальный общий winner относительно `dataset_v7_orpo_iter2`,
- но это пока не `best of both worlds`, потому что ordinal-binding discipline ещё не дотянута до `v7`-уровня.

### Pairwise comparison по-человечески

#### `v8_plan_sft` vs `v7`

- побед у `v8_plan_sft`: `163`
- побед у `v7`: `72`
- improvement выглядит уверенным (`p ≈ 2.77e-09`)

Итог:
- даже без ORPO `v8` уже превосходит чистый structural baseline на общем benchmark score.

#### `v8_plan_sft` vs `v7_orpo_iter2`

- побед у `v8_plan_sft`: `150`
- побед у `v7_orpo_iter2`: `83`
- improvement выглядит уверенным (`p ≈ 1.35e-05`)

Итог:
- `v8_plan_sft` уже обходит лучший `v7` semantic candidate, хотя binding discipline ещё не идеальна.

#### `v8_plan_orpo_iter1` vs `v7_orpo_iter2`

- побед у `v8_plan_orpo_iter1`: `151`
- побед у `v7_orpo_iter2`: `82`
- improvement выглядит уверенным (`p ≈ 7.26e-06`)

Что улучшилось:
- target resolution
- chronology
- strict success
- fallback rate

Что всё ещё хуже:
- `ordinal_actor_binding_accuracy`

Итог:
- после hotfix `v8_plan_orpo_iter1` становится лучшим общим кандидатом в benchmark-сравнении с `v7_orpo_iter2`.

#### `v8_plan_orpo_iter1` vs `v8_plan_sft`

- побед у `v8_plan_orpo_iter1`: `9`
- побед у `v8_plan_sft`: `12`
- статистически разницы нет (`p ≈ 0.664`)

Итог:
- первый ORPO pass почти не меняет итоговую картину поверх `plan_sft`,
- значит следующий шаг должен идти не в ещё один preference-cycle, а в точечный fix `ordinal` и plan integrity.

### Что показал `local_plan_raw` slice

Для `dataset_v8_plan_orpo_iter1`:
- `plan_parse_rate = 0.9580`
- `plan_reference_binding_accuracy = 0.7595`
- `plan_beat_integrity_accuracy = 0.2786`

Интерпретация:
- planner уже почти всегда выдаёт parseable IR,
- но reference binding и целостность multi-beat плана пока остаются главным bottleneck.

### Compile-note diagnostics

Для `dataset_v8_plan_orpo_iter1`:
- `v8.targetless_action_downgraded`: `58`
- `v8.invalid_spatial_relation_skipped`: `11`

Для `dataset_v8_plan_sft`:
- `v8.targetless_action_downgraded`: `57`
- `v8.invalid_spatial_relation_skipped`: `10`

Практический смысл:
- hotfix убрал лишние compile-null провалы,
- но сами note counts показывают, где именно нужно улучшать planner и training contract в `v8.1`.

### Практический вывод

На текущем шаге честный вывод уже другой, чем в pre-hotfix snapshot:
- `dataset_v7` — всё ещё лучший structural baseline по entity binding discipline
- `dataset_v7_orpo_iter2` — лучший `v7` semantic candidate
- `dataset_v8_plan_orpo_iter1` — лучший общий candidate после hotfix, потому что держит structure на уровне `iter2`, но заметно сильнее по semantics

Следующий шаг должен улучшать:
- `ordinal_actor_binding_accuracy`
- `plan_reference_binding_accuracy`
- `plan_beat_integrity_accuracy`

То есть `v8.1` должен дожимать уже не compile-path, а binding/integrity слой самого `ScenePlanIR`.

## Что вынести отдельному агенту

- metric definitions
- eval harness
- release thresholds
- A/B reporting format
