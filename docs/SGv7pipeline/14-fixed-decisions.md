# 14. Fixed Decisions

Этот документ фиксирует решения, которые для `SG v7` считаются уже принятыми.

Его цель:
- не заставлять агентов повторно обсуждать уже выбранные направления
- уменьшить архитектурный drift
- ускорить реализацию

## Product Scope

- целевая задача: локальный Scene Generator JSON parsing
- целевая модель: `qwen 1.5B`
- основной runtime-кейс: короткие и средние русские пользовательские описания сцены
- основной target format: `SceneScript`

## Model Constraints

- модель имеет ограниченную capacity
- модель склонна к under-parsing и минимальным валидным ответам
- модель чувствительна к train/inference mismatch
- модель не должна обучаться на избыточной optional complexity как на норме

## Data Strategy

- `SG v7` строится как `graph-first pipeline`
- canonical JSON должен рождаться программно, а не быть главным образом teacher-generated
- `gpt-5.4-nano` используется прежде всего как paraphraser, augmenter и critic helper
- `nano` не должен быть единственным источником ground-truth JSON для hard-cases
- real runtime failures должны попадать обратно в data pipeline

## Training Strategy

- train format должен совпадать с runtime prompt format
- exact runtime/train contract должен быть versioned отдельным source-of-truth артефактом
- один и тот же смысл должен иметь один canonical target JSON
- сначала `core SFT`, потом `hard SFT`, потом optional preference tuning
- complexity budget для `1.5B` должен соблюдаться как системное ограничение

## Runtime Contract

- runtime schema остаётся совместимой с текущим `SceneScript`
- prompt section order и serializer policy не должны расходиться между train и runtime
- `marked objects` должны передаваться как структурные constraints
- exact `object_marked_*` identity должна уважаться end-to-end
- `first/second` должны мапиться детерминированно
- unsupported actions должны уходить в `described_action`, а не исчезать

## Corrected Sample Provenance

Реальные corrected samples должны иметь explicit provenance tier:
- `tier_a_human_gold` - ручная правка или ручное подтверждение gold target
- `tier_b_deterministic_canonical` - target получен детерминированным canonicalizer-ом из известного good structured result
- `tier_c_reviewed_merge` - merge/repair прошёл review и признан достаточным для hard bucket
- `tier_d_auto_repair_only` - только автоматический repair без review

Правило использования:
- `tier_a_human_gold` можно использовать в любом train split
- `tier_b_deterministic_canonical` можно использовать в `core` и `hard`, если sample проходит strict validators
- `tier_c_reviewed_merge` можно использовать только в `hard` или preference data
- `tier_d_auto_repair_only` нельзя использовать как direct SFT gold; он годится только для mining, review queue или bad-example pools

## Canonical Mapping Rules

- `курит`, `закуривает`, `начинает курить` -> canonical `described_action`
- `первый` -> `actor_1`
- `второй` -> `actor_2`
- marked object id -> `object_marked_<SHORTID>`
- same-type marked objects не должны схлопываться по `type`

## Complexity Budget

Для `qwen 1.5B` нужно держать explicit budget не только по graph structure, но и по serialization:
- в `core` преобладают короткие и средние samples
- длинные multi-beat samples должны быть редким hard-case, а не новой нормой
- optional поля не должны заполняться "для красоты"
- target JSON не должен раздуваться лишними camera/object/action деталями без product-необходимости
- любой budget должен быть выражен в сериализуемых ограничениях: actors/objects/beats/actions/source length/target length

## What Agents Should Not Reopen

Агенты не должны без отдельного запроса пересматривать:
- выбор `qwen 1.5B` как target local model
- graph-first подход
- необходимость canonical JSON
- необходимость отдельного runtime/train contract
- необходимость runtime feedback loop
- необходимость strict validation stack

## What Can Still Be Proposed

Агенты могут предлагать:
- детали intermediate graph schema
- состав pattern library
- prompt wording для paraphrasing/critics
- validator implementation details
- training schedule details
- eval thresholds

## Rule Of Thumb

Если агент предлагает решение, противоречащее этому файлу, он должен:
- явно это отметить
- объяснить, почему deviation нужен
- не считать deviation принятой новой нормой автоматически
