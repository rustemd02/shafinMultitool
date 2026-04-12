# 19. Canonical Intermediate Representation For SG v7

## Цель

Зафиксировать `canonical intermediate representation` (далее `CIR`) между:
- `pattern generator`
- `final SceneScript / SFT JSON serializer`

Этот contract нужен, чтобы `SG v7` строил target JSON программно и детерминированно, а не через свободную teacher-генерацию.

Главный принцип:
- `CIR` хранит смысл сцены в форме, удобной для graph generation и validation
- final `SceneScript` получается из `CIR` детерминированным serializer-ом
- всё, что критично для runtime semantics, должно быть выражено явно, а не подразумеваться

## Design Goals

`CIR` должен:
- уменьшать ambiguity для `qwen 1.5B`
- хорошо поддерживать `marked objects`
- хорошо поддерживать `ordinal references`
- хорошо поддерживать `described_action`
- хорошо поддерживать `beats`
- отделять runtime-compatible fields от внутренних pipeline metadata
- позволять реализовать graph generator без домысливания

## Non-Goals

`CIR` не должен:
- расширять runtime schema без необходимости
- тащить в canonical слой произвольную prose-интерпретацию
- хранить teacher-authored JSON как source of truth
- делать optional runtime-поля обязательными "для красоты"

## Placement In Pipeline

```text
Pattern Library
  -> CIR record
  -> source generation / augmentation / critics
  -> deterministic SceneScript serializer
  -> final SFT JSON
```

## Canonical Unit

Одна запись `CIR` = один canonical semantic scene sample до paraphrase stage.

Рекомендуемый формат хранения: `JSONL`, одна запись на строку.

## Executable Artifacts

Machine-readable contract и проверки для `sg_v7_cir_v1`:
- schema: [cir_schema_v1.json](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/cir_contract/contracts/cir_schema_v1.json)
- typed definitions: [cir_types.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/cir_contract/contracts/cir_types.py)
- validator: [cir_validator.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/cir_contract/contracts/cir_validator.py)
- serializer: [cir_serializer.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/cir_contract/contracts/cir_serializer.py)
- CLI validate command: [validate_cir_contract.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/cir_contract/scripts/validate_cir_contract.py)
- executable examples: `docs/SGv7pipeline/cir_contract/contracts/examples/*.json`
- tests: [test_cir_contract.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/cir_contract/tests/test_cir_contract.py)
- SG v7 dataset entrypoint: [generate_dataset_v7.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v7.py)

## Top-Level Record Schema

```json
{
  "cir_version": "sg_v7_cir_v1",
  "contract_version": "sg_v7_contract_v1",
  "sample_id": "stop_near_marked_object_then_first_described_action__base__s10421__c09bd123",
  "source_variant_key": "base",
  "pattern_name": "stop_near_marked_object_then_first_described_action",
  "difficulty_bucket": "hard",
  "complexity_class": "M",
  "graph_seed": 10421,
  "scene_graph": { ... },
  "semantic_tags": [
    "movement",
    "marked_object",
    "ordinal_reference",
    "described_action",
    "multi_beat"
  ],
  "determinism": { ... },
  "budgets": { ... },
  "runtime_projection": { ... },
  "internal_metadata": { ... }
}
```

## Required Top-Level Fields

### `cir_version: string`
Версия схемы intermediate representation.

### `contract_version: string`
Версия runtime/train contract, с которым совместим serializer.

### `sample_id: string`
Стабильный id sample.

Правило:
- должен быть детерминированно вычислим из `pattern_name + source_variant_key + graph_seed + structural hash`

`source_variant_key` — это обязательный deterministic label graph-экземпляра до paraphrase stage.

Разрешённые значения:
- `base`
- `ordinal_stress`
- `morphology_stress`
- `same_type_marker_stress`
- `dialogue_mix`

Правила:
- `source_variant_key` выбирается из фиксированного enum, а не придумывается свободным текстом
- если record не является специальным stress-variant, используется `base`
- `sample_id` рекомендуется сериализовать как `<pattern_name>__<source_variant_key>__s<graph_seed>__<short_hash>`

### `source_variant_key: string`
Явное top-level поле record-а, фиксирующее variant family до source/paraphrase stage.

Разрешённые значения:
- `base`
- `ordinal_stress`
- `morphology_stress`
- `same_type_marker_stress`
- `dialogue_mix`

Правила:
- поле обязательное и persisted
- не является скрытым derivation-only значением
- должно совпадать с variant family, которая использовалась при генерации graph instance

### `pattern_name: string`
Имя semantic pattern из pattern library.

### `difficulty_bucket: "core" | "hard"`
Bucket для dataset assembly.

### `complexity_class: "S" | "M" | "L"`
Сложностной класс по правилам `03-graph-generation.md`.

### `graph_seed: integer`
Seed, которым был получен graph instance.

### `scene_graph: object`
Каноническое semantic представление сцены.

### `semantic_tags: string[]`
Небольшой нормализованный список тегов для stratification и hard-bucket routing.

### `determinism: object`
Явно фиксирует, какие части записи должны быть воспроизводимыми 1-в-1.

Обязательная схема:

```json
{
  "id_policy": "canonical_v1",
  "ordering_policy": "stable_v1",
  "serializer": "deterministic_scene_script_v1",
  "phase_policy": "phase_enum_v1",
  "described_action_policy": "described_action_v1"
}
```

Обязательные поля:
- `id_policy`
- `ordering_policy`
- `serializer`
- `phase_policy`
- `described_action_policy`

Правила:
- все значения берутся из фиксированного string-enum
- для `sg_v7_cir_v1` все 5 полей обязательны и должны иметь ровно указанные значения, если не введена новая версия CIR

### `budgets: object`
Сериализуемые complexity counters.

Обязательная схема:

```json
{
  "actor_count": 2,
  "object_count": 1,
  "beat_count": 3,
  "action_count": 5,
  "relation_count": 2
}
```

Обязательные поля:
- `actor_count`
- `object_count`
- `beat_count`
- `action_count`
- `relation_count`

Правила:
- все значения non-negative integers
- значения вычисляются из `scene_graph`, а не заполняются вручную
- `complexity_class` выводится из этих counts по deterministic rule

### `runtime_projection: object`
Явное описание того, какие части `scene_graph` обязаны попасть в final runtime `SceneScript`.

Обязательная схема:

```json
{
  "target_schema": "SceneScript",
  "field_casing": "camelCase",
  "drop_internal_fields": true,
  "fill_original_description_from_source_variant": true,
  "described_action_source_text_policy": "canonical_text_to_sourceText",
  "top_level_optional_policy": "omit_all",
  "beat_optional_policy": "preserve_if_present_else_omit"
}
```

Обязательные поля:
- `target_schema`
- `field_casing`
- `drop_internal_fields`
- `fill_original_description_from_source_variant`
- `described_action_source_text_policy`
- `top_level_optional_policy`
- `beat_optional_policy`

Правила:
- `target_schema` для `sg_v7_cir_v1` всегда `SceneScript`
- `field_casing` для runtime serializer всегда `camelCase`
- `drop_internal_fields` всегда `true`
- `fill_original_description_from_source_variant` всегда `true`
- `described_action_source_text_policy` для `sg_v7_cir_v1` всегда `canonical_text_to_sourceText`
- `top_level_optional_policy` для `sg_v7_cir_v1` всегда `omit_all`
- `beat_optional_policy` для `sg_v7_cir_v1` всегда `preserve_if_present_else_omit`

## Optional Top-Level Fields

### `internal_metadata: object`
Внутренние служебные данные пайплайна, не попадающие в runtime JSON.

Рекомендуемые поля:
- `notes`
- `generator_name`
- `generator_version`
- `parent_pattern_family`
- `dedup_group`
- `review_status`

## `scene_graph` Schema

```json
{
  "actors": [ ... ],
  "objects": [ ... ],
  "beats": [ ... ],
  "spatial_relations": [ ... ],
  "reference_bindings": { ... },
  "must_preserve": [ ... ]
}
```

## Required `scene_graph` Fields

### `actors: ActorNode[]`
Минимум `1`, максимум по SG v7 budget обычно `3`.

### `objects: ObjectNode[]`
Может быть пустым массивом.

### `beats: BeatNode[]`
Минимум `1`. Один semantic phase = один beat.

### `spatial_relations: SpatialRelationNode[]`
Может быть пустым массивом.

### `reference_bindings: object`
Явные привязки для ordinal, marker и alias-sensitive ссылок.

### `must_preserve: string[]`
Критичные semantic constraints, которые source generator и critics не имеют права терять.

## Optional `scene_graph` Fields

Допустимы только если реально нужны:
- `scene_heading_stub`
- `location_stub`
- `time_stub`

По умолчанию для `SG v7` их лучше не использовать, потому что текущий runtime chunk parsing обычно не зависит от этих полей.

## `ActorNode`

```json
{
  "id": "actor_1",
  "type": "human",
  "name": null,
  "labels": {
    "ordinal": "first",
    "surface_role": null
  }
}
```

### Required fields
- `id`
- `type`
- `labels.ordinal`

### Optional fields
- `name`
- `labels.surface_role`

### Rules
- `id` только `actor_1`, `actor_2`, `actor_3`
- `type` только из runtime `SceneActor.ActorType`
- `name` заполняется только если pattern реально требует собственное имя
- `labels.ordinal` нужен всегда для `actor_1/actor_2`; для `actor_3` можно использовать `third`

## `ObjectNode`

```json
{
  "id": "object_marked_a1b2c3d4",
  "type": "generic",
  "name": "ноутбук",
  "relative_position": "unknown",
  "marker_binding": {
    "kind": "marked",
    "marker_short_id": "a1b2c3d4",
    "source_name": "ноутбук",
    "mentioned_aliases": ["ноутбук", "ноут", "комп"]
  }
}
```

### Required fields
- `id`
- `type`
- `relative_position`
- `marker_binding.kind`

### Optional fields
- `name`
- `marker_binding.marker_short_id`
- `marker_binding.source_name`
- `marker_binding.mentioned_aliases`

### Rules
- marked object: `id = object_marked_<SHORTID>`
- unmarked object: `id = object_1`, `object_2`
- `type` только из runtime `SceneObject.ObjectType`
- `relative_position` должен быть runtime-compatible enum
- `marker_binding.kind` обязателен и равен `marked` или `unmarked`
- для marked object `marker_binding.marker_short_id` обязателен
- для same-type marked objects различение идёт по `id`, а не по `type`

## `BeatNode`

```json
{
  "id": "beat_2",
  "phase": "stop_near_object",
  "actions": [ ... ],
  "camera": null,
  "min_duration": null
}
```

### Required fields
- `id`
- `phase`
- `actions`

### Optional fields
- `camera`
- `min_duration`

### Rules
- `id` только `beat_1`, `beat_2`, ... без пропусков
- `phase` обязателен как внутренний disambiguation label
- `phase` не сериализуется в runtime JSON
- `actions` не пустой массив
- `camera` и `min_duration` используются только если serializer policy решит их сохранять

Разрешённый `phase` enum для `sg_v7_cir_v1`:
- `single_action`
- `dialogue_exchange`
- `toward_each_other`
- `approach_object`
- `stop_near_object`
- `pass_by_object`
- `turn_to_target`
- `pickup_object`
- `putdown_object`
- `open_object`
- `close_object`
- `give_object`
- `first_described_action`
- `second_described_action`
- `third_described_action`
- `small_followup_action`

Правила выбора:
- `phase` выбирается из этого enum, а не из свободного текста
- если beat содержит симметричное движение навстречу, использовать `toward_each_other`
- если ключевой смысл beat-а — остановка у объекта, использовать `stop_near_object`
- если ключевой смысл beat-а — прохождение мимо объекта, использовать `pass_by_object`
- если beat содержит только один не-диалоговый action без более специальной категории, использовать `single_action`
- если beat содержит преимущественно обмен репликами, использовать `dialogue_exchange`

## `ActionNode`

```json
{
  "id": "action_3",
  "actor_id": "actor_1",
  "type": "described_action",
  "target_id": null,
  "direction": null,
  "modifier": null,
  "resulting_pose": "standing",
  "holding_object": null,
  "dialogue": null,
  "described_action": {
    "canonical_text": "начинает курить",
    "fallback_text": "*начинает курить*",
    "source_lemma_hint": "курить"
  },
  "semantics": {
    "is_unsupported_runtime_action": true,
    "must_preserve_in_source": true,
    "chronology_rank": 3
  }
}
```

### Required fields
- `id`
- `actor_id`
- `type`
- `resulting_pose`
- `semantics.chronology_rank`

### Optional fields
- `target_id`
- `direction`
- `modifier`
- `holding_object`
- `dialogue`
- `described_action`
- `semantics.is_unsupported_runtime_action`
- `semantics.must_preserve_in_source`

### Rules
- `id` только `action_1`, `action_2`, ... без пропусков в canonical order
- `type` только из runtime `SceneAction.ActionType`
- `actor_id` обязан ссылаться на существующего actor
- `target_id` обязан ссылаться на существующего actor/object, если указан
- `direction` допустим только для `walk/run/approach/pass_by`
- `modifier` допустим только для `walk/run/approach/pass_by/described_action`
- `dialogue` допустим только для `talk`
- `described_action` обязателен при `type = described_action`
- `described_action.canonical_text` обязателен внутренне
- `described_action.fallback_text` обязателен, потому что уйдёт в runtime `fallbackText`
- `described_action.source_lemma_hint` optional, но желателен для morphology/critic

## `SpatialRelationNode`

```json
{
  "id": "rel_1",
  "subject": "actor_1",
  "relation": "near",
  "object": "object_marked_a1b2c3d4"
}
```

### Required fields
- `id`
- `subject`
- `relation`
- `object`

### Rules
- полностью runtime-compatible по enum и id references
- использовать только если relation явно нужен для object grounding или pass-by/near semantics
- `id` должен иметь префикс `rel_`, чтобы совпадать с текущим executable validator contract

## `reference_bindings` Schema

```json
{
  "ordinal_map": {
    "first": "actor_1",
    "second": "actor_2"
  },
  "marked_object_ids": [
    "object_marked_a1b2c3d4"
  ],
  "alias_to_object_id": {
    "ноутбук": "object_marked_a1b2c3d4",
    "ноут": "object_marked_a1b2c3d4",
    "комп": "object_marked_a1b2c3d4"
  }
}
```

### Required fields
- `ordinal_map`
- `marked_object_ids`
- `alias_to_object_id`

### Rules
- `first -> actor_1`, `second -> actor_2` детерминированы всегда
- если marked objects нет, `marked_object_ids = []`
- `alias_to_object_id` обязателен даже если пустой, чтобы не было implicit rules
- same-type marked objects обязаны иметь disjoint alias coverage или явный ambiguity flag в `must_preserve`

## `must_preserve` Semantics

Это список атомарных инвариантов sample-а, который помогает source generator, critics и validators.

Примеры значений:
- `beat_count=3`
- `must_ground_object:object_marked_a1b2c3d4`
- `ordinal:first->actor_1`
- `ordinal:second->actor_2`
- `action:action_3=described_action`
- `chronology:beat_1<beat_2<beat_3`
- `actor_2_escalates_to_run_in_beat_3`

## Deterministic Parts

Ниже перечислено, что должно быть строго детерминированным.

### 1. ID policy
- actor ids
- object ids
- beat ids
- action ids
- relation ids

Форматы:
- actors: `actor_<N>`
- unmarked objects: `object_<N>`
- marked objects: `object_marked_<SHORTID>`
- beats: `beat_<N>`
- actions: `action_<N>`
- spatial relations: `rel_<N>`

### 2. Enumeration policy
- actor/object/action/relation enum values
- direction values
- pose values
- relative position values

### 3. Beat segmentation
- один semantic phase = один beat
- одинаковый pattern instance должен давать одинаковое число beats
- chronology order beats должен быть фиксирован

### 4. Unsupported action mapping
- одинаковая unsupported semantics всегда мапится в одинаковый `described_action` shape
- `fallback_text` должен быть канонизирован одинаково
- `source_lemma_hint` должен быть стабилен для одного pattern family

### 5. Ordinal mapping
- `first -> actor_1`
- `second -> actor_2`
- без эвристик на этапе serializer

### 6. Marked object identity
- exact `object_marked_<SHORTID>` должен сохраняться end-to-end
- нельзя reassign marked object по одному только `type`

### 7. Serializer projection
Для одного и того же `CIR` deterministic serializer должен выдавать один и тот же final `SceneScript` JSON:
- один и тот же field order
- одна и та же optional-field policy
- одинаковый порядок массивов

## Optional Parts

Следующие части могут быть optional или внутренними:
- `name` у actors/objects
- `camera`
- `min_duration`
- `scene_heading_stub`
- `location_stub`
- `time_stub`
- `internal_metadata`
- `described_action.source_lemma_hint`
- `labels.surface_role`

Правило:
- optional поле разрешено только если его отсутствие не создаёт ambiguity для serializer и critic stack

## Runtime Projection Rules

`CIR` intentionally богаче runtime schema, но только в нескольких местах.

### Должно совпадать с runtime `SceneScript` schema

Следующие поля должны сериализоваться 1-в-1 в runtime-compatible shape:
- `actors[].id`
- `actors[].type`
- `actors[].name`
- `objects[].id`
- `objects[].type`
- `objects[].name`
- `objects[].relative_position -> objects[].relativePosition`
- `beats[].id`
- `beats[].actions[]`
- `beats[].camera`
- `beats[].min_duration -> minDuration`
- `actions[].id`
- `actions[].actor_id -> actorId`
- `actions[].type`
- `actions[].target_id -> target`
- `actions[].direction`
- `actions[].modifier`
- `actions[].resulting_pose -> resultingPose`
- `actions[].holding_object -> holdingObject`
- `actions[].dialogue`
- `described_action.fallback_text -> fallbackText`
- `described_action.canonical_text -> sourceText`
- `spatial_relations[].id`
- `spatial_relations[].subject`
- `spatial_relations[].relation`
- `spatial_relations[].object`

Для `sg_v7_cir_v1` top-level optional policy фиксирована:
- `sceneHeading` всегда опускается
- `locationName` всегда опускается
- `interiorExterior` всегда опускается
- `timeOfDay` всегда опускается

Нормативное уточнение:
- serializer не должен выводить эти ключи даже со значением `null`
- если runtime хранит такую metadata в отдельном state-layer, это считается out-of-band и не является частью canonical SG v7 JSON contract

### Может быть внутренним и не попадать в runtime JSON

Следующие поля нужны только для pipeline:
- `BeatNode.phase`
- `reference_bindings`
- `must_preserve`
- `labels.ordinal`
- `labels.surface_role`
- `marker_binding`
- `described_action.source_lemma_hint`
- `semantics.*`
- `determinism`
- `budgets`
- `internal_metadata`

## Deterministic Serializer Contract

Из `CIR` в final `SceneScript` serializer обязан делать следующее:

1. Переименовать поля в runtime casing.
2. Удалить все внутренние поля.
3. Сериализовать arrays в canonical order:
   - actors по numeric id
   - objects по numeric/marked id stable sort
   - beats по numeric id
   - actions внутри beat по `semantics.chronology_rank`, потом по `id`
4. Заполнить `originalDescription` не из `CIR`, а на downstream stage из source variant.
5. `described_action.canonical_text` всегда и без исключений конвертировать в runtime `sourceText`.
6. Не добавлять новых actions, objects, beats или relations.

Top-level optional fields policy для `sg_v7_cir_v1`:
- `sceneHeading` всегда опускать
- `locationName` всегда опускать
- `interiorExterior` всегда опускать
- `timeOfDay` всегда опускать

Beat-level optional fields policy для `sg_v7_cir_v1`:
- если `camera = null`, поле `camera` опускается
- если `camera` задан, поле сериализуется 1-в-1 в runtime shape
- если `min_duration = null`, поле `minDuration` опускается
- если `min_duration` задан, поле сериализуется как `minDuration`

Нормативное уточнение:
- `camera` и `minDuration` никогда не сериализуются как `null`
- допустимы только две формы: ключ отсутствует или ключ содержит валидное значение

Запрещено:
- вводить отдельное альтернативное поле для runtime `sourceText`
- выводить в `sourceText` paraphrased form вместо `canonical_text`
- принимать два разных serializer path для одного `described_action`

## Example Records

### Example 1. Stop Near Marked Object Then First Smokes

```json
{
  "cir_version": "sg_v7_cir_v1",
  "contract_version": "sg_v7_contract_v1",
  "sample_id": "stop_near_marked_object_then_first_described_action__base__s10421__8f2c1a7b",
  "source_variant_key": "base",
  "pattern_name": "stop_near_marked_object_then_first_described_action",
  "difficulty_bucket": "hard",
  "complexity_class": "M",
  "graph_seed": 10421,
  "scene_graph": {
    "actors": [
      {"id": "actor_1", "type": "human", "name": null, "labels": {"ordinal": "first", "surface_role": null}},
      {"id": "actor_2", "type": "human", "name": null, "labels": {"ordinal": "second", "surface_role": null}}
    ],
    "objects": [
      {
        "id": "object_marked_a1b2c3d4",
        "type": "generic",
        "name": "ноутбук",
        "relative_position": "unknown",
        "marker_binding": {
          "kind": "marked",
          "marker_short_id": "a1b2c3d4",
          "source_name": "ноутбук",
          "mentioned_aliases": ["ноутбук", "ноут", "комп"]
        }
      }
    ],
    "beats": [
      {
        "id": "beat_1",
        "phase": "toward_each_other",
        "actions": [
          {"id": "action_1", "actor_id": "actor_1", "type": "walk", "target_id": "actor_2", "direction": "toward_each_other", "modifier": null, "resulting_pose": "walking", "holding_object": null, "dialogue": null, "semantics": {"chronology_rank": 1}},
          {"id": "action_2", "actor_id": "actor_2", "type": "walk", "target_id": "actor_1", "direction": "toward_each_other", "modifier": null, "resulting_pose": "walking", "holding_object": null, "dialogue": null, "semantics": {"chronology_rank": 2}}
        ]
      },
      {
        "id": "beat_2",
        "phase": "stop_near_object",
        "actions": [
          {"id": "action_3", "actor_id": "actor_1", "type": "stop", "target_id": "object_marked_a1b2c3d4", "direction": null, "modifier": null, "resulting_pose": "standing", "holding_object": null, "dialogue": null, "semantics": {"chronology_rank": 3}},
          {"id": "action_4", "actor_id": "actor_2", "type": "stop", "target_id": "object_marked_a1b2c3d4", "direction": null, "modifier": null, "resulting_pose": "standing", "holding_object": null, "dialogue": null, "semantics": {"chronology_rank": 4}}
        ]
      },
      {
        "id": "beat_3",
        "phase": "first_described_action",
        "actions": [
          {
            "id": "action_5",
            "actor_id": "actor_1",
            "type": "described_action",
            "target_id": null,
            "direction": null,
            "modifier": null,
            "resulting_pose": "standing",
            "holding_object": null,
            "dialogue": null,
            "described_action": {
              "canonical_text": "начинает курить",
              "fallback_text": "*начинает курить*",
              "source_lemma_hint": "курить"
            },
            "semantics": {
              "is_unsupported_runtime_action": true,
              "must_preserve_in_source": true,
              "chronology_rank": 5
            }
          }
        ]
      }
    ],
    "spatial_relations": [
      {"id": "rel_1", "subject": "actor_1", "relation": "near", "object": "object_marked_a1b2c3d4"},
      {"id": "rel_2", "subject": "actor_2", "relation": "near", "object": "object_marked_a1b2c3d4"}
    ],
    "reference_bindings": {
      "ordinal_map": {"first": "actor_1", "second": "actor_2"},
      "marked_object_ids": ["object_marked_a1b2c3d4"],
      "alias_to_object_id": {"ноутбук": "object_marked_a1b2c3d4", "ноут": "object_marked_a1b2c3d4", "комп": "object_marked_a1b2c3d4"}
    },
    "must_preserve": [
      "beat_count=3",
      "must_ground_object:object_marked_a1b2c3d4",
      "ordinal:first->actor_1",
      "action:action_5=described_action"
    ]
  },
  "semantic_tags": ["movement", "marked_object", "ordinal_reference", "described_action", "multi_beat"],
  "determinism": {
    "id_policy": "canonical_v1",
    "ordering_policy": "stable_v1",
    "serializer": "deterministic_scene_script_v1",
    "phase_policy": "phase_enum_v1",
    "described_action_policy": "described_action_v1"
  },
  "budgets": {
    "actor_count": 2,
    "object_count": 1,
    "beat_count": 3,
    "action_count": 5,
    "relation_count": 2
  },
  "runtime_projection": {
    "target_schema": "SceneScript",
    "field_casing": "camelCase",
    "drop_internal_fields": true,
    "fill_original_description_from_source_variant": true,
    "described_action_source_text_policy": "canonical_text_to_sourceText",
    "top_level_optional_policy": "omit_all",
    "beat_optional_policy": "preserve_if_present_else_omit"
  }
}
```

### Example 2. Pass By Object Then Second Runs

```json
{
  "cir_version": "sg_v7_cir_v1",
  "contract_version": "sg_v7_contract_v1",
  "sample_id": "toward_each_other_then_pass_by_object_then_second_runs__base__s801__862a46fe",
  "source_variant_key": "base",
  "pattern_name": "toward_each_other_then_pass_by_object_then_second_runs",
  "difficulty_bucket": "hard",
  "complexity_class": "M",
  "graph_seed": 801,
  "scene_graph": {
    "actors": [
      {"id": "actor_1", "type": "human", "name": null, "labels": {"ordinal": "first", "surface_role": null}},
      {"id": "actor_2", "type": "human", "name": null, "labels": {"ordinal": "second", "surface_role": null}}
    ],
    "objects": [
      {"id": "object_marked_b7c8d9e0", "type": "generic", "name": "ноутбук", "relative_position": "unknown", "marker_binding": {"kind": "marked", "marker_short_id": "b7c8d9e0", "source_name": "ноутбук", "mentioned_aliases": ["ноутбук"]}}
    ],
    "beats": [
      {"id": "beat_1", "phase": "toward_each_other", "actions": [
        {"id": "action_1", "actor_id": "actor_1", "type": "walk", "target_id": "actor_2", "direction": "toward_each_other", "modifier": null, "resulting_pose": "walking", "holding_object": null, "dialogue": null, "semantics": {"chronology_rank": 1}},
        {"id": "action_2", "actor_id": "actor_2", "type": "walk", "target_id": "actor_1", "direction": "toward_each_other", "modifier": null, "resulting_pose": "walking", "holding_object": null, "dialogue": null, "semantics": {"chronology_rank": 2}}
      ]},
      {"id": "beat_2", "phase": "pass_by_object", "actions": [
        {"id": "action_3", "actor_id": "actor_1", "type": "pass_by", "target_id": "object_marked_b7c8d9e0", "direction": null, "modifier": null, "resulting_pose": "walking", "holding_object": null, "dialogue": null, "semantics": {"chronology_rank": 3}},
        {"id": "action_4", "actor_id": "actor_2", "type": "pass_by", "target_id": "object_marked_b7c8d9e0", "direction": null, "modifier": null, "resulting_pose": "walking", "holding_object": null, "dialogue": null, "semantics": {"chronology_rank": 4}}
      ]},
      {"id": "beat_3", "phase": "single_action", "actions": [
        {"id": "action_5", "actor_id": "actor_2", "type": "run", "target_id": null, "direction": null, "modifier": null, "resulting_pose": "running", "holding_object": null, "dialogue": null, "semantics": {"chronology_rank": 5}}
      ]}
    ],
    "spatial_relations": [],
    "reference_bindings": {
      "ordinal_map": {"first": "actor_1", "second": "actor_2"},
      "marked_object_ids": ["object_marked_b7c8d9e0"],
      "alias_to_object_id": {"ноутбук": "object_marked_b7c8d9e0"}
    },
    "must_preserve": [
      "beat_count=3",
      "must_ground_object:object_marked_b7c8d9e0",
      "actor_2_runs_in_final_beat"
    ]
  },
  "semantic_tags": ["movement", "marked_object", "ordinal_reference", "multi_beat", "role_shift"],
  "determinism": {
    "id_policy": "canonical_v1",
    "ordering_policy": "stable_v1",
    "serializer": "deterministic_scene_script_v1",
    "phase_policy": "phase_enum_v1",
    "described_action_policy": "described_action_v1"
  },
  "budgets": {
    "actor_count": 2,
    "object_count": 1,
    "beat_count": 3,
    "action_count": 5,
    "relation_count": 0
  },
  "runtime_projection": {
    "target_schema": "SceneScript",
    "field_casing": "camelCase",
    "drop_internal_fields": true,
    "fill_original_description_from_source_variant": true,
    "described_action_source_text_policy": "canonical_text_to_sourceText",
    "top_level_optional_policy": "omit_all",
    "beat_optional_policy": "preserve_if_present_else_omit"
  }
}
```

### Example 3. Same-Type Two Marked Objects

```json
{
  "cir_version": "sg_v7_cir_v1",
  "contract_version": "sg_v7_contract_v1",
  "sample_id": "same_type_two_marked_objects__same_type_marker_stress__s991__fb6aab21",
  "source_variant_key": "same_type_marker_stress",
  "pattern_name": "same_type_two_marked_objects",
  "difficulty_bucket": "hard",
  "complexity_class": "M",
  "graph_seed": 991,
  "scene_graph": {
    "actors": [
      {"id": "actor_1", "type": "human", "name": null, "labels": {"ordinal": "first", "surface_role": null}},
      {"id": "actor_2", "type": "human", "name": null, "labels": {"ordinal": "second", "surface_role": null}}
    ],
    "objects": [
      {"id": "object_marked_1111aaaa", "type": "chair", "name": "первый стул", "relative_position": "left", "marker_binding": {"kind": "marked", "marker_short_id": "1111aaaa", "source_name": "стул", "mentioned_aliases": ["левый стул", "этот стул"]}},
      {"id": "object_marked_2222bbbb", "type": "chair", "name": "второй стул", "relative_position": "right", "marker_binding": {"kind": "marked", "marker_short_id": "2222bbbb", "source_name": "стул", "mentioned_aliases": ["правый стул", "тот стул"]}}
    ],
    "beats": [
      {"id": "beat_1", "phase": "approach_object", "actions": [
        {"id": "action_1", "actor_id": "actor_1", "type": "approach", "target_id": "object_marked_2222bbbb", "direction": "to_target", "modifier": null, "resulting_pose": "walking", "holding_object": null, "dialogue": null, "semantics": {"chronology_rank": 1}},
        {"id": "action_2", "actor_id": "actor_2", "type": "stand", "target_id": null, "direction": null, "modifier": null, "resulting_pose": "standing", "holding_object": null, "dialogue": null, "semantics": {"chronology_rank": 2}}
      ]}
    ],
    "spatial_relations": [],
    "reference_bindings": {
      "ordinal_map": {"first": "actor_1", "second": "actor_2"},
      "marked_object_ids": ["object_marked_1111aaaa", "object_marked_2222bbbb"],
      "alias_to_object_id": {
        "левый стул": "object_marked_1111aaaa",
        "правый стул": "object_marked_2222bbbb",
        "тот стул": "object_marked_2222bbbb"
      }
    },
    "must_preserve": [
      "must_ground_object:object_marked_2222bbbb",
      "no_type_only_resolution",
      "same_type_markers_present"
    ]
  },
  "semantic_tags": ["marked_object", "same_type_markers", "ordinal_reference", "grounding"],
  "determinism": {
    "id_policy": "canonical_v1",
    "ordering_policy": "stable_v1",
    "serializer": "deterministic_scene_script_v1",
    "phase_policy": "phase_enum_v1",
    "described_action_policy": "described_action_v1"
  },
  "budgets": {
    "actor_count": 2,
    "object_count": 2,
    "beat_count": 1,
    "action_count": 2,
    "relation_count": 0
  },
  "runtime_projection": {
    "target_schema": "SceneScript",
    "field_casing": "camelCase",
    "drop_internal_fields": true,
    "fill_original_description_from_source_variant": true,
    "described_action_source_text_policy": "canonical_text_to_sourceText",
    "top_level_optional_policy": "omit_all",
    "beat_optional_policy": "preserve_if_present_else_omit"
  }
}
```

### Example 4. Dialogue Then Small Action

```json
{
  "cir_version": "sg_v7_cir_v1",
  "contract_version": "sg_v7_contract_v1",
  "sample_id": "dialogue_then_small_action__dialogue_mix__s77__478ba858",
  "source_variant_key": "dialogue_mix",
  "pattern_name": "dialogue_then_small_action",
  "difficulty_bucket": "core",
  "complexity_class": "S",
  "graph_seed": 77,
  "scene_graph": {
    "actors": [
      {"id": "actor_1", "type": "human", "name": "Анна", "labels": {"ordinal": "first", "surface_role": null}},
      {"id": "actor_2", "type": "human", "name": "Борис", "labels": {"ordinal": "second", "surface_role": null}}
    ],
    "objects": [],
    "beats": [
      {"id": "beat_1", "phase": "dialogue_exchange", "actions": [
        {"id": "action_1", "actor_id": "actor_1", "type": "talk", "target_id": "actor_2", "direction": null, "modifier": null, "resulting_pose": "standing", "holding_object": null, "dialogue": "Я уже отправила письмо.", "semantics": {"chronology_rank": 1}},
        {"id": "action_2", "actor_id": "actor_2", "type": "talk", "target_id": "actor_1", "direction": null, "modifier": null, "resulting_pose": "standing", "holding_object": null, "dialogue": "Тогда покажи вложение.", "semantics": {"chronology_rank": 2}}
      ]},
      {"id": "beat_2", "phase": "small_followup_action", "actions": [
        {"id": "action_3", "actor_id": "actor_1", "type": "turn", "target_id": "actor_2", "direction": null, "modifier": null, "resulting_pose": "standing", "holding_object": null, "dialogue": null, "semantics": {"chronology_rank": 3}}
      ]}
    ],
    "spatial_relations": [],
    "reference_bindings": {
      "ordinal_map": {"first": "actor_1", "second": "actor_2"},
      "marked_object_ids": [],
      "alias_to_object_id": {}
    },
    "must_preserve": [
      "dialogue_text_exactness",
      "beat_count=2"
    ]
  },
  "semantic_tags": ["dialogue", "small_action", "ordinal_reference"],
  "determinism": {
    "id_policy": "canonical_v1",
    "ordering_policy": "stable_v1",
    "serializer": "deterministic_scene_script_v1",
    "phase_policy": "phase_enum_v1",
    "described_action_policy": "described_action_v1"
  },
  "budgets": {
    "actor_count": 2,
    "object_count": 0,
    "beat_count": 2,
    "action_count": 3,
    "relation_count": 0
  },
  "runtime_projection": {
    "target_schema": "SceneScript",
    "field_casing": "camelCase",
    "drop_internal_fields": true,
    "fill_original_description_from_source_variant": true,
    "described_action_source_text_policy": "canonical_text_to_sourceText",
    "top_level_optional_policy": "omit_all",
    "beat_optional_policy": "preserve_if_present_else_omit"
  }
}
```

## Invariants

1. Один `CIR` record должен проецироваться ровно в один canonical runtime `SceneScript`.
2. Все runtime ids должны быть валидны и существовать до serializer stage.
3. `reference_bindings.ordinal_map.first` всегда равен `actor_1`.
4. `reference_bindings.ordinal_map.second` всегда равен `actor_2`, если `actor_2` существует.
5. Любой marked object обязан иметь exact `object_marked_<SHORTID>` id.
6. Same-type marked objects не могут различаться только по `type`.
7. `BeatNode.phase` обязателен во внутреннем graph и обязателен для beat segmentation stability.
8. `beats` не могут быть пустыми.
9. `BeatNode.actions` не могут быть пустыми.
10. Все `ActionNode.id` уникальны глобально в record, а не только внутри beat.
11. `described_action` всегда содержит `canonical_text` и `fallback_text`.
12. `talk` не содержит `described_action`; `described_action` не содержит `dialogue`.
13. `direction` допускается только у movement-like action types.
14. `target_id`, если указан, обязан существовать в `actors` или `objects`.
15. `must_preserve` должен покрывать все semantics, на которых historically проваливался runtime.
16. `budgets` должны совпадать с реально подсчитанными counts в `scene_graph`.
17. `complexity_class` выводится из counts, а не ставится вручную без проверки.
18. Serializer не имеет права выводить runtime-only догадки, которых нет в `CIR`.
19. Source generator не имеет права менять `reference_bindings`.
20. Critic/validator должны считать потерю marked object, ordinal mapping или critical described_action hard-fail.

## What Is Deterministic Vs Internal

### Deterministic and externally observable
- ids
- enum values
- beats count and order
- action count and order inside beats
- target references
- described action mapping
- runtime projection
- complexity counters

### Internal and removable before runtime JSON
- phase labels
- ordinal labels
- alias maps
- marker binding metadata
- chronology ranks
- must-preserve constraints
- dedup/review metadata

## Current Runtime / Pipeline Alignment And Known Gaps

Ниже перечислены наблюдения по текущему кодовому состоянию репозитория.

### Already aligned with proposed CIR
- Runtime `SceneScript` уже имеет нужные базовые сущности: `actors`, `objects`, `beats`, `actions`, `spatialRelations`.
- Runtime и `generate_dataset_v6.py` уже согласованы по основным enum для `action.type`, включая `described_action`.
- Runtime и dataset validator уже требуют `fallbackText` и `sourceText` для `described_action`.
- Runtime prompt уже использует exact marked-object ids вида `object_marked_<SHORTID>`.
- Current system already treats `first/second` as semantically important.

### Gaps or drift that CIR makes explicit
- Runtime `SceneScript` не хранит внутренние disambiguation fields вроде `phase`, `reference_bindings`, `must_preserve`; это нормально, но serializer contract должен быть формализован отдельно.
- Current runtime marked-object block в prompt использует `id/name/type`, но не фиксирует `mentioned_aliases` как first-class contract field, хотя `18-runtime-train-contract.md` рекомендует их передавать при необходимости.
- `generate_dataset_v6.py` остаётся legacy reference path и не является canonical SG v7 dataset pipeline.
- Canonical SG v7 dataset path проходит через `generate_dataset_v7.py` и deterministic projection из `CIR`.
- Runtime schema использует camelCase (`relativePosition`, `actorId`, `resultingPose`), а proposed `CIR` intentionally использует snake_case внутри graph; нужен один фиксированный projection layer.
- Runtime currently allows broader cardinalities (`actors <= 6`, `objects <= 8`) than `SG v7` complexity budget. Это не schema conflict, но это train-time budget mismatch, который надо валидировать отдельно.

## Implementation Guidance

Чтобы по этому документу можно было сразу писать graph generator, достаточно реализовать три deterministic шага:

1. Pattern instance builder
- выбирает `pattern_name`
- материализует actors/objects/beats/actions/reference_bindings
- считает budgets
- назначает complexity class

2. CIR validator
- проверяет schema
- проверяет id integrity
- проверяет runtime-projectable fields
- проверяет invariants

3. CIR -> SceneScript serializer
- делает чистое deterministic projection
- удаляет internal fields
- приводит casing к runtime
- сериализует canonical JSON order

## Open Questions

1. Нужно ли в `CIR` хранить `camera` уже на graph stage, или для `SG v7 core` лучше оставить её почти всегда `null` и добавлять только в отдельных buckets?
2. Должен ли `described_action.canonical_text` всегда быть инфинитивом/леммой, или лучше хранить surface-canonical form типа `начинает курить`?
3. Нужен ли отдельный `ambiguity_flags` блок для cases с same-type marked objects, или достаточно `must_preserve`?
4. Нужно ли разрешать `actor_3` в ordinal-sensitive patterns, или ordinal families лучше жёстко ограничить двумя актёрами?
5. Стоит ли включать `spatial_relations` в `core` как норму, или использовать их только когда они критичны для object grounding?
6. Нужен ли отдельный deterministic `graph_hash` уже на уровне `CIR`, или достаточно `sample_id` + stable serializer?
7. Следует ли `mentioned_aliases` сделать обязательным для каждого marked object, даже если alias всего один?
