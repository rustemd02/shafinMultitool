# 30. Validator Stack Design

## Цель

Зафиксировать исполнимый дизайн validator stack и semantic critic для `SG v7`, чтобы инженер мог реализовать:
- `docs/SGv7pipeline/validators/03_semantic_critic.py`
- `docs/SGv7pipeline/validators/05_validate_and_pack.py`

без дополнительных архитектурных решений по:
- слоям validation
- hard reject vs manual review policy
- critic prompt contract
- recoverability scoring
- reject taxonomy
- packaging boundary для downstream dataset assembly

Этот документ закрывает design-часть `Track 6` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/11-implementation-backlog.md).

## Scope

Track 6 отвечает за:
- deterministic validation accepted кандидатов из Track 4 и Track 5
- semantic critic поверх уже прошедших cheap checks samples
- явное разделение `accepted` / `manual_review` / `rejected`
- recoverability scoring для `qwen 1.5B`
- packaging validation metadata для Track 7
- enforcement provenance policy для real corrected samples

Track 6 не отвечает за:
- генерацию graph records
- paraphrase generation
- morphology/noise transforms
- финальный train/val/test split builder
- runtime serializer redesign
- автоматический repair target JSON

## Исходные зависимости

Validator stack обязан переиспользовать уже зафиксированные source-of-truth артефакты:

- общий индекс пакета: [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/README.md)
- fixed decisions: [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
- runtime failure seeds: [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- baseline validator policy: [06-validation-and-critics.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/06-validation-and-critics.md)
- dataset assembly contract: [07-dataset-assembly.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/07-dataset-assembly.md)
- eval metrics and release semantics: [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md)
- runtime/train contract: [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)
- canonical CIR contract: [19-canonical-intermediate-representation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/19-canonical-intermediate-representation.md)
- graph generator design: [21-graph-generator-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/21-graph-generator-design.md)
- source generation design: [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md)
- augmentation design: [27-augmentation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/27-augmentation-design.md)
- canonical entrypoint: [generate_dataset_v7.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v7.py)
- legacy comparison only: [generate_dataset_v6.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v6.py)

## Design Summary

Ключевое решение:
- validator stack работает после Track 4 и Track 5, а не внутри них
- cheap deterministic validators идут раньше LLM critic и уменьшают стоимость
- critic не принимает решение в одиночку: финальный verdict строится как `deterministic checks + critic verdict + recoverability score + provenance policy`
- hard semantic failures reject-ятся сразу
- borderline cases уходят в `manual_review`, а не silently попадают в train
- `05_validate_and_pack.py` не только валидирует, но и пишет готовые artifacts для Track 7 с traceable metadata

Базовый flow:

```text
accepted source/augmentation candidate
  -> ingress contract checks
  -> provenance gate
  -> schema + graph integrity validators
  -> semantic anchor checks
  -> LLM semantic critic
  -> recoverability scoring
  -> hard reject / manual review / accepted
  -> package validated JSONL + review queue + reject log + manifest
```

## Почему critic вынесен в отдельный слой

Если semantic critic встроить прямо в source generation или augmentation, становится трудно понять:
- candidate был плохим из-за prompt drift
- transform разрушил recoverability
- deterministic policy была слишком слабой
- provenance sample-а вообще не позволял direct-train admission

Отдельный Track 6 даёт:
- единый semantic gate для synthetic и real corrected data
- общую taxonomy reject reasons
- общие thresholds для `core`, `hard` и reviewed buckets
- совместимость с release metrics из [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md)

## Input Contract

Первая версия `05_validate_and_pack.py` должна принимать один JSONL из трёх допустимых upstream sources:
- accepted base variants из Track 4
- accepted augmented variants из Track 5
- real corrected samples, уже приведённые к SG v7 metadata contract

Canonical input mode для synthetic Track 4 / Track 5:
- `input_jsonl` содержит candidate envelope
- `cir_jsonl` содержит Track 3 canonical CIR records
- Track 6 обязан резолвить `cir_record` только deterministic join-ом по immutable `sample_id`
- эвристическое восстановление `cir_record` из `source_text`, `graph_constraints` или `pattern_name` запрещено

Допустимый fallback mode для real corrected samples:
- sample уже содержит embedded `cir_record`
- если embedded `cir_record` есть, Track 6 всё равно обязан проверить совпадение `sample_id`

Минимальный входной record для Track 4 / Track 5 envelope:

```json
{
  "sample_id": "sgv7-core-000123",
  "graph_id": "sgv7-core-000123",
  "difficulty_bucket": "core",
  "source_text": "Два актера идут навстречу друг другу, останавливаются у компа, после этого первый начинает курить.",
  "generation_pass": "base_paraphrase",
  "pattern_name": "toward_each_other_then_stop_near_marked_object",
  "correction_tier": "tier_b_deterministic_canonical",
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
- `sample_id` обязателен и должен считаться immutable contract field
- для source/augmentation candidates Track 6 обязан получать authoritative `cir_record` через `--cir-jsonl` join по `sample_id`
- для reviewed/corrected samples допустим embedded `cir_record`, но он всё равно обязан быть валиден по `sg_v7_cir_v1`
- `graph_constraints` считаются authoritative persisted metadata block из upstream слоя, а не восстанавливаются эвристически
- `correction_tier` обязателен для real corrected и reviewed samples; для pure synthetic v1 допускается materialized `tier_b_deterministic_canonical`
- `generation_pass` обязателен для понимания происхождения sample-а
- если вход не удовлетворяет contract-у, sample reject-ится как `contract_violation`, а не чинится молча

### CIR Resolution Policy

Track 6 обязан иметь ровно один source of truth для canonical graph:
- Track 3 `CIR` JSONL

Правило join-а v1:
- join key: `sample_id`
- source/augmentation envelope не имеет права переписывать `sample_id`
- если по `sample_id` не найден ровно один `cir_record`, sample reject-ится

Обязательные reject reasons:
- `contract_missing_cir_join_source`
- `contract_cir_join_not_found`
- `contract_cir_join_non_unique`

Следствие:
- `05_validate_and_pack.py` реализуется без реконструкции графа
- Track 4 и Track 5 не обязаны дублировать весь `cir_record` в каждом accepted record
- real corrected inputs могут использовать embedded `cir_record`, но canonical batch path для synthetic данных остаётся join-based

## Output Contract

Track 6 пишет четыре набора артефактов:
- `accepted.jsonl`
- `manual_review.jsonl`
- `rejected.jsonl`
- `validation_manifest.json`

Каждый processed sample обязан получить `validation_report`.

Пример accepted record:

```json
{
  "sample_id": "sgv7-core-000123",
  "graph_id": "sgv7-core-000123",
  "difficulty_bucket": "core",
  "correction_tier": "tier_b_deterministic_canonical",
  "source_text": "Два актера идут навстречу друг другу, останавливаются у компа, после этого первый начинает курить.",
  "validation_status": "accepted",
  "train_eligibility": "direct_sft",
  "validation_report": {
    "validator_stack_version": "sgv7_validator_stack_v1",
    "schema_checks_passed": true,
    "graph_checks_passed": true,
    "anchor_checks_passed": true,
    "critic_verdict": "pass",
    "critic_model": "gpt-5.4-nano",
    "critic_artifact_id": "critic-sgv7-core-000123-v1",
    "critic_execution": {
      "temperature": 0,
      "top_p": 1,
      "max_output_tokens": 300,
      "recomputed": false
    },
    "recoverability_score": 93,
    "recoverability_band": "high",
    "review_required": false,
    "reject_reasons": [],
    "review_reasons": [],
    "semantic_findings": [],
    "bucket_metrics": {
      "marked_object_recall_expected": 1,
      "ordinal_binding_expected": 1,
      "must_keep_lemma_expected": 1
    }
  }
}
```

Пример review record:

```json
{
  "sample_id": "sgv7-hard-000044",
  "difficulty_bucket": "hard",
  "correction_tier": "tier_c_reviewed_merge",
  "validation_status": "manual_review",
  "train_eligibility": "review_only",
  "validation_report": {
    "critic_verdict": "soft_fail",
    "recoverability_score": 74,
    "recoverability_band": "borderline",
    "review_required": true,
    "review_reasons": [
      "review_same_type_marker_conflict",
      "review_critic_soft_fail"
    ]
  }
}
```

Правила:
- `accepted` не означает automatic inclusion in final train split; это означает, что sample прошёл Track 6 и может быть использован downstream по `train_eligibility`
- `manual_review` обязателен для borderline semantic cases и trust-tier escalation
- `rejected` sample сохраняет полный trace reject reasons и, если запускался critic, critic summary
- `validation_report` является persisted metadata block для Track 7 и future eval harness
- `correction_tier` обязан persist-иться в `accepted`, `manual_review` и `rejected` artifacts; Track 7 не должен восстанавливать provenance повторным чтением upstream input

## Ownership Boundary

Ownership между треками фиксируется так:

- Track 4 владеет только lexical/format acceptance базовых variants
- Track 5 владеет transform safety и local post-augmentation guards
- Track 6 владеет финальным semantic accept/reject/review verdict
- Track 7 владеет split building и balancing, но не переоценивает semantic verdict заново

Следствие:
- `needs_semantic_critic=true` из Track 4 и Track 5 снимается только Track 6
- Track 7 не должен самостоятельно повышать `manual_review` sample до `accepted`
- `train_eligibility` вычисляется в Track 6 из `validation_status + correction_tier`, а не из split builder heuristics

## Рекомендуемая структура модулей

```text
docs/SGv7pipeline/validators/
  __init__.py
  config.py
  contracts.py
  provenance.py
  schema_checks.py
  graph_checks.py
  anchor_checks.py
  critic_prompts.py
  semantic_critic.py
  recoverability.py
  taxonomy.py
  packaging.py
  writer.py
  03_semantic_critic.py
  05_validate_and_pack.py
  tests/
    test_provenance.py
    test_schema_checks.py
    test_graph_checks.py
    test_anchor_checks.py
    test_recoverability.py
    test_packaging.py
    test_validate_and_pack_cli.py
```

## Public API

Рекомендуемый Python API:

```python
from dataclasses import dataclass
from pathlib import Path

@dataclass(frozen=True)
class ValidationRequest:
    input_jsonl: Path
    cir_jsonl: Path | None
    accepted_jsonl: Path
    review_jsonl: Path
    rejected_jsonl: Path
    manifest_json: Path
    seed: int
    critic_model: str = "gpt-5.4-nano"
    critic_temperature: float = 0.0
    critic_top_p: float = 1.0
    critic_max_output_tokens: int = 300
    validator_stack_version: str = "sgv7_validator_stack_v1"
    enable_critic: bool = True
    difficulty_bucket: str | None = None

def run_semantic_critic(sample: dict, request: ValidationRequest) -> "CriticResult": ...
def validate_sample(sample: dict, request: ValidationRequest) -> "ValidationDecision": ...
def validate_and_pack(request: ValidationRequest) -> "ValidationRunResult": ...
```

Рекомендуемый CLI для critic smoke:

```bash
python docs/SGv7pipeline/validators/03_semantic_critic.py \
  --input-json /tmp/sg_v7_candidate.json \
  --output-json /tmp/sg_v7_candidate.critic.json
```

Рекомендуемый CLI для batch validation:

```bash
python docs/SGv7pipeline/validators/05_validate_and_pack.py \
  --input-jsonl /tmp/sg_v7_candidates.jsonl \
  --cir-jsonl /tmp/sg_v7_graphs.jsonl \
  --accepted-jsonl /tmp/sg_v7_accepted.jsonl \
  --review-jsonl /tmp/sg_v7_review.jsonl \
  --rejected-jsonl /tmp/sg_v7_rejected.jsonl \
  --manifest-json /tmp/sg_v7_validation_manifest.json \
  --seed 20260413
```

## Layered Validator Architecture

### Layer 0. Ingress Contract Binding

Проверяет:
- наличие `sample_id`, `graph_id`, `difficulty_bucket`, `source_text`
- наличие canonical CIR source: либо resolved join из `cir_jsonl`, либо embedded `cir_record`
- согласованность `sample_id` между envelope и resolved `cir_record.sample_id`
- допустимость `generation_pass`
- наличие обязательного `graph_constraints`

Hard reject:
- `contract_missing_required_field`
- `contract_missing_cir_join_source`
- `contract_cir_join_not_found`
- `contract_cir_join_non_unique`
- `contract_sample_id_mismatch`
- `contract_missing_graph_constraints`
- `contract_unknown_generation_pass`

### Layer 1. Provenance Gate

Проверяет:
- присутствует ли `correction_tier`
- разрешён ли этот tier для заявленного candidate type
- можно ли этому sample вообще претендовать на `direct_sft`

Политика:
- `tier_a_human_gold` -> может идти в `direct_sft`
- `tier_b_deterministic_canonical` -> может идти в `direct_sft` после strict pass
- `tier_c_reviewed_merge` -> минимум `manual_review`; даже после pass не выше `hard_or_preference_only`
- `tier_d_auto_repair_only` -> никогда не direct train eligible

Hard reject:
- неизвестный provenance tier
- отсутствующий tier для real corrected sample

Manual review:
- любой `tier_c_reviewed_merge`
- любой запрос на повышение доверия `tier_d_auto_repair_only`

### Layer 2. Schema And Runtime Projection Checks

Проверяет:
- `cir_record` проходит `validate_record(...)`
- serializer boundary через [generate_dataset_v7.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v7.py) не ломается
- runtime projection rules берутся из [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md), а не выводятся эвристически
- `described_action` obey required runtime fields
- id formats и enum values остаются допустимыми

Обязательные projection invariants v1:
- resolved `cir_record.runtime_projection.target_schema == "SceneScript"`
- `described_action` после deterministic projection содержит runtime-required `sourceText` и `fallbackText`
- `build_scene_script(...)` / `serialize_to_scenescript(...)` не падает на record-е
- `originalDescription` берётся из candidate `source_text` без отдельного rewrite слоя в Track 6
- validator не меняет serializer policy и не нормализует contract drift post-hoc

Hard reject:
- `schema_invalid_cir`
- `schema_invalid_described_action`
- `runtime_projection_failure`

### Layer 3. Graph Consistency Checks

Проверяет:
- все action targets существуют
- нет dangling actor/object references
- `holdingObject` и relation targets валидны
- beat/action ids уникальны
- actor/object cardinality соответствует budgets

Особый фокус:
- `dangling_target` всегда считается hard reject
- same-type markers проверяются по exact `object_marked_*`, а не только по `type`

Hard reject:
- `graph_dangling_target`
- `graph_missing_actor`
- `graph_missing_object`
- `graph_duplicate_action_id`
- `graph_duplicate_beat_id`

### Layer 4. Semantic Anchor Checks

Это deterministic bridge между graph и surface text.

Проверяет:
- marked object alias из whitelist реально восстановим в `source_text`
- ordinal anchor присутствует, если sample recoverability-sensitive по ordinal binding
- must-keep lemma для unsupported action или critical described action не потеряна
- same-type marker disambiguation cue присутствует, если `same_type_marker_conflict=true`
- dialogue constraints не нарушены

Hard reject:
- `semantic_marked_object_lost`
- `semantic_ordinal_anchor_lost`
- `semantic_critical_action_lemma_lost`
- `semantic_same_type_disambiguation_lost`
- `semantic_invented_dialogue`

### Layer 5. LLM Semantic Critic

Критику отправляются только samples, прошедшие Layer 0-4.

Критик оценивает:
- сохранён ли object grounding
- не схлопнулась ли chronology и beats
- не потерялся ли unsupported action
- не появились ли invented objects/actions/dialogue
- не разрушилась ли exact binding для same-type marked objects

Допустимые verdicts:
- `pass`
- `soft_fail`
- `hard_fail`

Правило интерпретации:
- `hard_fail` -> `rejected`
- `soft_fail` -> минимум `manual_review`
- `pass` не гарантирует acceptance без учёта score и provenance

### Critic Execution Freeze Policy

Чтобы recoverability scoring оставался воспроизводимым, Track 6 фиксирует critic как persisted artifact, а не как live re-check на каждом шаге.

Обязательные правила v1:
- один sample -> максимум один canonical critic run в рамках одного validation run
- результат critic сохраняется в `validation_report` как persisted artifact с `critic_artifact_id`
- recoverability scoring читает только persisted critic fields из этого artifact
- `05_validate_and_pack.py` не имеет права заново вызывать critic при повторной упаковке уже прокритикованного sample-а
- если critic artifact уже присутствует и его execution params совпадают, Track 6 обязан переиспользовать его, а не recompute-ить
- если critic artifact отсутствует, run может создать его ровно один раз до scoring

Frozen execution params v1:
- `model = gpt-5.4-nano`
- `temperature = 0`
- `top_p = 1`
- `max_output_tokens = 300`
- response format = strict JSON schema из этого документа

Если execution params не совпадают с persisted artifact:
- sample не должен silently rescoring-ться
- run должен либо reject-нуть artifact как incompatible execution context, либо требовать явного нового validation run

### Layer 6. Recoverability Scoring

Recoverability score нужен не для замены hard checks, а для ранжирования borderline cases под `qwen 1.5B`.

Считается только после deterministic pass и persisted critic result.

Формула v1:
- `anchor_recall_score` до `35`
- `chronology_score` до `25`
- `unsupported_action_score` до `15`
- `target_integrity_score` до `15`
- `compression_budget_score` до `10`

Итог:

```text
recoverability_score =
  anchor_recall_score +
  chronology_score +
  unsupported_action_score +
  target_integrity_score +
  compression_budget_score
```

Band policy:
- `85-100` -> `high`
- `65-84` -> `borderline`
- `<65` -> `low`

Threshold policy:
- `high` + no policy exceptions -> candidate может стать `accepted`
- `borderline` -> `manual_review`
- `low` -> `rejected`

Scoring implementation rule:
- каждая компонента вычисляется по фиксированным дискретным правилам ниже
- partial credit разрешён только там, где он явно указан
- если hard reject уже сработал на более раннем слое, score можно не считать
- scoring использует только persisted critic booleans из `validation_report.critic_*` / `critic_execution`, а не live LLM recomputation
- packaging step не имеет права менять critic inputs или переоценивать sample повторным вызовом critic

### Layer 7. Packaging And Train Eligibility

После verdict Track 6 вычисляет:
- `validation_status`
- `train_eligibility`
- `review_required`
- `packaging_tags`

Рекомендуемые значения `train_eligibility`:
- `direct_sft`
- `hard_or_preference_only`
- `review_only`
- `reject_only`

## Hard Reject Vs Manual Review

### Hard Reject

Sample reject-ится сразу, если есть хотя бы одно из:
- contract violation
- provenance unknown
- schema/runtime projection failure
- dangling target
- потеря exact marked object grounding
- потеря recoverability-critical ordinal binding
- beat collapse, подтверждённый deterministic check или critic hard fail
- unsupported action loss или semantic replacement
- invented object, invented action, invented dialogue
- recoverability score `<65`

### Manual Review

Sample идёт в review queue, если:
- critic verdict `soft_fail`
- `same_type_marker_conflict=true`, даже при формальном pass
- `tier_c_reviewed_merge`
- recoverability score `65-84`
- chronology выглядит сохранённой, но surface cues слишком сжаты для уверенного auto-pass
- sample из risky augmentation претендует на прямой train admission

### Accepted

Sample можно принять автоматически, если одновременно:
- нет hard reject reasons
- нет review-required policy flags
- critic verdict `pass`
- recoverability score `>=85`
- provenance tier допускает automatic admission

## Recoverability Scoring Details

### 1. Anchor Recall Score

Компоненты:
- marked object anchor найден
- required ordinal anchor найден
- same-type disambiguation cue найден

Детерминированный расчёт:
- `+20`, если все required marked object aliases найдены; иначе `0`
- `+10`, если все required ordinal anchors найдены или ordinal anchors не обязательны для sample; иначе `0`
- `+5`, если `same_type_marker_conflict=false` или required disambiguation cue найден; иначе `0`

### 2. Chronology Score

Проверяет:
- surface cues отражают порядок beats
- нет схлопывания `move -> stop near object -> described_action`
- multi-beat scenes не стали single-event summary

Детерминированный расчёт:
- `+10`, если `cir_record.budgets.beat_count == 1` или deterministic chronology cue check passed
- `+10`, если deterministic beat-collapse heuristic не сработал
- `+5`, если critic вернул `chronology_preserved=true`; иначе `0`

Deterministic chronology cue check v1:
- для `beat_count >= 2` candidate должен содержать либо явный sequence marker (`затем`, `после этого`, `потом`, `после чего`), либо минимум две глагольные фазы, привязанные к ordered must-have semantics из graph summary

Deterministic beat-collapse heuristic v1:
- срабатывает, если `beat_count >= 2`, но candidate surface summary содержит только одну action phase после normalization, или отсутствует отдельный cue для stop/pass-by/late described_action фазы при pattern-ах, где она объявлена must-have

### 3. Unsupported Action Score

Проверяет:
- critical described action сохранил смысл
- `курить` и другие unsupported actions не заменены на `говорит`, `стоит` или иной безопасный шаблон

Детерминированный расчёт:
- `+10`, если все `must_keep_lemmas` найдены; иначе `0`
- `+5`, если critic вернул `unsupported_action_preserved=true`; иначе `0`

### 4. Target Integrity Score

Проверяет:
- surface text не ломает actor/object binding
- `first/second/third` не потеряны там, где они нужны
- handoff/higher-order target continuity не деградировала

Детерминированный расчёт:
- `+5`, если graph consistency layer не нашёл dangling/missing targets
- `+5`, если critic вернул `object_grounding_preserved=true`
- `+5`, если critic вернул `ordinal_binding_preserved=true` или ordinal binding для sample не recoverability-critical

### 5. Compression Budget Score

Проверяет:
- текст не стал слишком коротким для сохранения нужной semantics
- текст не стал слишком длинным и шумным для `qwen 1.5B`

Детерминированный расчёт:
- вычислить `source_token_count = len(source_text.split())`
- `+5`, если `difficulty_bucket == "core"` и `4 <= source_token_count <= 32`, либо `difficulty_bucket == "hard"` и `4 <= source_token_count <= 48`; иначе `0`
- `+5`, если не сработал `recoverability_overcompressed`; иначе `0`

`recoverability_overcompressed` срабатывает, если:
- `source_token_count < max(4, beat_count * 3 + required_anchor_count)`

где:
- `beat_count` берётся из resolved `cir_record.budgets.beat_count`
- `required_anchor_count = required_marked_object_count + required_ordinal_count + must_keep_lemma_count`

## Critic Prompt Pack

### Critic System Prompt

Рекомендуемый system prompt:

```text
Ты semantic critic для SG v7 dataset pipeline.
Ты не переписываешь текст и не предлагаешь улучшения.
Ты сравниваешь candidate source text с canonical graph constraints и отвечаешь только структурированным verdict.
Считай hard-fail, если потеряны marked object grounding, recoverability-critical ordinal binding, chronology beats, unsupported action semantics или появились придуманные сущности.
Считай soft-fail, если смысл в целом похож, но recoverability для qwen 1.5B стала сомнительной.
Верни только JSON.
```

### Critic User Prompt Template

Рекомендуемый user prompt:

```text
Проверь candidate source text против canonical constraints.

SOURCE_TEXT:
{source_text}

GRAPH_SUMMARY:
{graph_summary}

MUST_HAVE_SEMANTICS:
{must_have_semantics}

MUST_NOT_HAVE_SEMANTICS:
{must_not_have_semantics}

MARKED_OBJECTS:
{marked_objects}

ORDINAL_BINDINGS:
{ordinal_bindings}

CRITICAL_LEMMAS:
{critical_lemmas}

Верни JSON с полями:
- verdict: pass | soft_fail | hard_fail
- confidence: 0.0-1.0
- findings: список коротких строк
- detected_failures: список кодов taxonomy
- chronology_preserved: true/false
- object_grounding_preserved: true/false
- ordinal_binding_preserved: true/false
- unsupported_action_preserved: true/false
- invented_content_present: true/false
- summary: короткая строка
```

### Critic JSON Contract

Первая версия critic response обязана проходить строгую схему:

```json
{
  "verdict": "soft_fail",
  "confidence": 0.86,
  "findings": [
    "Неясно, сохранился ли второй beat остановки у объекта."
  ],
  "detected_failures": [
    "recoverability_borderline"
  ],
  "chronology_preserved": false,
  "object_grounding_preserved": true,
  "ordinal_binding_preserved": true,
  "unsupported_action_preserved": true,
  "invented_content_present": false,
  "summary": "Chronology стала пограничной для recoverability."
}
```

### Prompt Variants

Нужны два user-template variants:
- `source_candidate_v1` для Track 4 / Track 5 candidates
- `reviewed_merge_v1` для real corrected / merge-origin samples, где особенно важны provenance и invented repairs

Разница:
- `reviewed_merge_v1` дополнительно получает `correction_tier`, `review_notes`, `merge_origin_summary`
- verdict policy остаётся общей

## Reject Taxonomy

Reject taxonomy v1 должна быть компактной и кодовой.

### Contract

- `contract_missing_required_field`
- `contract_missing_cir_join_source`
- `contract_cir_join_not_found`
- `contract_cir_join_non_unique`
- `contract_sample_id_mismatch`
- `contract_missing_graph_constraints`
- `contract_unknown_generation_pass`

### Provenance

- `provenance_missing_tier`
- `provenance_unknown_tier`
- `provenance_tier_not_train_eligible`

### Schema

- `schema_invalid_cir`
- `schema_invalid_described_action`
- `runtime_projection_failure`

### Graph Integrity

- `graph_dangling_target`
- `graph_missing_actor`
- `graph_missing_object`
- `graph_duplicate_action_id`
- `graph_duplicate_beat_id`

### Semantic

- `semantic_marked_object_lost`
- `semantic_exact_marker_id_conflict`
- `semantic_ordinal_anchor_lost`
- `semantic_same_type_disambiguation_lost`
- `semantic_unsupported_action_lost`
- `semantic_beat_collapse`
- `semantic_invented_object`
- `semantic_invented_action`
- `semantic_invented_dialogue`

### Recoverability

- `recoverability_borderline`
- `recoverability_too_low`
- `recoverability_overcompressed`

### Packaging

- `packaging_validation_status_missing`
- `packaging_train_eligibility_conflict`

### Review Queue

- `review_same_type_marker_conflict`
- `review_recoverability_borderline`
- `review_tier_c_reviewed_merge`
- `review_risky_augmentation_candidate`
- `review_critic_soft_fail`

Правила taxonomy:
- deterministic checks обязаны писать canonical codes
- critic может добавить только коды из этого же словаря
- `review_reasons` обязаны использовать только коды из секции `Review Queue`
- human review tools не должны invent free-form reject labels

## Focused Policies For Critical Failure Modes

### Object Grounding

Политика:
- absence of required marked object alias = hard reject
- mention только по `type`, когда известен exact `object_marked_*`, считается loss of grounding
- critic обязан различать `object present` и `exact marker identity preserved`

### Beat Collapse

Политика:
- если graph имеет 2+ meaningful beats, candidate не может сжимать их в одно нейтральное summary-событие
- pattern `toward_each_other -> stop near object -> described_action` считается canonical anti-collapse smoke case

### Unsupported Action Loss

Политика:
- unsupported action не может исчезнуть
- замена на generic `talk`, `stand`, `look_at` без сохранения смысла считается hard fail
- presence of lemma hint проверяется deterministic validator-ом до critic

### Dangling Target

Политика:
- любые dangling references reject-ятся до semantic critic
- critic не должен тратить токены на заведомо broken graph sample

### Same-Type Marker Conflicts

Политика:
- такие samples по умолчанию требуют `manual_review`, даже если deterministic и critic checks прошли
- auto-accept допустим только в будущем отдельной версией policy после накопления precision stats

## Packaging Policy

`05_validate_and_pack.py` обязан писать manifest со сводкой:
- total input count
- accepted count
- manual review count
- rejected count
- counts by `correction_tier`
- counts by `difficulty_bucket`
- reject counts by taxonomy code
- critic verdict distribution
- recoverability score histogram

Track 7 должен забирать именно accepted/review artifacts Track 6, а не raw upstream candidates.

## Tests

Минимальный test plan для реализации:

- contract reject на отсутствие `--cir-jsonl` для source/augmentation batch run
- contract reject на missing/non-unique CIR join по `sample_id`
- contract reject на отсутствующий `graph_constraints`
- provenance reject на unknown tier
- schema reject на invalid `described_action`
- graph reject на dangling target
- semantic hard reject на потерю marked object
- semantic hard reject на unsupported action loss в smoke case про `курить`
- manual review на same-type marker conflict
- manual review на critic `soft_fail`
- accept path на clean `tier_b_deterministic_canonical` sample
- outputs persist-ят `correction_tier`
- packaging test на правильное распределение accepted/review/rejected outputs

Обязательные smoke fixtures:
- Example 1 из [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- Example 2 из [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- Example 4 из [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- Example 5 из [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)

## Implementation Handoff

Инженер по реализации должен сделать в таком порядке:

1. Собрать `contracts.py` и taxonomy constants.
2. Реализовать deterministic layers `provenance -> schema -> graph -> anchors`.
3. Добавить `recoverability.py` без LLM-зависимостей.
4. Реализовать `03_semantic_critic.py` со strict JSON response parsing.
5. Реализовать `05_validate_and_pack.py` и writer/manifest layer.
6. Добавить fixtures на critical runtime failures.

Definition of done для этого design:
- можно реализовать `03_semantic_critic.py` и `05_validate_and_pack.py` без новых архитектурных решений
- hard reject vs manual review policy однозначна
- recoverability scoring определён и привязан к policy thresholds
- critic prompt contract и JSON schema зафиксированы
- Track 6 boundary с Track 4, Track 5 и Track 7 не оставляет ownership ambiguity

## Open Questions

- Нужен ли во второй версии отдельный `critic_ensemble` только для `tier_c_reviewed_merge`, если single-critic precision окажется недостаточной.
- Стоит ли после первых реализаций разрешить auto-accept части `same_type_marker_conflict` cases при подтверждённой точности на held-out set.
