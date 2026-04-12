# 08. Training Plan

## Цель

Обучить `qwen 1.5B` так, чтобы она стабильно воспроизводила canonical JSON без схлопывания.

## Базовый принцип

Для `1.5B` выигрывает curriculum + canonical consistency, а не просто большой датасет.

## Training phases

### Phase 1. Core SFT

Данные:
- только `core`

Цель:
- научить базовую структуру JSON
- научить стабильные `beats`
- научить object grounding

### Phase 2. Core + Hard Mix

Данные:
- `core`
- `hard`

Цель:
- ввести сложные формы без слома базовой структуры

### Phase 3. Hard Oversampling

Данные:
- hard buckets x2-x3
- real corrected samples

Цель:
- добить runtime failure patterns

### Phase 4. Optional Preference Tuning

Данные:
- `good_json` vs `bad_json`

Цель:
- уменьшить типичные деградации:
  - `walk/talk collapse`
  - object loss
  - beat collapse

## Recommended constraints for 1.5B

- учить на full base model, не на quantized
- ограничивать effective complexity samples
- не раздувать prompt без необходимости
- не давать слишком много optional variability

## Formal Complexity Budget

Ниже стартовый budget для `SG v7`, который должен проверяться автоматически.

### Core budget

- `actor_count <= 2`
- `object_count <= 1`
- `beat_count <= 2`
- `action_count <= 4`
- `source_text_token_count <= 40`
- `target_json_token_count <= 220`
- `full_sequence_token_count <= 420`

### Hard budget

- `actor_count <= 3`
- `object_count <= 2`
- `beat_count <= 4`
- `action_count <= 6`
- `source_text_token_count <= 64`
- `target_json_token_count <= 320`
- `full_sequence_token_count <= 560`

### Reject-by-budget

Sample должен автоматически исключаться из standard SFT, если:
- превышает hard budget
- использует слишком много optional fields без product-необходимости
- сериализованный target заметно длиннее среднего для своего pattern family

## Phase-Level Complexity Policy

### Phase 1

- только `core`
- только `S/M`
- без `L`
- без `tier_c_reviewed_merge`

### Phase 2

- `core + hard`
- `L` не более 10-15%
- `tier_b_deterministic_canonical` допустим

### Phase 3

- hard oversampling
- `real corrected`
- `tier_c_reviewed_merge` допустим только в контролируемой доле

## Serialization Discipline

Нужно отдельно мониторить:
- среднюю длину source в токенах
- среднюю длину target JSON в токенах
- долю samples с optional fields
- долю `L` samples в каждом phase

Если эти значения растут без роста eval metrics, это почти наверняка data drift, а не улучшение.

## What to monitor during training

- train loss
- val loss
- structured exact-match subset
- marked object recall
- beat accuracy
- target integrity
- exact marked-object id accuracy
- ordinal actor binding accuracy
- target resolution accuracy
- average target length

## Warning signs

- loss падает, а beat accuracy не растёт
- model outputs get shorter
- object recall падает при росте hard samples
- described_action деградирует в talk

## Когда переобучать с нуля, а когда дообучать

Дообучать текущую модель, если:
- проблемы локальны
- core structure уже держится

Стартовать заново от base + new pipeline, если:
- после двух циклов data refresh сохраняется шаблонный collapse
- runtime failures не двигаются по critical buckets

## Что вынести отдельному агенту

- phase schedule
- curriculum config
- hard oversampling policy
- preference tuning feasibility
