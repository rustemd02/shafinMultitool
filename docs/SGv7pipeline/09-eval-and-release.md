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

## Что вынести отдельному агенту

- metric definitions
- eval harness
- release thresholds
- A/B reporting format
