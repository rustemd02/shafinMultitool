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

## Что вынести отдельному агенту

- metric definitions
- eval harness
- release thresholds
- A/B reporting format
