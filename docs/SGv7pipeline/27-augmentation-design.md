# 27. Augmentation Design

## Цель

Зафиксировать исполнимый дизайн controlled augmentation layer для `SG v7`, чтобы инженер мог реализовать `04_noise_and_morphology.py` без дополнительных решений по:
- augmentation classes
- safe vs risky transform policy
- morphology engine rules
- user-noise transformations
- traceable metadata
- post-augmentation validation plan

Этот документ закрывает design-часть `Track 5` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/11-implementation-backlog.md).

## Scope

Augmentation layer отвечает за:
- controlled post-processing уже принятых source variants из Track 4
- детерминированные morphology/noise transforms поверх исходного смысла graph
- явное разделение safe и risky surface-изменений
- запись provenance и transform-chain metadata
- передачу augmented samples в downstream validation stack

Augmentation layer не отвечает за:
- генерацию canonical graph или final target JSON
- свободный paraphrase через LLM
- финальное semantic accept/reject решение без участия Track 6
- смену runtime/train contract
- repair target JSON при source drift

## Исходные зависимости

Track 5 обязан переиспользовать уже зафиксированные артефакты:
- общий индекс пакета: [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/README.md)
- fixed decisions: [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
- runtime failure seeds: [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- augmentation baseline: [05-augmentation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/05-augmentation.md)
- validator stack baseline: [06-validation-and-critics.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/06-validation-and-critics.md)
- source generation design: [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md)
- canonical CIR contract: [19-canonical-intermediate-representation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/19-canonical-intermediate-representation.md)
- runtime marked-object grounding reference: [MarkedObjectMatcher.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/MarkedObjectMatcher.swift)

## Design Summary

Ключевое решение:
- augmentation работает только поверх уже accepted `base_paraphrase` variants
- v1 реализует deterministic transform catalog, а не свободные lexical rewrites
- каждый transform применяется к явно определенному surface slot и пишет transform metadata
- safe transforms разрешены по умолчанию
- risky transforms существуют в каталоге, но по умолчанию выключены и требуют отдельного флага + усиленной валидации
- augmentation не должен пытаться "улучшать текст вообще"; его задача только stress-test recoverability

Базовый flow:

```text
accepted source variant
  -> derive augmentation slots
  -> build deterministic transform plan
  -> apply one or more transforms
  -> run lexical invariants
  -> run post-augmentation validation
  -> accept augmented variant or reject with reason
```

## Почему augmentation идет после source generation

Если morphology/noise делать прямо в Track 4, становится трудно различить:
- ошибка paraphrase-модели
- ошибка трансформации
- ошибка validator-а

Отдельный слой Track 5 дает:
- явный ownership за morphology/noise stress
- traceable provenance
- повторяемость по seed
- возможность отключать конкретные transform classes без переписывания source prompts

## Input Contract

`04_noise_and_morphology.py` принимает JSONL с accepted source variants. Минимальный входной record:

```json
{
  "sample_id": "sgv7-core-000123",
  "variant_id": "sgv7-core-000123-clean-00",
  "graph_id": "sgv7-core-000123",
  "difficulty_bucket": "core",
  "style_bucket": "clean",
  "source_text": "Два актера идут навстречу друг другу, останавливаются у компа, после этого первый начинает курить.",
  "generation_pass": "base_paraphrase",
  "acceptance": {
    "lexical_checks_passed": true,
    "needs_semantic_critic": true
  },
  "graph_constraints": {
    "ordinal_bindings": {
      "first": "actor_1",
      "second": "actor_2"
    },
    "marked_objects": [
      {
        "id": "object_marked_ab12",
        "canonical_name": "комп",
        "allowed_aliases": ["комп", "компа", "компу"]
      }
    ],
    "must_keep_lemmas": ["курить"],
    "same_type_marker_conflict": false
  }
}
```

Правила input contract:
- augmentation не работает с rejected variants
- `generation_pass` обязан быть `base_paraphrase`
- `source_text` должен быть уже очищен от prompt artifacts
- `graph_constraints` обязан быть уже materialized upstream Track 4 и считаться authoritative persisted metadata block
- augmentation не восстанавливает `graph_constraints` ни из CIR, ни из свободного текста
- если обязательные поля `graph_constraints` отсутствуют, sample reject-ится как contract violation, а не silently деградирует

### Upstream Contract Boundary

Единственный допустимый источник `graph_constraints` в v1:
- accepted output JSONL из Track 4

Track 4 обязан persist-ить для каждого base variant:
- `ordinal_bindings`
- `marked_objects` с `id`, `canonical_name`, `allowed_aliases`
- `must_keep_lemmas`
- `same_type_marker_conflict`

Следствие:
- `04_noise_and_morphology.py` работает по одному входному JSONL и не делает дополнительный join с CIR
- если позже появится richer slot metadata, это будет расширение того же persisted блока, а не новая обязательная интеграция
- Track 6 later резолвит authoritative `cir_record` отдельно через Track 3 `CIR` JSONL по immutable `sample_id`; augmentation этот join не выполняет и не подменяет

## Output Contract

Augmentation пишет отдельный JSONL с accepted augmented variants и sidecar reject log.

Пример accepted record:

```json
{
  "sample_id": "sgv7-core-000123",
  "parent_variant_id": "sgv7-core-000123-clean-00",
  "variant_id": "sgv7-core-000123-clean-00-aug-01",
  "graph_id": "sgv7-core-000123",
  "difficulty_bucket": "core",
  "style_bucket": "clean",
  "source_text": "Два актёра идут навстречу друг другу, останавливаются у компа после этого первый начинает курить",
  "generation_pass": "augmentation",
  "augmentation_policy_version": "sgv7_augmentation_policy_v1",
  "transform_chain": [
    {
      "transform_id": "orthography.actor_yo",
      "class": "orthography_variation",
      "safety_level": "safe",
      "slot_type": "actor_head",
      "before": "актера",
      "after": "актёра"
    },
    {
      "transform_id": "noise.drop_final_punctuation",
      "class": "punctuation_noise",
      "safety_level": "safe",
      "slot_type": "sentence_tail",
      "before": ".",
      "after": ""
    }
  ],
  "risk_flags": [],
  "validation": {
    "lexical_invariants_passed": true,
    "needs_semantic_validation": true
  }
}
```

Правила:
- один output record = один augmented variant
- `parent_variant_id` обязателен
- `risk_flags` canonical живёт как top-level field; внутри `validation` дублирование запрещено
- transform metadata обязана сохранять порядок применения
- rejected candidates не пишутся в основной JSONL
- augmented sample не должен скрывать origin через перезапись `parent_variant_id`
- augmentation не имеет права переписывать `sample_id`, потому что это canonical join key для downstream Track 6 validation against Track 3 CIR

## Variant Planning Policy

V1 обязан ограничивать combinatorial growth explicit planner-ом.

### Planning Units

Planner работает не по всем комбинациям transforms, а по `augmentation recipes`.

`augmentation recipe`:
- выбирает один anchor-preserving primary transform
- опционально добавляет один punctuation/whitespace transform
- всегда уважает noise budget и safety rules

Planner не перебирает весь декартов продукт catalog-а.

### Per-Parent Caps

По умолчанию:
- `core`: максимум `1` accepted augmented variant на один `parent_variant_id`
- `hard`: максимум `2` accepted augmented variants на один `parent_variant_id`
- `hard` с `--enable-risky`: максимум `3` accepted augmented variants на один `parent_variant_id`, где не более одного risky candidate

### Allowed Composition

Для `core`:
- только safe recipes
- максимум `1` primary transform + `1` punctuation/whitespace transform

Для `hard` без risky:
- только safe recipes
- максимум `1` primary transform + `1` punctuation/whitespace transform

Для `hard` с risky:
- до одного safe recipe
- до одного safe morphology/ordinal stress recipe
- до одного risky recipe, если sample проходит risky preconditions

### Deterministic Selection Policy

Planner обязан быть deterministic по `(seed, parent_variant_id, difficulty_bucket)`.

Рекомендуемый алгоритм v1:
1. Собрать список eligible recipes по safety rules.
2. Стабильно отсортировать recipes по `(priority, recipe_id)`.
3. Применить seeded selection только к рецептам с одинаковым priority.
4. Обрезать список по `max_augmented_variants_per_parent`.

Рекомендуемый default priority:
- `core`: marked-object morphology -> ordinal stress -> orthography -> punctuation/whitespace
- `hard`: marked-object morphology -> ordinal stress -> telegraph shortening -> punctuation/whitespace -> risky recipes

Следствие:
- planner воспроизводим
- число outputs заранее ограничено
- implementer не должен сам придумывать sampling policy

Если `max_augmented_variants_per_parent=None`, модуль обязан использовать bucket defaults из раздела `Per-Parent Caps`, а не выбирать cap эвристически.

## Augmentation Classes

V1 фиксирует 6 transform classes.

### 1. Marked Object Morphology

Задача:
- варьировать surface form размеченного объекта без потери recoverable mention

Фокус v1:
- `комп -> компа -> компу`
- `ноутбук -> ноутбука`
- предлоги `у`, `около`, `возле`, `рядом с`, `к`, `мимо`

### 2. Orthography Variation

Задача:
- варьировать орфографическую поверхность без изменения леммы

Фокус v1:
- `актер` / `актёр`
- `еще` / `ещё`

### 3. Ordinal Surface Stress

Задача:
- менять форму surface-упоминания ordinal binding, не теряя `first/second`

Фокус v1:
- `первый`
- `первый актер`
- `первый актёр`
- `второй`
- `второй актер`

### 4. Actor Surface Variation

Задача:
- варьировать surface noun для роли актера без смены role binding

Фокус v1:
- `актер` / `актёр`
- только в сочетаниях, где ordinal или actor-count уже сохранены

### 5. Whitespace And Punctuation Noise

Задача:
- вносить типичный пользовательский шум

Фокус v1:
- двойные пробелы
- удаление конечной точки
- удаление одной необязательной запятой
- отсутствие пробела после запятой

### 6. Telegraph Shortening

Задача:
- делать короткие пользовательские формулировки, если chronology и anchors не теряются

Фокус v1:
- убрать служебные слова вроде `после этого`
- сократить `останавливаются около` до `стоят у` запрещено в v1, потому что это уже lexical rewrite, а не безопасное сокращение

## Safe Vs Risky Policy

### Safe transforms

По умолчанию разрешены:
- deterministic case inflection для marked-object alias из whitelist
- `е/ё` и `актер/актёр` spelling variation
- surface-wrapping ordinals: `первый` <-> `первый актер` <-> `первый актёр`
- whitespace noise
- drop final punctuation
- удаление только той запятой, которая не разделяет критичные beat-фазы

Safe transform обязан удовлетворять всем условиям:
- не меняет порядок смысловых фрагментов
- не меняет lemma critical action
- не удаляет единственное упоминание marked object
- не удаляет единственное ordinal binding
- не подменяет object alias на не-whitelisted synonym
- не требует внешней модели для применения

### Risky transforms

В каталоге фиксируются, но в v1 выключены:
- lexical synonym swap `около` -> `возле` при отсутствии уверенного slot-anchor
- aggressive telegraph shortening с удалением связок между beats
- замена `первый актер` на `1-й`
- pronounization вроде `он` вместо `первый`
- object alias clipping, если same-type marker conflict возможен
- lexical rewrite критичных действий

Risky transform может быть включен только если:
- задан `--enable-risky`
- sample не имеет `same_type_marker_conflict`
- есть полный `graph_constraints`
- post-augmentation validation включает semantic critic

## Transformation Catalog

Ниже фиксируется обязательный v1 catalog.

| Transform ID | Class | Safety | Пример | Правило |
| --- | --- | --- | --- | --- |
| `morph.marked_object.case_genitive` | marked_object_morphology | safe | `у комп` -> `у компа` | только если alias есть в whitelist |
| `morph.marked_object.case_dative` | marked_object_morphology | safe | `к комп` -> `к компу` | только для предлога, совместимого с дательным |
| `morph.marked_object.case_genitive_noutbuk` | marked_object_morphology | safe | `около ноутбук` -> `около ноутбука` | применяется к каноническому alias `ноутбук` |
| `orthography.actor_yo` | orthography_variation | safe | `актера` -> `актёра` | не меняет lemma |
| `orthography.remove_yo` | orthography_variation | safe | `ещё` -> `еще` | допустимо только для surface variation |
| `ordinal.wrap_actor_head` | ordinal_surface_stress | safe | `первый` -> `первый актер` | только если binding already known |
| `ordinal.unwrap_actor_head` | ordinal_surface_stress | safe | `второй актер` -> `второй` | нельзя удалять ordinal полностью |
| `noise.double_space` | whitespace_noise | safe | `идут навстречу` -> `идут  навстречу` | максимум один double-space на sample |
| `noise.drop_final_punctuation` | punctuation_noise | safe | `...курить.` -> `...курить` | не трогает внутренние разделители |
| `noise.drop_optional_comma` | punctuation_noise | safe | `..., останавливаются...` -> `... останавливаются...` | запрещено на границе ambiguity |
| `noise.no_space_after_comma` | punctuation_noise | safe | `идут, останавливаются` -> `идут,останавливаются` | максимум один случай на sample |
| `telegraph.drop_noncritical_connector` | telegraph_shortening | safe | `после этого` -> `` | только если beats остаются явно упорядоченными |
| `lexical.preposition_swap` | marked_object_morphology | risky | `около компа` -> `возле компа` | требует slot-anchor |
| `ordinal.numeric_form` | ordinal_surface_stress | risky | `первый` -> `1-й` | риск ухудшить parser recall |
| `telegraph.drop_subject_repeat` | telegraph_shortening | risky | `второй актер начинает` -> `второй начинает` | допустимо только при явном ordinal anchor |

## Morphology Engine Rules

V1 morphology engine не является общим морфологическим генератором русского языка. Это controlled rule engine с ограниченным словарем и шаблонами.

### Rule 1. Работать по surface slots, а не по глобальному regex-rewrite

Engine сначала выделяет candidate slots:
- `marked_object_anchor`
- `ordinal_anchor`
- `actor_head`
- `punctuation_slot`
- `connector_slot`

Предпочтительный источник slot-ов:
- explicit metadata из Track 4, если когда-нибудь появится
- иначе детерминированный local matcher по `source_text` и `graph_constraints`

### Rule 2. Хранить whitelist по alias-формам

Для каждого marked object должен быть список допустимых форм:

```json
{
  "canonical_name": "комп",
  "allowed_aliases": ["комп", "компа", "компу"]
}
```

Если нужной формы нет в whitelist, transform запрещен.

### Rule 3. Разделять preposition-governed forms

Morphology rules применяются только в совместимых рамках:
- `у X` -> родительный
- `около X` -> родительный
- `возле X` -> родительный
- `к X` -> дательный
- `мимо X` -> родительный
- `рядом с X` -> творительный только если форма явно внесена в whitelist

Следствие:
- `рядом с компом` нельзя генерировать, пока `компом` не добавлен в whitelist
- engine не склоняет слово "на глаз" по общим грамматическим правилам

### Rule 4. Не терять exact marker identity

Если в graph есть same-type marked objects, augmentation обязан сохранить distinguishing surface anchor. Поэтому:
- safe morphology разрешена только для exact alias текущего объекта
- risky clipping и pronounization запрещены
- preposition swap выключен по умолчанию

### Rule 5. Ordinal binding важнее stylistic compactness

Если scene использует `first/second/third` как structural binding:
- ordinal слово должно остаться в тексте
- разрешено оборачивать его в `первый актер` / `первый актёр`
- запрещено заменять ordinal на местоимение
- запрещено убирать ordinal, если он нужен для различения ролей

### Rule 6. Unsupported action lemma должна пережить augmentation

Для cases вроде `начинает курить`:
- augmentation может трогать пунктуацию вокруг выражения
- augmentation не может заменять lemma `курить`
- augmentation не может сокращать фразу до пустого action marker

## User-Noise Policy

User-noise transforms нужны не для "реалистичности любой ценой", а для controlled stress testing runtime parser.

### Разрешенный шум v1

- один двойной пробел в sample
- отсутствие финальной точки
- отсутствие одного пробела после запятой
- удаление одной необязательной запятой
- удаление одного не-смыслового коннектора `после этого`

### Запрещенный шум v1

- множественные опечатки в одном sample
- случайные символы
- удаление ключевого предлога перед marked object
- слияние соседних слов
- перестановка фрагментов местами
- обрыв предложения до потери последнего beat

### Noise budget

На один augmented sample:
- максимум 2 safe transforms total для `core`
- максимум 3 safe transforms total для `hard`
- не более 1 transform из категории punctuation/whitespace noise одновременно
- risky transforms не смешиваются больше одного на sample

## Traceable Metadata Contract

Каждый augmented variant обязан сохранять:
- `parent_variant_id`
- `variant_id`
- `augmentation_policy_version`
- `transform_chain`
- `risk_flags`
- `validation` summary
- `surface_anchor_snapshot`

Рекомендуемый вид `surface_anchor_snapshot`:

```json
{
  "marked_object_mentions": [
    {
      "object_id": "object_marked_ab12",
      "matched_text": "компа",
      "alias_group": "комп"
    }
  ],
  "ordinal_mentions": ["первый"],
  "critical_action_lemmas": ["курить"]
}
```

`transform_chain` обязан фиксировать:
- `transform_id`
- `class`
- `safety_level`
- `slot_type`
- `slot_index` или stable slot key
- `before`
- `after`

Это нужно для:
- reject analysis
- ablation по transform classes
- later dataset balancing по augmentation types

## Post-Augmentation Validation Plan

После применения transform chain sample проходит 5 уровней проверки.

### Layer A. Structural Preconditions

Проверяет:
- parent variant был accepted
- `generation_pass=base_paraphrase`
- `graph_constraints` присутствует полностью и соответствует upstream contract
- transform ids известны policy
- transform order детерминирован

### Layer B. Lexical Invariants

Проверяет:
- хотя бы один alias marked object остался в тексте
- ordinal binding сохранен, если требовался
- must-keep action lemma присутствует
- source_text не стал пустым и не содержит служебных маркеров

### Layer C. Safety-Class Rules

Проверяет:
- safe transform не вышел за свой noise budget
- risky transform не применен без `--enable-risky`
- same-type marker conflict не сочетается с risky alias transform

### Layer D. Recoverability Checks

Проверяет:
- local matcher по тексту все еще находит marked object
- chronology markers не схлопнулись очевидным образом
- текст остается разумно коротким для `qwen 1.5B`

### Layer E. Downstream Semantic Validation

Проверяет уже через Track 6:
- semantic critic `pass/soft_fail/hard_fail`
- no invented objects
- no ordinal loss
- no unsupported action loss
- no beat collapse

Итог policy:
- safe transform sample может попасть дальше только после прохождения Layer A-D
- risky transform sample обязан проходить и Layer E до записи в train-eligible набор

## Reject Taxonomy

Обязательные reject reasons для augmentation:
- `missing_graph_constraints_contract`
- `missing_marked_object_anchor`
- `missing_ordinal_anchor`
- `critical_action_lemma_lost`
- `same_type_marker_disambiguation_lost`
- `noise_budget_exceeded`
- `unknown_transform_id`
- `risky_transform_without_flag`
- `post_augmentation_recoverability_fail`

## Рекомендуемая структура модулей

```text
docs/SGv7pipeline/augmentation/
  __init__.py
  config.py
  catalog.py
  slots.py
  morphology.py
  noise.py
  metadata.py
  validate.py
  writer.py
  04_noise_and_morphology.py
  tests/
    test_catalog.py
    test_slots.py
    test_morphology.py
    test_noise.py
    test_validate.py
    test_augmentation_cli.py
```

## Public API

Рекомендуемый Python API:

```python
from dataclasses import dataclass
from pathlib import Path

@dataclass(frozen=True)
class AugmentationRequest:
    input_jsonl: Path
    output_jsonl: Path
    reject_log_jsonl: Path | None
    seed: int
    policy_version: str = "sgv7_augmentation_policy_v1"
    difficulty_bucket: str | None = None
    max_augmented_variants_per_parent: int | None = None
    enable_risky: bool = False

def build_transform_plan(record: dict, request: AugmentationRequest) -> list["TransformPlanItem"]: ...
def apply_transform_plan(record: dict, plan: list["TransformPlanItem"]) -> dict: ...
def validate_augmented_record(record: dict) -> list[str]: ...
def generate_augmented_variants(request: AugmentationRequest) -> "AugmentationResult": ...
```

Рекомендуемый CLI:

```bash
python docs/SGv7pipeline/augmentation/04_noise_and_morphology.py \
  --input-jsonl /tmp/sg_v7_core_sources.jsonl \
  --output-jsonl /tmp/sg_v7_core_sources_augmented.jsonl \
  --reject-log-jsonl /tmp/sg_v7_core_sources_augmented.rejects.jsonl \
  --seed 20260413 \
  --max-augmented-variants-per-parent 1 \
  --difficulty-bucket core
```

## Implementation Handoff

Инженер, реализующий `04_noise_and_morphology.py`, должен сделать в таком порядке:

1. Зафиксировать `catalog.py` с transform ids, safety level и budgets.
2. Реализовать deterministic recipe planner с per-parent caps и stable priority order.
3. Реализовать `slots.py`, который выделяет deterministic surface slots из `source_text` и persisted `graph_constraints`.
4. Реализовать `morphology.py` только через whitelist-driven substitution.
5. Реализовать `noise.py` только для v1-safe transforms.
6. Реализовать `validate.py` с reject taxonomy из этого документа.
7. Добавить CLI, sidecar reject log и metadata snapshot.

## Required Tests

Минимальные unit/smoke tests:
- `комп -> компа` сохраняет marked object anchor
- `к компу` генерируется только при наличии whitelist-формы
- `ноутбук -> ноутбука` проходит lexical invariants
- `первый актер -> первый актёр` сохраняет ordinal binding
- `второй актер -> второй` допустим только если ordinal не теряется
- double-space noise не ломает matching
- drop final punctuation не ломает matching
- same-type marker sample отвергает risky alias transform
- sample с `курить` reject-ится, если lemma исчезла после transform
- отсутствующий `graph_constraints` приводит к contract reject, а не к partial fallback
- `core` planner не выдает больше одного augmented variant на parent
- `hard --enable-risky` planner не выдает больше одного risky variant на parent
- CLI детерминированно выдает одинаковый transform plan при одном seed

## Open Questions

Неблокирующие вопросы:
- стоит ли Track 4 позже начать писать explicit `surface_slots` в metadata, чтобы Track 5 меньше полагался на локальный matcher
- нужен ли отдельный hard-only transform class для `1-й/2-й`, если runtime parser после smoke tests покажет достаточную устойчивость
- стоит ли переносить часть whitelist alias-форм в единый shared contract между runtime matcher и dataset pipeline

## Definition Of Done Mapping

Текущий design считается достаточным, если:
- implementer может написать `04_noise_and_morphology.py` без новых решений по catalog structure
- implementer не принимает сам решения о source of `graph_constraints`
- implementer не принимает сам решения о max variants per parent
- safe/risky boundary формализована
- morphology engine rules ограничены и исполнимы
- trace metadata и reject taxonomy зафиксированы
- post-augmentation validation ownership разделен между Track 5 и Track 6
