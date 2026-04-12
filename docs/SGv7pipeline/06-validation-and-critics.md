# 06. Validation And Critics

## Цель

Пропускать в train только те samples, которые:
- schema-valid
- graph-consistent
- semantic-consistent
- recoverable для 1.5B

## Слой 0. Provenance validation

Проверяет:
- указан ли `correction_tier`
- понятен ли источник `corrected_target_json`
- известно ли, кто или что породило final target
- разрешён ли этот tier для выбранного train split

Sample не должен попадать в train как "gold", если provenance неизвестен.

## Слой 1. Schema validation

Проверяет:
- все required fields присутствуют
- ids валидны
- enum values разрешены
- target formats корректны

## Слой 2. Graph consistency validation

Проверяет:
- все `actorId` существуют
- все `target` существуют
- `holdingObject` валиден
- `talk` и `described_action` obey semantic rules
- beat ids и action ids уникальны

## Слой 3. Product semantics validation

Проверяет:
- marked object ids сохранены
- `первый/второй` мапятся корректно
- unsupported actions мапятся в `described_action`
- same-type markers не схлопнуты

## Слой 4. Recoverability validation

Проверяет:
- можно ли по source reasonably восстановить данный JSON
- не слишком ли много beats для такого source
- не слишком ли много actions
- нет ли нескольких равноправных трактовок

## LLM semantic critic

Критик получает:
- source
- canonical graph summary
- список must-have semantics
- список must-not-have semantics

Он должен ответить:
- `pass`
- `soft_fail`
- `hard_fail`

## Правила reject

Sample отклоняется, если:
- потерян marked object
- потерян ordinal reference
- схлопнулась chronology
- появился новый объект/новое действие
- диалог появился там, где его не было
- source перестал выражать critical unsupported action

## Правила manual review

В review bucket идут:
- borderline under-parsed samples
- сложные multi-beat ambiguous chunks
- samples с несколькими marked objects одного типа
- `tier_c_reviewed_merge`, ещё не подтверждённые для train
- все `tier_d_auto_repair_only`, претендующие на повышение trust tier

## Training Eligibility Policy

- `tier_a_human_gold` -> direct train eligible
- `tier_b_deterministic_canonical` -> train eligible после strict validation
- `tier_c_reviewed_merge` -> review required, потом только hard/preference
- `tier_d_auto_repair_only` -> не direct train eligible

## Что вынести отдельному агенту

- реализация validators
- critic prompt
- reject taxonomy
- review bucket policy
