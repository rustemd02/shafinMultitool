# 07. Dataset Assembly

## Цель

Собрать не просто общий JSONL, а несколько целевых наборов под разные training phases.

## Наборы данных

### 1. Core SFT

Содержит:
- простые и средние cases
- высокую canonical consistency
- низкую ambiguity

Объём:
- 12k-18k samples

### 2. Hard SFT

Содержит:
- morphology stress
- marked object edge cases
- ordinal edge cases
- unsupported action patterns
- multi-beat hard cases

Объём:
- 2k-4k samples

### 3. Real Corrected

Содержит:
- реальные user prompts
- corrected target JSON
- реальные reject/merge patterns

Объём:
- 500-1500 samples

Admission policy:
- каждый sample обязан иметь provenance tier
- неизвестное происхождение corrected target недопустимо
- `tier_a_human_gold` и `tier_b_deterministic_canonical` можно включать в SFT
- `tier_c_reviewed_merge` по умолчанию идёт в hard/reviewed bucket
- `tier_d_auto_repair_only` не должен попадать в SFT как gold

### 4. Preference Pairs

Содержит:
- source
- good_json
- bad_json
- optional reject reason

Объём:
- 1k-2k pairs

## Split strategy

Нельзя делать purely random split.

Нужно:
- stratify by semantic pattern
- stratify by hard bucket
- выносить family-level patterns в val/test

## Bucket distributions

Рекомендуемый `core`:
- 25% movement
- 20% marked object grounding
- 15% ordinal references
- 15% unsupported actions
- 10% mixed dialogue+action
- 10% multi-beat
- 5% ambiguity discipline

Рекомендуемый `hard`:
- 30% morphology
- 25% multi-beat grounding
- 20% ordinal role flips
- 15% same-type markers
- 10% noisy user prompts

## Dedup strategy

Нужно дедуплицировать:
- identical graphs
- near-identical source variants
- pattern clones с незначительной заменой слов

## Что хранить в metadata

У каждого sample:
- `sample_id`
- `pattern_name`
- `difficulty_bucket`
- `complexity_class`
- `source_variant`
- `augmentation_flags`
- `graph_hash`
- `validation_status`
- `correction_tier`
- `gold_source`
- `train_eligibility`
- `contract_version`
- `source_text_token_count`
- `target_json_token_count`

## Complexity Budget Metadata

Для каждого sample нужно хранить budget-related поля:
- `actor_count`
- `object_count`
- `beat_count`
- `action_count`
- `source_text_token_count`
- `target_json_token_count`
- `full_sequence_token_count`

Без этих полей нельзя контролировать, не учим ли мы `1.5B` на слишком тяжёлых samples как на норме.

## Что вынести отдельному агенту

- split builder
- dedup strategy
- metadata contract
- bucket balancing logic
