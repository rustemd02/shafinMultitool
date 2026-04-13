# 21. Deterministic Graph Generator Design

## Цель

Зафиксировать исполнимый дизайн `deterministic graph generator` для `SG v7`, чтобы инженер мог начать реализацию `01_build_pattern_graphs.py` без дополнительных архитектурных решений.

Этот документ закрывает design-часть `Track 3` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/11-implementation-backlog.md).

## Scope

Данный слой отвечает за:
- deterministic planning набора graph records
- materialization `CIR`-записей из pattern registry
- reproducible seed derivation
- bucket-aware complexity gating
- exact graph-level dedup
- JSONL/manifest output для downstream source generation и dataset assembly

Данный слой не отвечает за:
- paraphrase/source generation
- morphology/noise augmentation
- semantic critics
- final train/val/test split policy
- runtime serializer changes

## Исходные зависимости

Graph generator не придумывает semantics самостоятельно. Он обязан переиспользовать уже существующие source-of-truth артефакты:

- pattern registry: [pattern_library/registry.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/pattern_library/registry.py)
- pattern coverage/policy: [20-pattern-library.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/20-pattern-library.md)
- CIR contract: [19-canonical-intermediate-representation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/19-canonical-intermediate-representation.md)
- CIR validator/serializer: [cir_contract/contracts/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/cir_contract/contracts)
- canonical entrypoint: [generate_dataset_v7.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v7.py)
- legacy comparison only: [generate_dataset_v6.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v6.py)

Отдельное правило versioning:
- source-of-truth для версии pattern registry является экспортируемая Python-константа `PATTERN_REGISTRY_VERSION` из [pattern_library/registry.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/pattern_library/registry.py)
- manifest и seed derivation обязаны использовать именно её, а не выводить версию эвристически из filenames, git hash или `internal_metadata`

## Design Summary

Ключевое решение:
- `pattern_library` остаётся owner-ом pattern semantics и per-pattern builders
- новый `graph_generator` слой не дублирует эти builders, а добавляет deterministic planning, validation, dedup и emission
- production entrypoint для Track 3: `docs/SGv7pipeline/graph_generator/01_build_pattern_graphs.py`

Иначе говоря:

```text
PatternSpec builder
  -> CIR record candidate
  -> CIR validation
  -> bucket complexity gate
  -> graph fingerprint / dedup
  -> stable ordering
  -> JSONL + manifest
```

## Почему недостаточно одного `enumerate_pattern_records()`

Текущий executable registry уже умеет:
- строить valid `CIR`
- перечислять patterns
- выдавать deterministic результат при одинаковом seed

Но для production graph generator этого недостаточно, потому что ещё нужны:
- явный CLI-контракт
- независимая генерация `core` и `hard` без скрытой связи через общий shuffle
- планирование counts по patterns и buckets как отдельный шаг
- bounded refill policy после dedup/drop
- exact graph-level fingerprint, который не зависит от seed-derived marked ids
- manifest с метаданными сборки

Следовательно, `enumerate_pattern_records()` остаётся удобным helper-ом для tests/examples, а `01_build_pattern_graphs.py` становится reproducible orchestration layer.

## Emitted Artifact Contract

Graph generator первой версии пишет `pure CIR JSONL`.

То есть каждая строка output-файла является валидным `CIR` record и не оборачивается во внешний envelope.

`marked_object_spec` в старых описаниях graph generator-а следует считать уже встроенным в `CIR`, а не отдельным top-level полем:
- `scene_graph.objects[*].marker_binding`
- `scene_graph.reference_bindings.marked_object_ids`
- `scene_graph.reference_bindings.alias_to_object_id`

Manifest является отдельным sidecar JSON и не участвует в `CIR` contract.

## Рекомендуемая структура модулей

```text
docs/SGv7pipeline/graph_generator/
  __init__.py
  config.py
  planner.py
  builder.py
  dedup.py
  validate.py
  manifest.py
  writer.py
  01_build_pattern_graphs.py
  tests/
    test_graph_generator_planner.py
    test_graph_generator_dedup.py
    test_graph_generator_cli.py
```

## Ownership по файлам

### `config.py`

Хранит typed config/dataclass слой:
- `GraphBuildRequest`
- `BucketPolicy`
- `PatternQuota`
- `OutputTargets`

### `planner.py`

Отвечает за deterministic build plan:
- выбор pattern set
- allocation counts
- variant selection
- graph seed derivation
- refill plan после dedup/drop

### `builder.py`

Тонкая прослойка над `pattern_library.registry`:
- получает `PlanItem`
- вызывает `generate_pattern_record(...)`
- не содержит своей pattern semantics

### `dedup.py`

Отвечает за exact graph-level dedup:
- canonical graph normalization для dedup
- `graph_fingerprint_v1`
- `dedup_group_key`
- `DedupIndex`

### `validate.py`

Проверяет, что candidate record:
- валиден по CIR contract
- попадает в bucket budget
- не нарушает core/hard policy

### `manifest.py`

Собирает reproducibility metadata:
- build seed
- contract versions
- registry version
- counts requested/generated/dropped
- duplicate stats
- pattern distribution

### `writer.py`

Отвечает за:
- stable sort output
- JSONL emission
- manifest JSON emission

### `01_build_pattern_graphs.py`

CLI entrypoint, который связывает всё вместе.

## Public API

Рекомендуемый Python API:

```python
from dataclasses import dataclass
from pathlib import Path

@dataclass(frozen=True)
class GraphBuildRequest:
    seed: int
    difficulty_bucket: str | None
    total_records: int | None
    pattern_names: list[str] | None
    include_variants: list[str] | None
    output_jsonl: Path
    output_manifest: Path | None
    refill_budget: int = 3
    fail_on_duplicates: bool = False

def build_graph_records(request: GraphBuildRequest) -> BuildResult: ...
def plan_graph_records(request: GraphBuildRequest) -> list[PlanItem]: ...
def graph_fingerprint(record: dict) -> str: ...
def dedup_group_key(record: dict) -> str: ...
```

Рекомендуемый CLI:

```bash
python docs/SGv7pipeline/graph_generator/01_build_pattern_graphs.py \
  --seed 20260413 \
  --bucket core \
  --total-records 500 \
  --output-jsonl /tmp/sg_v7_core_graphs.jsonl \
  --output-manifest /tmp/sg_v7_core_graphs.manifest.json
```

Допустимые CLI флаги первой версии:
- `--seed`
- `--bucket {core,hard}`
- `--total-records`
- `--pattern-name` с repeatable использованием
- `--output-jsonl`
- `--output-manifest`
- `--fail-on-duplicates`
- `--refill-budget`

Первая версия не обязана поддерживать YAML configs. Достаточно строгого CLI.

## Data Flow

```text
CLI / API request
  -> resolve pattern specs from PATTERN_REGISTRY
  -> allocate per-pattern quotas
  -> derive deterministic plan items
  -> materialize CIR candidates via registry builders
  -> validate CIR
  -> validate bucket complexity policy
  -> compute graph_fingerprint_v1
  -> drop exact duplicates
  -> refill missing quota deterministically
  -> stable sort final records
  -> write JSONL
  -> write manifest
```

## Plan Item Contract

До materialization generator работает не с готовыми record-ами, а с plan item-ами:

```json
{
  "ordinal": 17,
  "pattern_name": "toward_each_other_then_stop_near_marked_object",
  "difficulty_bucket": "core",
  "source_variant_key": "morphology_stress",
  "graph_seed": 418203,
  "attempt_index": 0
}
```

Правила:
- `ordinal` детерминирован внутри build-а
- `attempt_index=0` для первичного плана
- refill использует тот же `ordinal`, но новый `attempt_index`
- final output не обязан сохранять `PlanItem`, но manifest должен позволять воспроизвести derivation rule

## Seed And Reproducibility Strategy

### Non-goals

Нельзя:
- использовать global `random.seed(...)` как единственный источник истины
- делать seed derivation зависимым от того, сколько дублей уже встретилось
- делать `core` output зависимым от того, запускался ли рядом `hard`

### Правило derivation

У каждого candidate должен быть собственный namespaced seed:

```text
sha256(
  build_seed,
  contract_version,
  registry_version,
  difficulty_bucket,
  pattern_name,
  source_variant_key,
  ordinal,
  attempt_index
)
```

Из этого payload получается:
- `plan_key`
- `graph_seed`

Рекомендуемое правило:
- брать первые 12 hex-символов
- переводить в int
- сжимать в диапазон `100..999999`

Это даёт важные свойства:
- одинаковый request всегда даёт одинаковый plan
- `core` и `hard` можно генерировать отдельно
- refill не ломает уже успешно сгенерированные records

### Registry-level randomness

Per-pattern builders могут продолжать использовать локальный `random.Random(...)`, но только от уже вычисленного `graph_seed` и известных namespace inputs.

## Complexity Controls

Graph generator обязан делать budget gating до записи результата.

### Bucket policy

`core`:
- разрешены только `S` и `M`
- `L` запрещён
- same-type marked pair запрещён вне pattern-ов, где это явно заложено registry
- `beat_count <= 3`
- `action_count <= 5`

`hard`:
- разрешены `S`, `M`, `L`
- `L` допускается только для pattern-ов, уже помеченных в registry как `hard`
- `beat_count <= 4`
- `action_count <= 6`

### Источник истины для budget

Generator не пересчитывает semantics вручную. Он использует уже присутствующие в `CIR`:
- `budgets`
- `complexity_class`
- `difficulty_bucket`

Если record нарушает bucket policy, он:
- либо отбрасывается и заменяется refill-candidate
- либо вызывает hard failure, если включён strict mode

## Dedup Strategy

## Почему `sample_id` недостаточен

`sample_id` включает `graph_seed` и structural hash текущего graph-а. Это хорошо для contract integrity, но недостаточно для graph dedup:
- два разных `graph_seed` могут породить один и тот же semantic graph
- marked object ids зависят от seed через `SHORTID`
- значит, одинаковая semantics может иметь разный `sample_id`

Следовательно, graph generator обязан использовать отдельный dedup fingerprint.

### `graph_fingerprint_v1`

Exact dedup должен:
- игнорировать top-level metadata
- нормализовать `object_marked_<SHORTID>` в slot-stable placeholder-и
- сортировать actors/objects/beats/actions/relation-ы по canonical rule
- сохранять semantic fields, влияющие на final SceneScript

Нормализация должна включать:
- `actor_1/2/3` как есть
- unmarked objects как есть
- marked objects: `object_marked_SLOT1`, `object_marked_SLOT2`
- `marker_short_id` удаляется из fingerprint payload
- `source_name` и `mentioned_aliases` сохраняются, потому что они важны для morphology stress

Deterministic slot assignment обязателен и делается так:
1. собрать все marked objects из `scene_graph.objects`
2. для каждого marked object посчитать `marked_object_signature_v1` из полей, не зависящих от `SHORTID`:
   - `type`
   - `name`
   - `relative_position`
   - `marker_binding.source_name`
   - отсортированный `marker_binding.mentioned_aliases`
   - `first_usage_signature`
3. `first_usage_signature` вычисляется как самая ранняя ссылка на объект в нормализованном graph-е:
   - сначала среди `beats[*].actions[*].target_id`
   - затем среди `beats[*].actions[*].holding_object`
   - затем среди `spatial_relations[*].object`
   - формат сигнатуры: `<kind>:<beat_index>:<action_index_or_relation_index>:<action_type_or_relation>`
4. marked objects сортируются по `(marked_object_signature_v1, original_object_position_in_sorted_scene_graph)`
5. после сортировки им назначаются placeholder ids `object_marked_SLOT1`, `object_marked_SLOT2`, ...
6. все ссылки на эти ids в actions, relations и `reference_bindings` переписываются на placeholder ids до хеширования

Это правило обязательно именно для того, чтобы same-type marked patterns с разными `SHORTID` схлопывались как exact duplicates только тогда, когда у них действительно совпадает semantics.

Результат:
- если два records различаются только seed-derived marked ids, они считаются дублем
- если records различаются по dialogue/described action/object binding, это уже разные графы

### `dedup_group_key`

Кроме exact dedup нужен более грубый downstream-friendly ключ:

```text
pattern_name
+ source_variant_key
+ beat_phase_sequence
+ actor_count
+ object_mode_shape
+ action_type_sequence
```

Generator не обязан выкидывать все записи одного `dedup_group_key`, но обязан записывать этот ключ в manifest для downstream balancing.

### Refill policy

Если candidate отброшен как duplicate:
- generator пытается построить replacement для того же pattern quota
- replacement использует тот же `ordinal`, но `attempt_index += 1`
- максимум попыток на quota slot: `1 + refill_budget`

Если после исчерпания refill quota не закрыта:
- CLI завершается ошибкой

Это лучше, чем silently выдать меньше данных.

## Stable Output Ordering

Перед записью generator сортирует final records по:
1. `difficulty_bucket`
2. `pattern_name`
3. `source_variant_key`
4. `graph_seed`
5. `sample_id`

Manifest должен хранить и requested order, и final emitted order counts, но не обязан сохранять каждый промежуточный candidate.

## Manifest Contract

Минимальный manifest первой версии:

```json
{
  "generator_name": "sg_v7_graph_generator_v1",
  "build_seed": 20260413,
  "difficulty_bucket": "core",
  "requested_total_records": 500,
  "emitted_total_records": 500,
  "duplicate_drop_count": 7,
  "refill_attempt_count": 7,
  "cir_version": "sg_v7_cir_v1",
  "contract_version": "sg_v7_contract_v1",
  "pattern_registry_version": "sg_v7_pattern_library_v1",
  "pattern_counts": {
    "toward_each_other": 45
  },
  "variant_counts": {
    "base": 310
  }
}
```

Дополнительно рекомендуется писать:
- `complexity_counts`
- `rejected_by_budget`
- `rejected_by_duplicate`
- `build_request`

Поле `pattern_registry_version` должно быть равно значению `PATTERN_REGISTRY_VERSION` из executable registry.

## Validation Policy

Каждый emitted record обязан пройти:
1. `CIR` schema validation
2. invariant validation через `cir_validator`
3. bucket complexity validation
4. duplicate validation

Generator не имеет права:
- repair-ить broken `sample_id`
- переписывать `difficulty_bucket` постфактум
- ослаблять contract ради сохранения количества samples

## Backlog По Реализации

### Phase 1. Package Skeleton

- создать `docs/SGv7pipeline/graph_generator/`
- завести `config.py`, `planner.py`, `builder.py`, `dedup.py`, `validate.py`, `manifest.py`, `writer.py`
- экспортировать `build_graph_records`

### Phase 2. Deterministic Planner

- реализовать `PlanItem`
- реализовать quota allocation поверх `PATTERN_REGISTRY`
- реализовать namespace seed derivation
- реализовать refill planning

### Phase 3. Materialization And Validation

- подключить `generate_pattern_record(...)`
- валидировать record через `cir_validator`
- добавить bucket policy checks

### Phase 4. Dedup Layer

- реализовать `graph_fingerprint_v1`
- реализовать `DedupIndex`
- реализовать replacement loop с bounded refill

### Phase 5. Output Layer

- stable JSONL writer
- manifest writer
- CLI summary / exit codes

### Phase 6. Smoke Integration

- проверить output через [generate_dataset_v7.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v7.py)
- убедиться, что emitted records проектируются в valid `SceneScript`

## Backlog По Функциям И Классам

Обязательные сущности первой реализации:

- `GraphBuildRequest`
- `BucketPolicy`
- `PlanItem`
- `BuildResult`
- `build_graph_records(request)`
- `plan_graph_records(request)`
- `derive_graph_seed(...)`
- `materialize_plan_item(plan_item)`
- `validate_bucket_policy(record, policy)`
- `normalize_record_for_graph_fingerprint(record)`
- `graph_fingerprint(record)`
- `dedup_group_key(record)`
- `DedupIndex.add(record) -> bool`
- `write_jsonl(records, path)`
- `write_manifest(manifest, path)`

## Unit Test Plan

### Planner

- одинаковый `GraphBuildRequest` даёт одинаковый список `PlanItem`
- отдельный запуск `core` не зависит от запуска `hard`
- одинаковые quotas дают одинаковые `graph_seed`
- refill attempt меняет seed, но не ломает deterministic derivation

### Builder / Validation

- каждый materialized record валиден по `CIR`
- `core` build не пропускает `L`
- `hard` build допускает `L` только для hard patterns

### Dedup

- разные marked `SHORTID`, но одинаковая semantics схлопываются в один `graph_fingerprint_v1`
- реально разные action chains не считаются дублем
- duplicate replacement детерминирован
- при исчерпании refill budget CLI падает с ошибкой

### CLI / Output

- `--bucket core` пишет только `core`
- `--pattern-name` ограничивает output выбранными pattern-ами
- JSONL порядок стабилен
- manifest counts совпадают с реально записанными records

### Contract Smoke

- любой emitted record проходит [generate_dataset_v7.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v7.py) и сериализуется в `SceneScript`
- одинаковый build seed даёт byte-identical JSONL при одинаковом наборе аргументов

## Инварианты Реализации

- graph generator не создаёт новую semantics мимо `PATTERN_REGISTRY`
- seed derivation не зависит от порядка runtime execution
- `sample_id` проверяется, а не чинится
- exact graph dedup не зависит от seed-derived marked ids
- `core` и `hard` могут собираться независимо
- output всегда traceable через manifest

## Implementation Handoff

Инженеру, который будет писать `01_build_pattern_graphs.py`, не нужно принимать дополнительные решения по:
- месту entrypoint
- составу модулей
- public API первой версии
- seed derivation strategy
- dedup architecture
- bucket gating policy
- manifest contract
- обязательным unit/smoke tests

Можно начинать с `Phase 1 -> Phase 6` в указанном порядке, используя существующие `pattern_library` и `cir_contract` как dependencies, а не как черновой reference.
