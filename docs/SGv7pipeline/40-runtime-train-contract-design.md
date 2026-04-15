# 40. Runtime / Train Contract Design (Draft v2)

## Цель

Зафиксировать исполнимый дизайн `Prompt 11` / `Track 0` для следующей версии contract, чтобы:
- train/runtime не расходились по prompt structure, serializer, grammar и decoding policy
- exact `object_marked_*` identity и ordinal binding были стабильны end-to-end
- change policy и fixture-based drift checks были достаточны для безопасного rollout

## Статус И Приоритет Source Of Truth

На текущий момент активный продовый contract:
- [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)
- `contract_version = "sg_v7_contract_v1"`

Этот документ:
- описывает **draft для `sg_v7_contract_v2`**
- не переопределяет `v1` задним числом
- становится source of truth только после implement phase и прохождения `v2` fixtures/checks

При конфликте между `v1` и этим документом до rollout:
- для прод/runtime/train действуют правила `v1`
- для design/implementation planning действует этот `v2` draft

## Scope

Track 0 отвечает за:
- exact logical prompt contract
- exact transport rendering contract
- marked-object section contract
- generation target vs runtime envelope contract
- canonical serializer rules
- grammar/GBNF + enums parity
- decoding bundle
- frozen fixtures + drift checks
- versioning/change policy

Track 0 не отвечает за:
- training phase scheduling
- parser selection policy (`accept/merge/reject`)
- runtime feedback loop
- AR/UI flows

## Подтвержденные Drift-Зоны (Current State)

1. Train target сейчас включает `originalDescription`, а runtime grammar его не допускает.
2. Runtime и train используют разные prompt texts/sections.
3. Marked-object formatting отличается (включая case и aliases policy).
4. Legacy repairs (`speed -> modifier`, `actions -> beats`) смешаны с canonical path.
5. Train prompt включает graph-derived hints, которых runtime не знает.

## Versioned Bundle (`v2`)

`v2` вводится только как новая версия:
- `contract_version = "sg_v7_contract_v2"`
- `prompt_contract_version = "sg_v7_prompt_v2"`
- `marked_object_contract_version = "sg_v7_marked_objects_v2"`
- `generation_target_version = "sg_v7_generation_json_v2"`
- `runtime_envelope_version = "sg_v7_runtime_envelope_v2"`
- `serializer_version = "sg_v7_serializer_v2"`
- `grammar_version = "sg_v7_gbnf_v2"`
- `decoding_version = "sg_v7_decoding_v2"`
- `fixture_bundle_version = "sg_v7_contract_fixtures_v2"`
- `enum_bundle_version = "sg_v7_enums_v2"`

Рекомендуемые артефакты:
- `docs/SGv7pipeline/runtime_train_contract/prompt_contract_v2.md`
- `docs/SGv7pipeline/runtime_train_contract/generation_schema_v2.json`
- `docs/SGv7pipeline/runtime_train_contract/marked_object_contract_v2.md`
- `docs/SGv7pipeline/runtime_train_contract/enums_v2.json`
- `docs/SGv7pipeline/runtime_train_contract/decoding_config_v2.json`
- `docs/SGv7pipeline/runtime_train_contract/fixtures/runtime_train_contract_fixtures_v2.jsonl`
- `docs/SGv7pipeline/runtime_train_contract/tests/test_runtime_train_contract_v2.py`

## Exact Prompt Contract (`sg_v7_prompt_v2`)

### Logical Messages

Логический prompt всегда:
- 1 `system` message
- 1 `user` message
- без few-shot примеров
- без train-only hints

### System Message

```text
Ты SceneScript parser для коротких русскоязычных описаний сцены. Верни только валидный JSON без markdown и без пояснений.
Не выдумывай актёров, объекты, действия и отношения, которых нет в source text.
Сохраняй chronology по beats.
Если source text ссылается на marked object, используй его exact id из секции Marked objects.
Ordinal binding фиксирован: первый=actor_1, второй=actor_2, третий=actor_3.
Если важное действие не покрывается разрешёнными action.type, используй described_action с fallbackText и sourceText.
Если optional поле семантически не нужно, опускай его.
```

### User Message Sections (Fixed Order)

```text
Task instruction:
Сконвертируй source text в canonical SceneScript JSON.

Output contract:
Верни только JSON c top-level полями actors, objects, beats, spatialRelations.

Action/object constraints:
- preserve chronology from source text
- preserve actor and target bindings from source text
- reuse exact marked-object ids when the source refers to a marked object
- do not invent duplicate objects for an already marked real-world object
- unsupported but important actions must become described_action
- omit optional fields when they are semantically absent

Marked objects:
<rendered marked-object block>

Source text:
<normalized source text>
```

### Transport Contract (No Hidden Drift)

Чтобы не оставить drift-prone зону на уровне chat template:
- logical prompt hash считается по normalized `system + "\n\n" + user`
- runtime transport тоже versioned (`chat_transport_v2`)
- для runtime с ChatML wrapper фиксируется exact layout:
  - `<|im_start|>system\n{system}\n<|im_end|>\n<|im_start|>user\n{user}\n<|im_end|>\n<|im_start|>assistant\n`
- train/eval/runtime обязаны хранить `logical_prompt_hash` и `transport_prompt_hash`

`stateContext` не входит в `v2`. Stateful-вариант допустим только как отдельный `contract_version`.

## Marked Object Section Contract (`sg_v7_marked_objects_v2`)

### Block Shape

Если объектов нет:

```text
Marked objects:
- none
```

Если объекты есть:

```text
Marked objects:
- id=object_marked_a1b2c3d4; name=ноутбук; type=generic; aliases=-
- id=object_marked_f9e8d7c6; name=левый стул; type=chair; aliases=-
```

### Exact Rules

- prefix: `object_marked_`
- `SHORTID`: lower-case hex длины 8
- порядок полей: `id`, `name`, `type`, `aliases`
- разделитель: `; `
- `name` lower-case + trim
- `aliases` для `v2` фиксированно `-` в runtime/train prompt contract
- строки сортируются по `id`

### ID Normalization Rule (Mandatory)

Для runtime UUID-derived ids:
- берётся префикс UUID длины 8
- затем `lowercased()`
- потом собирается `object_marked_<shortid>`

Для non-UUID marker identity:
- `shortid = sha256(marker_identity_key)[:8]`, где `marker_identity_key = normalized_name + "|" + type + "|" + stable_marker_index`
- `stable_marker_index` задаётся по `marked_objects_source_list` **до** генерации `id` и **до** любой сортировки rows по `id`
- `marked_objects_source_list` берётся из source marker input в фиксированном pre-id порядке:
  - сначала `source_marker_ordinal` (если доступен)
  - затем `normalized_name`
  - затем `type`
  - затем `marker_origin_key`
- если `source_marker_ordinal` отсутствует и `marker_origin_key` отсутствует, renderer обязан завершаться ошибкой (`marker_identity_order_unstable`)
- сортировка prompt rows по `id` применяется только после финализации всех `shortid` и не влияет на `stable_marker_index`

Collision policy внутри одного sample:
- если `shortid` уже занят, пересчитать `shortid = sha256(marker_identity_key + "|" + collision_index)[:8]`
- `collision_index` начинается с `1` и инкрементируется до первого свободного значения
- при каждом пересчёте `marker_identity_key` остаётся неизменным; меняется только `collision_index`
- policy обязана быть одинаковой в train/runtime fixture rendering и проверяться fixture-ом `marked_id_collision_resolution_v2`

Это правило обязано использоваться в обоих местах runtime:
- prompt rendering
- repair/injection path

## Generation Target Contract (`sg_v7_generation_json_v2`)

LLM генерирует только:

```json
{
  "actors": [],
  "objects": [],
  "beats": [],
  "spatialRelations": []
}
```

Запрещены top-level поля:
- `originalDescription`
- `sceneHeading`
- `locationName`
- `interiorExterior`
- `timeOfDay`

## Runtime Envelope Contract (`sg_v7_runtime_envelope_v2`)

После strict decode generation target-а downstream слой добавляет:

```json
{
  "actors": [],
  "objects": [],
  "beats": [],
  "spatialRelations": [],
  "originalDescription": "..."
}
```

Правила:
- `originalDescription` берётся из source text
- никакие другие top-level scene fields не добавляются
- envelope stage не меняет semantics generated graph-а

## Canonical Serializer Rules (`sg_v7_serializer_v2`)

- actors: stable numeric id order
- objects: marked first, дальше stable numeric id order
- beats: stable numeric id order
- actions: `chronology_rank`, затем stable action id
- spatial relations: stable numeric id order
- optional policy: `emit_if_present_else_omit`
- `null` не используется
- canonical string: UTF-8, `ensure_ascii=False`, separators `(",", ":")`

## Action Semantics Completeness

В `v2` prose-правила не ограничиваются `talk`/`described_action`/motion.

Authoritative policy для action-level invariants:
- [cir_validator.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/cir_contract/contracts/cir_validator.py)
- `docs/SGv7pipeline/runtime_train_contract/action_semantics_matrix_v2.json`

Conflict resolution rule:
- если prose и validator расходятся, блокирующим source of truth считается validator + machine-readable matrix
- prose обязан обновляться в том же change set, иначе change считается незавершённым

В contract tests обязательно покрыть:
- `look_at` target semantics
- `pick_up`/`put_down` + `holdingObject`
- `open`/`close` target semantics
- `give` target semantics
- `talk` vs `described_action` mutual exclusivity

## Grammar + Enums Contract (`sg_v7_gbnf_v2`)

GBNF описывает generation target и не включает envelope-only поля.

Обязательные ограничения:
- top-level: только `actors`, `objects`, `beats`, `spatialRelations`
- нет legacy top-level `actions`
- нет `speed` поля
- id-string: lower-case alnum + `_`
- enum set синхронизирован с `SceneScript.swift`

Machine-readable enum parity:
- `enums_v2.json` является обязательным artifact
- parity script проверяет совпадение:
  - Swift enums
  - Python contract enums
  - GBNF enums

## Decoding Contract (`sg_v7_decoding_v2`)

- grammar: `sg_v7_gbnf_v2`
- temperature: `0.1`
- top_k: `20`
- repetition_penalty: `1.3`
- repetition_window: `64`
- sampler_seed: `1234`
- generation token budgets: `[512, 768]`
- stop boundary: `EOG` или `max_tokens`

Offline eval, runtime A/B и prod inference обязаны использовать один decoding bundle.

## Repair Boundary

Canonical `v2` path:
1. strict decode по grammar/schema
2. canonical re-serialization
3. runtime envelope attach

Legacy repairs (`actions -> beats`, `speed -> modifier`, bracket balancing и т.д.):
- не часть canonical `v2`
- допускаются только в отдельном compatibility profile:
  - `legacy_repair_profile = "sg_v7_legacy_repair_v1"`
- запрещены для `v2` fixtures и training gold path

## Dataset Schema Migration Plan

Чтобы split `generation target` / `runtime envelope` не ломал текущий pipeline, `v2` rollout по фазам:

1. **Phase A (dual-write)**
- dataset row хранит:
  - `target_generation_json`
  - `target_runtime_envelope_json`
  - временно `target_json` как legacy alias
- ownership rule:
  - `target_generation_json` — единственный writable source of truth
  - `target_runtime_envelope_json` — deterministic derived artifact из `target_generation_json + source_text`
  - `target_json` — derive-only legacy alias (write запрещён)
- consistency gate (обязателен до приёма row):
  - `target_runtime_envelope_json == envelope(target_generation_json, source_text)`
  - если `target_json` присутствует, то `target_json == target_runtime_envelope_json`

2. **Phase B (consumer migration)**
- ingest/dedup/train/eval consumers переходят на новые поля
- `target_json` остаётся read-only совместимостью

3. **Phase C (strict v2)**
- для `sg_v7_contract_v2` `target_json` больше не обязателен
- любые mixed rows (`v1`/`v2`) в одном emitted artifact запрещены

## Frozen Fixtures (`sg_v7_contract_fixtures_v2`)

Минимум:
- existing CIR examples `ex1`...`ex4`
- 2+ cases exact marked identity
- 1+ обязательный collision-resolution case (`marked_id_collision_resolution_v2`)
- 2+ same-type markers
- 2+ ordinal binding
- 2+ unsupported action -> `described_action`
- 2+ multi-beat chronology
- 1+ no-marked-object case
- 1+ optional-field omission case для `name/target/direction/modifier`
- 1+ optional-field present case для canonical serialization (`name/target/direction/modifier`)
- 1+ `null`-forbidden regression case (любой `null` в generation target должен фейлиться)

Каждый fixture хранит:
- `fixture_id`
- `contract_version`
- `logical_prompt_hash`
- `transport_prompt_hash`
- `generation_target_json`
- `runtime_envelope_json`
- `expected_marked_ids`
- `expected_actor_ordinals`

## Drift Checks (`v2`)

1. `prompt_text_hash_match`
2. `transport_template_hash_match`
3. `marked_object_render_match`
4. `marked_id_case_check`
5. `marked_id_collision_resolution_check`
6. `generation_target_schema_match`
7. `original_description_outside_generation_target`
8. `serializer_field_order_match`
9. `enum_parity_check`
10. `described_action_policy_check`
11. `ordinal_binding_check`
12. `action_semantics_parity_check`
13. `optional_present_canonicalization_check`
14. `null_forbidden_check`
15. `repair_boundary_check`
16. `dataset_row_schema_v2_check`

`marked_id_collision_resolution_check` обязан проверять минимум:
- одинаковые входные marker rows дают одинаковые resolved ids в train/eval/runtime
- при намеренной shortid-коллизии применяется deterministic re-hash с `collision_index`, без silent overwrite

## Change Policy

Contract change trigger:
- prompt wording/order
- transport wrapper
- marked-object rendering
- generation schema
- serializer field order/optional policy
- enums
- grammar
- decoding settings
- repair boundary
- dataset row schema

Обязательная процедура:
1. обновить versioned artifacts
2. прогнать fixtures
3. прогнать drift checks
4. подтвердить dataset/runtime/eval compatibility
5. bump `contract_version`, если observable behavior изменился

## Implementation Handoff

1. Зафиксировать `v2` artifacts и parity tests.
2. Вынести shared prompt renderer для train/runtime.
3. Ввести mandatory lower-case normalization для `object_marked_*`.
4. Реализовать dual-write migration для dataset rows.
5. Отделить legacy repair profile от canonical v2 path.
6. Включить v2 fixture gate в CI для contract-sensitive треков.

## Definition Of Done (Design Verify)

`v2` design готов к реализации, если:
- есть один непротиворечивый draft bundle `sg_v7_contract_v2`
- нет скрытых transport/alias/repair drift-зон
- migration path для dataset schema описан пошагово
- все обязательные drift checks определены

## Open Question

- Нужен ли stateful prompt contract как отдельный `sg_v7_contract_v3_stateful`, или это должен быть отдельный runtime-only profile вне SFT loop.
