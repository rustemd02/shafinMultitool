# 18. Runtime And Training Contract

## Цель

Зафиксировать один точный contract, который одновременно определяет:
- runtime prompt format
- training prompt format
- canonical target JSON serialization
- grammar/decoding constraints
- compatibility c `SceneScript`

Этот документ нужен, чтобы не допустить train/inference drift.

## Почему это отдельный артефакт

Для `qwen 1.5B` даже небольшой mismatch между:
- train prompt
- runtime prompt
- grammar
- field optionality
- serialization order

может приводить к:
- minimal valid JSON collapse
- потере `marked objects`
- потере `beats`
- ошибкам в `first/second`
- деградации unsupported actions

Поэтому `SG v7` должен иметь не только data pipeline, но и отдельный source of truth для exact contract.

## Scope

Contract покрывает:
- chat template
- system instruction block
- user prompt sections
- structured marked-object section
- target JSON canonicalization
- grammar/GBNF
- decoding settings
- stop conditions
- normalization rules

Contract не покрывает:
- training hyperparameters
- sampling distributions
- release thresholds

## Owned Artifacts

Должны существовать versioned артефакты:
- `runtime_prompt_template`
- `training_prompt_template`
- `marked_object_section_template`
- `canonical_json_serializer_spec`
- `gbnf_or_schema_constraint_spec`
- `decoding_config`
- `contract_fixtures.jsonl`

Для `SG v7` executable projection layer тоже должен существовать как код, а не только как prose.
Текущая canonical точка входа: [generate_dataset_v7.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v7.py).
Serializer source of truth: [cir_serializer.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/cir_contract/contracts/cir_serializer.py).

Если эти артефакты физически лежат в разных файлах, они всё равно считаются одним логическим contract.

## Non-Negotiable Invariants

- train и runtime используют один и тот же semantic instruction set
- section order в prompt фиксирован
- marked objects передаются как структурный список, а не как свободный prose
- exact `object_marked_<SHORTID>` должен быть допустимым target id и в train, и в runtime
- ordinal mapping `first/second` должен быть одинаково описан в train и runtime
- unsupported actions должны сериализоваться одинаково в train и runtime
- canonical JSON использует стабильный field order
- optional поля либо всегда опускаются, либо всегда сериализуются по одному правилу
- grammar не должна допускать runtime-only или train-only формы
- изменение contract требует новой версии eval и проверки на drift

## Prompt Structure

Рекомендуемый фиксированный порядок секций:
1. task instruction
2. output contract
3. action/object constraints
4. marked objects
5. source text

Запрещено:
- менять порядок секций между train и runtime
- использовать разные описания одних и тех же action semantics
- давать train-only примеры, которых нет в runtime contract

## Marked Object Section Contract

Marked objects должны передаваться как структурный блок.

Минимально обязательные поля:
- `id`
- `name`
- `type`
- `mentioned_aliases` при необходимости

Инварианты:
- если source text упоминает размеченный объект, модель должна переиспользовать его exact `id`
- нельзя создавать новый object вместо совпавшего marked object
- same-type marked objects различаются по `id`, а не только по `type`

## Canonical JSON Serialization Contract

Нужно явно зафиксировать:
- field order на верхнем уровне
- field order внутри `actors`, `objects`, `beats`, `actions`
- политику `null`
- политику empty arrays
- правила для optional camera fields
- правила для optional actor names

Рекомендуемое правило:
- если optional поле семантически не нужно, оно опускается
- если поле оставлено, оно должно иметь одно canonical representation

Для `SG v7` canonical path это значит:
- `sceneHeading`, `locationName`, `interiorExterior`, `timeOfDay` не входят в canonical target JSON
- `camera` и `minDuration` сериализуются только по policy `emit_if_present_else_omit`
- runtime может хранить дополнительные scene-state поля отдельно, но они не должны становиться частью canonical train/runtime JSON contract

## Grammar And Decoding Contract

Нужно versioned-образом зафиксировать:
- точный grammar/GBNF contract
- допустимые enum values
- stop tokens
- temperature/top_p/repetition settings для eval и runtime
- max output tokens
- repair policy boundary

Важно:
- grammar должна соответствовать dataset contract, а не подталкивать модель к "самому короткому валидному JSON"
- runtime repair не должен silently менять semantics, которых не было в исходном output

## Normalization Contract

До передачи в модель должно быть одинаково определено:
- trimming
- newline policy
- whitespace collapse policy
- Unicode normalization policy для русского текста
- spelling normalization policy только там, где она безопасна

После генерации должно быть одинаково определено:
- JSON cleanup boundary
- допустимые repairs
- canonical re-serialization

## Fixture-Based Validation

У contract должен быть минимальный fixture set:
- 10-20 frozen prompts
- 10-20 frozen expected targets
- 5-10 cases с marked objects
- 5-10 cases с ordinal references
- 5-10 cases с unsupported actions
- 5-10 multi-beat cases

Эти fixtures используются для:
- contract regression checks
- dataset serializer checks
- runtime prompt regression checks
- grammar compatibility checks

## Change Policy

Любое изменение в одном из пунктов ниже требует contract review:
- prompt wording
- prompt section order
- marked object section format
- grammar/GBNF
- canonical serializer
- enum set
- optional field policy

Если contract меняется, нужно:
1. увеличить `contract_version`
2. прогнать frozen fixtures
3. перепроверить dataset generation compatibility
4. перепроверить offline eval comparability

## Ownership

У этого contract должен быть явный owner-track в `SG v7`:
- design owner
- implementation owner
- verification owner

Этот трек нельзя считать "подзадачей по ходу дела". Он блокирует:
- dataset generation
- training
- runtime A/B

## Minimum Definition Of Done

Contract считается готовым, когда:
- существует один source-of-truth document
- существует список versioned artifacts
- есть frozen fixtures
- есть mismatch checklist для train vs runtime
- любой агент может понять, что именно нужно менять при drift
