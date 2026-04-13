# 22. Source Generation Design

## Цель

Зафиксировать исполнимый дизайн `graph-to-text` слоя для `SG v7`, чтобы инженер мог реализовать `02_generate_source_variants.py` без дополнительных решений по:
- prompt contract
- style buckets
- variant counts
- anti-hallucination policy
- reject criteria
- traceable metadata

Этот документ закрывает design-часть `Track 4` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/11-implementation-backlog.md).

## Scope

Данный слой отвечает за:
- преобразование одного canonical graph в несколько русскоязычных source variants
- prompt-based paraphrasing через `gpt-5.4-nano`
- style-controlled diversification без semantic drift
- первичный lexical/reject filtering
- traceable metadata для downstream validators и dataset assembly

Данный слой не отвечает за:
- генерацию canonical JSON
- morphology/noise post-processing rules как отдельный transformation layer
- semantic critic policy как финальный gate
- train/runtime prompt-template versioning
- финальный split balancing

## Исходные зависимости

Source generation обязан переиспользовать уже зафиксированные source-of-truth артефакты:

- общий пакетный индекс: [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/README.md)
- fixed decisions: [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
- runtime failure seeds: [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- source generation policy baseline: [04-source-generation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/04-source-generation.md)
- augmentation boundary: [05-augmentation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/05-augmentation.md)
- validator stack: [06-validation-and-critics.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/06-validation-and-critics.md)
- runtime/train contract: [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)
- canonical graph contract: [19-canonical-intermediate-representation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/19-canonical-intermediate-representation.md)
- graph generator design: [21-graph-generator-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/21-graph-generator-design.md)
- legacy reference only: [generate_dataset_v6.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v6.py)

## Design Summary

Ключевое решение:
- `gpt-5.4-nano` используется только как controlled paraphraser
- graph остаётся единственным semantic source of truth
- один вызов модели генерирует ровно один variant заданного style bucket
- Track 4 ограничивается `base paraphrase layer` и генерирует только `clean`, `colloquial`, `user_short`
- morphology-heavy, ordinal-heavy и noisy surface transforms официально принадлежат Track 5 и не реализуются внутри `02_generate_source_variants.py`
- каждый variant получает explicit constraint pack и проверяемую reject taxonomy

Базовый flow:

```text
CIR graph record
  -> graph summarizer
  -> prompt payload for one style bucket
  -> nano paraphrase candidate
  -> lexical policy checks
  -> reject / accept with reason
  -> accepted source variant + metadata
  -> downstream semantic critic + recoverability validator
```

## Почему нужен отдельный source generation layer

Если сразу смешать:
- paraphrase
- morphology stress
- orthography noise
- colloquial drift
- validator feedback

то становится трудно понять, где именно потерялись:
- chronology
- marked object grounding
- ordinal mapping
- unsupported action wording

Поэтому первая стадия должна давать контролируемый, семантически плотный paraphrase, а unsafe variation переносится в augmentation layer.

## Input Contract

`02_generate_source_variants.py` принимает валидные graph records, построенные Track 3. Минимальный вход для source generator:

```json
{
  "sample_id": "sgv7-core-000123",
  "difficulty_bucket": "core",
  "pattern_name": "toward_each_other_then_stop_near_marked_object",
  "scene_graph": {
    "actors": ["actor_1", "actor_2"],
    "objects": ["object_marked_ab12"],
    "beats": [
      "actors move toward each other",
      "actors stop near object_marked_ab12",
      "actor_1 performs described_action sourced from smoking wording"
    ],
    "reference_bindings": {
      "ordinal_bindings": {
        "first": "actor_1",
        "second": "actor_2"
      },
      "marked_object_ids": ["object_marked_ab12"],
      "alias_to_object_id": {
        "комп": "object_marked_ab12"
      }
    }
  }
}
```

Реальная схема определяется `CIR`, но для prompt-builder обязательны следующие derived поля:
- `graph_summary`
- `must_keep_semantics`
- `must_not_introduce`
- `allowed_aliases_for_marked_objects`
- `same_type_disambiguation_block` при 2+ marked objects одного `type`
- `style_bucket`
- `difficulty_bucket`
- `ordinal_bindings`
- `beat_outline`

## Output Contract

Первая версия source generator пишет JSONL, где каждая строка описывает один accepted variant:

```json
{
  "sample_id": "sgv7-core-000123",
  "variant_id": "sgv7-core-000123-clean-00",
  "graph_id": "sgv7-core-000123",
  "difficulty_bucket": "core",
  "style_bucket": "clean",
  "source_text": "Два актера идут навстречу друг другу, останавливаются у компа, после этого первый начинает курить.",
  "model_name": "gpt-5.4-nano",
  "prompt_template_version": "sgv7_source_prompt_v1",
  "source_policy_version": "sgv7_source_policy_v1",
  "generation_pass": "base_paraphrase",
  "attempt_index": 0,
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

Правила:
- один record = один variant
- rejected варианты в основной JSONL не пишутся
- reject log хранится отдельно как sidecar JSONL
- `source_text` не должен содержать служебные маркеры prompt-а
- `style_bucket` обязателен и не выводится эвристически downstream-слоями
- persisted `source_text` хранится уже в train-ready normalized form по policy из раздела `Source Text Normalization Policy`
- Track 4 обязан persist-ить минимальный `graph_constraints` block для Track 5; augmentation не должен восстанавливать эти поля эвристически из CIR или из свободного текста
- минимальный `graph_constraints` block обязан включать:
- `ordinal_bindings`
- `marked_objects` с `id`, `canonical_name`, `allowed_aliases`
- `must_keep_lemmas`
- `same_type_marker_conflict`
- Track 6 обязан валидировать эти variants вместе с authoritative Track 3 `CIR` JSONL, используя immutable join key `sample_id`
- Track 4 не имеет права переписывать `sample_id` и не должен reconstruct-ить `cir_record` downstream-слоям эвристически

## Рекомендуемая структура модулей

```text
docs/SGv7pipeline/source_generation/
  __init__.py
  config.py
  prompt_builder.py
  style_policy.py
  batcher.py
  filters.py
  metadata.py
  writer.py
  02_generate_source_variants.py
  tests/
    test_prompt_builder.py
    test_style_policy.py
    test_filters.py
    test_source_generator_cli.py
```

## Public API

Рекомендуемый Python API:

```python
from dataclasses import dataclass
from pathlib import Path

@dataclass(frozen=True)
class SourceGenerationRequest:
    input_jsonl: Path
    output_jsonl: Path
    reject_log_jsonl: Path | None
    seed: int
    model_name: str = "gpt-5.4-nano"
    prompt_template_version: str = "sgv7_source_prompt_v1"
    policy_version: str = "sgv7_source_policy_v1"
    max_variants_per_graph: int | None = None
    difficulty_bucket: str | None = None

def build_variant_plan(request: SourceGenerationRequest) -> list["VariantPlanItem"]: ...
def generate_source_variants(request: SourceGenerationRequest) -> "SourceGenerationResult": ...
def evaluate_candidate_text(candidate: str, plan_item: "VariantPlanItem") -> list[str]: ...
```

Рекомендуемый CLI:

```bash
python docs/SGv7pipeline/source_generation/02_generate_source_variants.py \
  --input-jsonl /tmp/sg_v7_core_graphs.jsonl \
  --output-jsonl /tmp/sg_v7_core_sources.jsonl \
  --reject-log-jsonl /tmp/sg_v7_core_sources.rejects.jsonl \
  --seed 20260413 \
  --difficulty-bucket core
```

## Prompt Strategy

Один model call генерирует один variant заданного style bucket. Это нужно для:
- traceability
- управляемых retries
- явной reject reason taxonomy
- отсутствия скрытого смешения стилей

### System Prompt Template

Рекомендуемый system prompt:

```text
Ты делаешь только controlled paraphrase русского пользовательского описания сцены.
Ты не придумываешь новые события, объекты, роли, реплики или причины действий.
Ты обязан сохранить chronology, actor bindings, ordinal references и exact grounding marked objects.
Если действие не поддерживается каноническими action labels, ты не заменяешь его другим действием, а пересказываешь исходный смысл простыми словами.
Верни только один русский source text без пояснений и без списка.
```

### User Prompt Template

Рекомендуемый user prompt первой версии:

```text
Собери один {style_bucket} вариант русского пользовательского описания сцены.

Canonical graph summary:
{graph_summary}

Chronology to preserve:
{beat_outline}

Ordinal bindings:
{ordinal_bindings}

Marked objects:
{marked_object_block}

Must keep:
{must_keep_semantics}

Must not introduce:
{must_not_introduce}

Style rules for this bucket:
{style_rules}

Hard constraints:
- не добавляй новые события
- не добавляй новые объекты
- не убирай marked object mention, если он есть в графе
- не теряй слова первый/второй/третий, если ordinal binding нужен для recoverability
- не схлопывай несколько beats в один расплывчатый факт
- не превращай unsupported action в talk или в другое поддерживаемое действие
- не пиши пояснений, списков и JSON

Верни только один финальный source text на русском языке.
```

## Prompt Payload Contract

### `graph_summary`

Короткое, механически собранное summary без лишней prose-литературности. Не больше 4-6 строк.

### `beat_outline`

Каждый beat подаётся отдельно в canonical порядке:

```text
1. actor_1 and actor_2 move toward each other
2. both stop near object_marked_ab12 (aliases: комп, компьютер)
3. actor_1 performs described_action based on source wording about smoking
```

### `marked_object_block`

Для каждого marked object:

```text
- id: object_marked_ab12
  type: generic
  preferred_aliases: комп, компьютер
  morphology_examples: у компа, около компа, возле компьютера
```

`morphology_examples` нужны как разрешённые surface forms, но не как обязательные формулировки.

### `same_type_disambiguation_block`

Если в graph есть 2+ marked objects одного `type`, prompt-builder обязан добавить отдельный disambiguation block:

```text
Same-type marker disambiguation:
- object_marked_a1: preferred alias "левый ноутбук", fallback cues: "ноутбук слева", "первый ноутбук у стены"
- object_marked_b2: preferred alias "правый ноутбук", fallback cues: "ноутбук справа", "второй ноутбук ближе к двери"
- source must mention the targeted object with one explicit distinguishing cue
```

Правила:
- в prompt нельзя полагаться только на `type`
- если target graph требует exact marker grounding, source обязан содержать хотя бы один distinguishing cue
- distinguishing cue выбирается из whitelist, построенного из alias, spatial cue или ordinal cue
- если безопасного distinguishing cue нет, graph должен идти в review/backlog, а не в silent generation

### `must_keep_semantics`

Явный список атомарных инвариантов:
- actor count
- beat count or beat phases
- required object grounding
- ordinal binding
- unsupported action wording anchor

### `must_not_introduce`

Явный список запретов:
- новый объект
- новая реплика
- новый мотив или эмоция
- новая развязка
- перенос действия в другой порядок

## Style Buckets

Track 4 реализует только base paraphrase buckets. Stress/noise buckets остаются частью общего pipeline vocabulary, но их materialization принадлежит Track 5.

### Buckets Owned By Track 4

### `clean`

Назначение:
- базовый максимально recoverable paraphrase

Правила:
- короткий прямой русский
- без сленга
- без намеренного шума
- сохранить все ключевые anchors в явной форме

### `colloquial`

Назначение:
- разговорная пользовательская подача без semantic drift

Правила:
- допустимы бытовые слова: `комп`, `ноут`, `телик`
- синтаксис может быть разговорным, но без эллипсиса, скрывающего chronology
- не использовать редкий жаргон

### `user_short`

Назначение:
- сжатая формулировка, похожая на короткий пользовательский ввод

Правила:
- максимум 1-2 предложения
- допустима телеграфность
- нельзя жертвовать ordinal или marked object anchors ради краткости

### Buckets Deferred To Track 5

Следующие buckets не генерируются в `02_generate_source_variants.py`, а строятся только как controlled post-processing поверх accepted base variants:

### `user_noisy`

Назначение:
- лёгкий шум, который остаётся recoverable без отдельного augmentation layer

Правила:
- допустимы лишние пробелы и отсутствие точки
- допустимы `актер/актёр`, `еще/ещё`
- нельзя одновременно добавлять сильный шум и редкую лексику

### `morphology_stress`

Назначение:
- проверить устойчивость к косвенным формам marked objects

Правила:
- хотя бы один marked object упоминается в косвенной форме
- morphology stress применяется только к разрешённым alias-ам
- нельзя менять referent или заменять marker на общий тип объекта

### `ordinal_stress`

Назначение:
- усилить recoverability `first/second/third`

Правила:
- в тексте явно присутствуют ordinal references
- запрещено заменять ordinal на неоднозначное `он/она`
- при 3 актёрах требуется явный `третий`, если он есть в graph binding

## Variant Count Policy

Рекомендуемые counts на один graph:

### `core`

- `clean`: 1
- `colloquial`: 1
- `user_short`: 1

Итого:
- типичный `core` в Track 4: 3 variants

### `hard`

- `clean`: 1
- `colloquial`: 1
- `user_short`: 1

Итого:
- типичный `hard` в Track 4: 3 variants

Ограничения:
- Track 4 не генерирует больше 3 base variants на graph в первой версии
- `clean` обязателен всегда
- morphology/noise/ordinal stress variants появляются только после Track 5

### End-To-End Pipeline Note

Полный pipeline по-прежнему может выдавать `3-6` source variants на graph, но ownership разделён так:
- Track 4: `clean`, `colloquial`, `user_short`
- Track 5: `user_noisy`, `morphology_stress`, `ordinal_stress` и другие controlled transforms

## Anti-Hallucination Constraints

Source generator обязан явно защищать следующие инварианты:

### Chronology invariants

- порядок beats нельзя менять
- нельзя опускать промежуточный beat, если он отличает failure case
- нельзя схлопывать `approach -> stop near object -> described action` в одну размывчатую фразу

### Marked object invariants

- если graph содержит marked object grounding, source обязан сохранить упоминание этого referent-а
- same-type marked objects нельзя заменять общим словом без различителя
- morphology variation допустима только внутри alias whitelist
- если есть `same_type_disambiguation_block`, source обязан использовать хотя бы один distinguishing cue из него

### Same-Type Marker Disambiguation Policy

При 2+ marked objects одного `type` действуют дополнительные правила:
- `clean` обязан использовать preferred alias или explicit spatial cue для target marker-а
- `colloquial` может упростить лексику, но не имеет права убирать distinguishing cue
- `user_short` может сокращать синтаксис, но не имеет права убирать единственный disambiguating token
- запрещено генерировать text, где target marker восстанавливается только эвристикой по контексту
- отдельный reject reason: `same_type_marker_disambiguation_loss`

### Ordinal invariants

- `first/second/third` должны сохраняться, если они нужны для actor binding
- нельзя заменять ordinal reference на местоимение, если это делает восстановление неоднозначным

### Unsupported action invariants

- wording про `курить`, `закуривать`, `начинать курить` не должен превращаться в `говорит`, `ждёт`, `стоит`
- paraphrase может упростить формулировку, но не semantic class

### Dialogue invariants

- если graph не содержит dialogue acts, source не должен придумывать реплики
- если dialogue есть, source не должен подменять его новым текстом

## Reject Ownership Boundary

Ownership reject policy фиксируется так:
- Track 4 (`02_generate_source_variants.py`) владеет только `lexical_or_format_reject`
- Track 6 владеет `semantic_hard_reject`
- accepted output Track 4 обязан быть помечен как `needs_semantic_critic=true`, пока Track 6 не подтвердит семантическую корректность

Это значит:
- Track 4 не объявляет sample финально пригодным для train
- Track 4 отвечает только за prompting, style compliance, formatting, required surface anchors и traceable metadata
- semantic claims уровня chronology preservation, object grounding completeness и unsupported action fidelity закрываются в validator stack

## Reject Policy

Reject policy делится на hard reject и soft reject.

### Track 4 Hard Reject

Это reject-ы, которые `02_generate_source_variants.py` обязан применять сам без semantic critic:

- ответ пустой или не на русском
- ответ содержит JSON, список, комментарий или мета-объяснение
- текст не проходит bucket length budget
- отсутствует required ordinal token, когда он обязателен в base prompt
- отсутствует required marked-object alias из whitelist, когда object grounding должен быть surface-visible
- при `same_type_disambiguation_block` отсутствует обязательный distinguishing cue
- candidate дублирует уже принятый variant после dedup normalization

### Track 6 Semantic Hard Reject

Это reject-ы, которые применяются только validator/critic stack-ом после Track 4:

- появился новый объект
- появился новый beat или новая причина действия
- исчезло упоминание обязательного marked object
- потерялась ordinal reference, обязательная для recoverability
- chronology перестала совпадать с graph order
- unsupported action заменён на другой смысл
- появился диалог там, где его не было

### Soft Reject

Variant идёт на retry, если:
- стиль не соответствует bucket policy
- текст слишком длинный для `user_short`
- текст почти дублирует уже принятый variant того же graph
- `colloquial` не отличается от `clean` на surface level
- `user_short` получился слишком развёрнутым и stylistically indistinguishable from `clean`

## Lexical And Structural Checks Before Critic

До semantic critic допускаются только кандидаты, прошедшие cheap checks:

- `non_empty`
- `single_paragraph`
- `not_json_like`
- `not_bulleted`
- `contains_cyrillic`
- `length_within_bucket_budget`
- `contains_required_alias`
- `contains_required_ordinal_token`
- `contains_required_disambiguation_cue`
- `not_duplicate_of_existing_variant`

Первая версия не должна пытаться "чинить" candidate text автоматически. На base paraphrase layer policy только две:
- reject
- retry

## Source Text Normalization Policy

Track 4 сохраняет `source_text` не как raw model output, а как persisted train-ready text.

### Persisted normalization for accepted `source_text`

Перед записью accepted variant применяются:
- trim по краям
- conversion of internal newlines to single spaces
- collapse repeated spaces to single space
- Unicode normalization to NFC
- сохранение букв `ё/е` как в финальном accepted тексте, без принудительного сведения

Не применяются:
- удаление разговорной лексики
- spell correction
- semantic rewriting
- noise injection

### Dedup-only normalization

Нормализация для dedup key остаётся более агрессивной и не меняет persisted `source_text`:
- trim
- collapse repeated spaces
- lowercase
- safe `ё -> е` projection только для dedup key

### Runtime/train alignment rule

Persisted `source_text` из Track 4 должен совпадать с тем видом текста, который потом увидит training prompt builder до runtime-safe preprocessing. Если позже Track 5 добавляет noisy variants, он обязан:
- либо хранить их в отдельном поле surface-preserving artifact layer
- либо явно документировать дополнительную normalization policy, совместимую с [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)

## Dedup Strategy

Dedup нужен на двух уровнях:

### Intra-graph dedup

Варианты одного graph не должны отличаться только:
- точкой на конце
- `ё/е`
- двойным пробелом
- перестановкой союзов без change in style bucket

### Cross-graph dedup

Первая версия может ограничиться exact normalized text dedup только внутри одного build-а, чтобы не переполнять dataset одинаковыми short prompts.

Нормализация для dedup:
- trim
- collapse repeated spaces
- lowercase
- safe `ё -> е` projection только для dedup key

## Traceable Metadata

Каждый accepted variant обязан хранить:
- `sample_id`
- `graph_id`
- `pattern_name`
- `difficulty_bucket`
- `style_bucket`
- `attempt_index`
- `prompt_template_version`
- `source_policy_version`
- `model_name`
- `generation_pass`
- `seed`

Каждый reject log record обязан дополнительно хранить:
- `reject_stage`
- `reject_reason`
- `candidate_text`

Это нужно, чтобы downstream слой понимал:
- что отбрасывается на lexical этапе
- какие buckets нестабильны
- где нужна корректировка prompt wording

## Batching And Retry Policy

### Batching

- группировать запросы по `style_bucket`
- не смешивать в одном batch-е `core` и `hard`, если у них разные retry budgets
- один batch item содержит один graph и один style bucket

### Retry

Рекомендуемый retry budget:
- `clean`: до 2 попыток
- `colloquial`: до 2 попыток
- `user_short`: до 2 попыток

Эскалация при retry:
- первая попытка: базовый prompt
- вторая попытка: добавить `previous_reject_reason`
- третья попытка: усилить только релевантное ограничение, не переписывая весь prompt contract

Если bucket не собрал variant в пределах retry budget:
- граф не должен silently терять обязательный `clean`
- optional buckets можно пропустить, но это должно быть отражено в metadata/manifest

## Quality Checklist

Перед пометкой variant как ready-for-validation нужно пройти checklist:

- текст на русском и выглядит как пользовательское описание сцены
- chronology beats читается в правильном порядке
- actor count не схлопнулся
- required marked object упомянут
- ordinal anchor сохранён, если нужен
- required disambiguation cue сохранён, если graph содержит same-type markers
- unsupported action не нормализован до ложного supported action
- нет invented dialogue
- bucket действительно отличается от `clean`, если это не `clean`
- текст остаётся recoverable для модели `qwen 1.5B`

## Implementation Handoff For `02_generate_source_variants.py`

### Обязательные функции первой версии

- `summarize_graph_for_source_prompt(record)`
- `build_source_prompt(plan_item)`
- `derive_variant_plan(record, difficulty_bucket)`
- `call_paraphraser(prompt, model_name)`
- `run_cheap_reject_filters(candidate, plan_item)`
- `extract_required_surface_anchors(record)`
- `write_accept_record(record)`
- `write_reject_record(record)`

### Обязательные CLI флаги первой версии

- `--input-jsonl`
- `--output-jsonl`
- `--reject-log-jsonl`
- `--seed`
- `--difficulty-bucket`
- `--max-graphs`
- `--max-variants-per-graph`
- `--model-name`

### Обязательные smoke tests

- graph с marked object в morphology form
- graph с `first/second`
- graph с `described_action` про курение
- graph с multi-beat chronology
- graph с двумя marked objects одного типа
- graph, где `colloquial` обязан сохранить same-type disambiguation cue

## Open Questions

- стоит ли первой версии сразу писать отдельный manifest по coverage buckets или достаточно reject log + accepted JSONL
- нужен ли отдельный `style_bucket_version` или достаточно общего `source_policy_version`

## Definition Of Done Mapping

`design` для Prompt 4 считается закрытым, если по этому документу инженер может:
- реализовать `02_generate_source_variants.py`
- собрать prompt pack без новых архитектурных решений
- понять exact reject boundary между source generation и augmentation
- воспроизвести variant counts и style bucket policy

## Где зафиксирован результат

Этот дизайн является source-of-truth артефактом для `Track 4` и должен быть доступен из:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/README.md)
- [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/11-implementation-backlog.md)
