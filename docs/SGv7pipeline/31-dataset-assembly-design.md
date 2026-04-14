# 31. Dataset Assembly Design

## Цель

Зафиксировать исполнимый дизайн `dataset assembler` для `SG v7`, чтобы инженер мог реализовать сборку:
- `train/val/test` SFT artifacts
- `preference` artifacts
- split manifests и leakage checks

без дополнительных архитектурных решений по:
- структуре train-ready JSONL
- split strategy и family-level holdout
- metadata contract
- balancing policy
- dedup policy
- границе между Track 6 validation и Track 8 training

Этот документ закрывает design-часть `Track 7` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/11-implementation-backlog.md).

## Scope

Track 7 отвечает за:
- ingest уже валидированных артефактов из Track 6
- family-safe dedup и split assignment
- упаковку `train/val/test` в train-ready JSONL по runtime/train contract
- упаковку `preference` pairs из runtime feedback и reviewed merge sources
- manifests со статистикой buckets, tiers и leakage guards

Track 7 не отвечает за:
- повторную semantic validation
- повышение `manual_review` sample до train-eligible без отдельного review artifact
- oversampling или curriculum scheduling во время обучения
- изменение runtime/train prompt contract
- генерацию новых source variants или repair target JSON

## Исходные зависимости

Dataset assembler обязан переиспользовать уже зафиксированные source-of-truth артефакты:

- общий индекс пакета: [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/README.md)
- fixed decisions: [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
- runtime failure seeds: [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- dataset assembly baseline: [07-dataset-assembly.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/07-dataset-assembly.md)
- eval metrics and release semantics: [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md)
- runtime feedback schema: [10-runtime-feedback-loop.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/10-runtime-feedback-loop.md)
- runtime/train contract: [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)
- canonical CIR contract: [19-canonical-intermediate-representation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/19-canonical-intermediate-representation.md)
- pattern library: [20-pattern-library.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/20-pattern-library.md)
- graph generator design: [21-graph-generator-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/21-graph-generator-design.md)
- source generation design: [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md)
- augmentation design: [27-augmentation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/27-augmentation-design.md)
- validator stack design: [30-validator-stack-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/30-validator-stack-design.md)
- canonical entrypoint: [generate_dataset_v7.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v7.py)

## Design Summary

Ключевое решение:
- Track 7 работает только по validated artifacts, а не по raw upstream candidates
- family-level holdout строится вокруг canonical `graph_family_key`, а не вокруг `sample_id`: все descendants одного canonical graph family не могут разойтись по разным splits
- для semantic-aware stratification Track 7 повторно использует authoritative `CIR` metadata через join по `sample_id`
- balancing в Track 7 означает caps, floors и split proportions, но не row duplication для oversampling
- `preference` наборы собираются отдельно от SFT и используют runtime-failure / reviewed-merge provenance, а не synthetic отрицательные пары "по ощущению"

Базовый flow:

```text
Track 6 accepted/review/rejected artifacts
  + Track 3 CIR JSONL
  + optional runtime_failures / reviewed preference candidates
  -> normalize and join metadata
  -> eligibility filter
  -> family-safe dedup
  -> semantic stratification and split planning
  -> prompt/target rendering by Track 0 contract
  -> write SFT train/val/test JSONL
  -> write preference train/val/(optional test) JSONL
  -> write manifests and leakage report
```

## Почему Track 7 отделён от Track 6

Если final splits строить прямо в validator stack, становится трудно независимо менять:
- dedup policy
- split ratios
- phase-oriented packaging
- preference ingestion

Отдельный Track 7 даёт:
- чёткую ownership boundary между semantic acceptance и dataset packaging
- возможность пересобрать splits без повторного запуска critic
- отдельный leakage report и reproducible split manifests
- совместимость с несколькими training phases из [08-training-plan.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/08-training-plan.md)

## Input Contract

### Primary Inputs

Первая версия dataset assembler должна принимать:
- `accepted.jsonl` из Track 6
- `manual_review.jsonl` из Track 6 как optional source для human-promoted reviewed samples
- `manual_review_promoted.jsonl` как optional human-reviewed add-on
- `rejected.jsonl` как optional source только для preference mining
- `cir_jsonl` из Track 3 как authoritative semantic metadata source
- `runtime_failures.jsonl` как optional input для preference pairs

Track 7 не должен читать raw Track 4 / Track 5 artifacts напрямую.

Правило ownership boundary:
- `manual_review_promoted.jsonl` является decision sidecar, а не full sample artifact
- если Track 7 получил `manual_review_promoted.jsonl`, он обязан получить и `manual_review.jsonl`
- promoted sample materialize-ится join-ом `manual_review_promoted.sample_id -> manual_review.sample_id`
- если promotion decision не матчится ровно с одним reviewed record, build fail-ится как contract violation

### Почему нужен повторный join с CIR

Track 6 уже сохраняет `graph_hash`, `difficulty_bucket`, `train_eligibility` и `validation_report`, но для split planning Track 7 ещё нужны:
- `source_variant_key`
- `semantic_tags`
- `complexity_class`
- `pattern_family`
- `graph_family_key`
- stable budget counters из CIR

Поэтому v1 использует `cir_jsonl` как authoritative join source по immutable `sample_id`.

### Canonical Family Root

Track 7 обязан работать с отдельным canonical family root:
- `graph_family_key`

`graph_family_key`:
- описывает family-level semantic identity graph-а
- не должен зависеть от `sample_id`
- не должен зависеть от seed-derived `object_marked_<SHORTID>`
- в v1 берётся из Track 3 `graph_fingerprint_v1`, описанного в [21-graph-generator-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/21-graph-generator-design.md)

Источник поля:
- если Track 3/Track 6 уже materialize-ят `graph_family_key`, Track 7 переиспользует его как source of truth
- иначе Track 7 обязан вычислить его deterministic-образом из authoritative `cir_record` по тому же `graph_fingerprint_v1` правилу

Следствие:
- `sample_id` остаётся immutable join key до `cir_jsonl`
- `graph_family_key` становится family-level routing key для dedup, balancing и split assignment

### Minimal SFT Candidate Input

Минимальный candidate record после Track 6:

```json
{
  "sample_id": "sgv7-core-000123",
  "graph_id": "sgv7-core-000123",
  "pattern_name": "toward_each_other_then_stop_near_marked_object",
  "difficulty_bucket": "core",
  "source_text": "Два актера идут навстречу друг другу, останавливаются у компа, после этого первый начинает курить.",
  "generation_pass": "base_paraphrase",
  "style_bucket": "clean",
  "correction_tier": "tier_b_deterministic_canonical",
  "validation_status": "accepted",
  "train_eligibility": "direct_sft",
  "graph_hash": "ab7f0c1b...",
  "validation_report": {
    "validator_stack_version": "sgv7_validator_stack_v1",
    "recoverability_score": 93,
    "bucket_metrics": {
      "marked_object_recall_expected": 1,
      "ordinal_binding_expected": 1,
      "must_keep_lemma_expected": 1
    }
  }
}
```

### Optional Review Promotion Input

`manual_review_promoted.jsonl` нужен, чтобы Track 7 мог включить часть reviewed данных без нарушения ownership boundary.

Минимальный record:

```json
{
  "sample_id": "sgv7-hard-000044",
  "review_decision": "promote_for_hard_sft",
  "reviewer": "human_or_approved_tool",
  "reviewed_at": "2026-04-13T11:30:00Z",
  "promoted_train_eligibility": "hard_or_preference_only",
  "notes": "same-type markers checked manually"
}
```

Правила:
- без promotion artifact Track 7 не может поднимать `manual_review` sample
- без `manual_review.jsonl` promotion artifact не имеет исполнимого source record и build должен завершаться ошибкой
- `promoted_train_eligibility` не может быть шире, чем допускает provenance policy из Track 6
- `tier_d_auto_repair_only` не может быть promoted в direct SFT

### Optional Preference Input

Canonical источник preference pairs:
- `runtime_failures.jsonl` из Track 10

Допустимый secondary источник:
- reviewed merge records, где есть both `bad_json` и approved `good_json`

Для всех preference-origin inputs v1 обязателен materialized `family_anchor` block.

Минимальная схема:

```json
{
  "family_anchor": {
    "anchor_type": "graph_family_key_or_sample_id_or_graph_hash",
    "anchor_value": "gfk_9c0ab1de",
    "graph_family_key": "gfk_9c0ab1de",
    "split_family_id": "gfk_9c0ab1de"
  }
}
```

Правила:
- каждый preference candidate обязан иметь ровно один canonical family anchor
- final `family_anchor` обязан materialize-ить `graph_family_key`
- если у preference candidate доступен `sample_id`, `graph_hash` или другой deterministic path к authoritative CIR family, builder обязан резолвить из него final `graph_family_key`
- raw `runtime_failure_id` не является допустимым final family root для split-able preference artifacts
- если runtime failure не удаётся deterministic-join-ить к canonical `graph_family_key`, sample должен быть отправлен в quarantine/review pool и не может входить в `preference_train`, `preference_val` или `preference_test`
- для offline-eval кейсов anchor не может быть произвольным локальным id; он обязан ссылаться на `sample_id` или `graph_hash` оцениваемого canonical family
- Track 7 не имеет права создавать новый family anchor эвристически из свободного текста, если исходный артефакт не даёт deterministic source key
- emitted preference artifact обязан сохранять `family_resolution_proof`, чтобы provenance canonical family join был проверяемым downstream-аудитом

Anti-leakage следствие:
- cross-task holdout проверяется по final canonical `graph_family_key` / `split_family_id`, а не по raw runtime id
- preference pair без canonical `graph_family_key` не может участвовать в split assignment вообще

Минимальный runtime preference candidate:

```json
{
  "failure_id": "rtf-000921",
  "source": "2 актёра идут навстречу друг другу, останавливаются у компа, первый начинает курить сигарету",
  "raw_llm_output": { "...": "bad_json" },
  "corrected_target_json": { "...": "good_json" },
  "final_decision": "merge",
  "correction_tier": "tier_c_reviewed_merge",
  "contract_version": "sg_v7_contract_v1",
  "family_anchor": {
    "anchor_type": "graph_family_key",
    "anchor_value": "gfk_9c0ab1de",
    "graph_family_key": "gfk_9c0ab1de",
    "split_family_id": "gfk_9c0ab1de"
  }
}
```

Минимальный offline-eval preference candidate:

```json
{
  "eval_case_id": "eval-hard-0042",
  "sample_id": "toward_each_other_then_stop_near_marked_object__base__s418203__ab12cd34",
  "bad_json": { "...": "bad_json" },
  "good_json": { "...": "good_json" },
  "correction_tier": "tier_b_deterministic_canonical",
  "contract_version": "sg_v7_contract_v1",
  "family_anchor": {
    "anchor_type": "graph_family_key",
    "anchor_value": "gfk_9c0ab1de",
    "graph_family_key": "gfk_9c0ab1de",
    "split_family_id": "gfk_9c0ab1de"
  },
  "family_anchor_source": {
    "anchor_type": "sample_id",
    "anchor_value": "toward_each_other_then_stop_near_marked_object__base__s418203__ab12cd34",
    "resolved_via": "cir_jsonl_join"
  }
}
```

### Preference Difficulty Derivation

Для preference pairs `difficulty_bucket` обязан быть deterministically materialized до emission.

Правило v1:
- если preference candidate deterministic-join-ится к authoritative `cir_jsonl`, bucket берётся из соответствующего canonical family
- если candidate не может deterministic-join-иться к authoritative family, он не может войти в split-able preference dataset и должен быть quarantined
- derived bucket обязан persist-иться в `packaging_metadata` и `preference_manifest`

Следствие:
- hard bucket accounting для preference artifacts исполним
- builder не зависит от несуществующего поля `difficulty_bucket` в `runtime_failures.jsonl`

## Packaging Metadata Contract

Track 7 обязан материализовать единый metadata block `packaging_metadata`, но с task-specific required fields.

Обязательные общие поля:
- `split`
- `task_type`
- `contract_version`
- `correction_tier`

Обязательные поля для `task_type=sft`:
- `sample_id`
- `graph_id`
- `graph_hash`
- `graph_family_key`
- `normalized_source_hash`
- `pattern_name`
- `pattern_family`
- `source_variant_key`
- `difficulty_bucket`
- `complexity_class`
- `semantic_tags`
- `style_bucket`
- `generation_pass`
- `validation_status`
- `train_eligibility`
- `validator_stack_version`
- `split_family_id`
- `semantic_family_key`
- `dedup_group_key`
- `source_text_token_count`
- `target_json_token_count`
- `full_sequence_token_count`
- `actor_count`
- `object_count`
- `beat_count`
- `action_count`

Обязательные поля для `task_type=preference`:
- `preference_id`
- `preference_origin`
- `difficulty_bucket`
- `graph_family_key`
- `normalized_source_hash`
- `split_family_id`
- `family_resolution_proof`

Допустимые optional поля:
- `sample_id`
- `graph_id`
- `graph_hash`
- `pattern_name`
- `pattern_family`
- `source_variant_key`
- `complexity_class`
- `semantic_tags`
- `style_bucket`
- `generation_pass`
- `validation_status`
- `train_eligibility`
- `validator_stack_version`
- `dedup_group_key`
- `variant_id`
- `parent_variant_id`
- `review_decision`
- `reviewed_at`
- `reviewer`
- `runtime_failure_id`

### Field Semantics

`graph_family_key`
- canonical family root для downstream split planning
- в v1 равен Track 3 `graph_fingerprint_v1`
- именно он, а не `sample_id`, определяет family-level holdout boundary

`split_family_id`
- группа всех descendants одного canonical graph instance
- для SFT v1 вычисляется как stable key по `graph_family_key`
- для preference pairs v1 всегда materialize-ится из `family_anchor.split_family_id`
- для preference pairs v1 должен совпадать с `graph_family_key`
- для offline-eval preference pairs canonical anchor обязан строиться по `sample_id` или `graph_hash`, а не по ad-hoc `eval_case_id`
- все records одного `split_family_id` обязаны попасть в один split

`family_resolution_proof`
- обязательный persisted proof block для `task_type=preference`
- фиксирует, каким deterministic путём был получен final `graph_family_key`
- минимальные поля:
- `input_anchor_type`
- `input_anchor_value`
- `resolution_method`
- `resolved_graph_family_key`
- `proof_status`
- допустимые `proof_status` для split-able artifacts: только `resolved`
- если `proof_status != resolved`, record может жить только в quarantine artifact и не должен попадать в `preference_train`, `preference_val`, `preference_test`

`normalized_source_hash`
- обязательный persisted source fingerprint для emitted `sft` и `preference` artifacts
- вычисляется по правилу `normalized_source_hash v1` из раздела near-duplicate dedup
- служит независимым leakage guard key и не должен восстанавливаться downstream эвристически из raw text как единственный источник правды
- emission-time validation обязана проверять совпадение persisted `normalized_source_hash` с canonical recomputation

`semantic_family_key`
- coarse stratification key
- v1 собирается как:
  `pattern_family | source_variant_key | difficulty_bucket | complexity_class | sorted(semantic_tags)`
- нужен для semantic-aware balancing и holdout coverage

`pattern_family`
- берётся из `CIR internal_metadata.parent_pattern_family`, если оно materialized
- если поле отсутствует, детерминированно резолвится через pattern registry по `pattern_name`
- Track 7 не имеет права придумывать `pattern_family` свободным текстом

`dedup_group_key`
- ключ для family-safe dedup
- v1 собирается как:
  `graph_hash | normalized_source_hash`

`contract_version`
- версия runtime/train contract из Track 0
- Track 7 не имеет права смешивать разные `contract_version` в одном emitted artifact

## JSONL Structure

### SFT Record

SFT JSONL обязан быть train-ready и совпадать с runtime/train contract по section order и target serialization.

Рекомендуемый record:

```json
{
  "sample_id": "sgv7-core-000123",
  "task_type": "sft",
  "messages": [
    {
      "role": "system",
      "content": "SceneScript parser instruction block..."
    },
    {
      "role": "user",
      "content": "Task instruction\\nOutput contract\\nAction/object constraints\\nMarked objects\\nSource text..."
    },
    {
      "role": "assistant",
      "content": "{\"actors\":[...],\"objects\":[...],\"beats\":[...]}"
    }
  ],
  "target_json": {
    "actors": [],
    "objects": [],
    "beats": []
  },
  "packaging_metadata": {
    "split": "train",
    "task_type": "sft",
    "contract_version": "sg_v7_contract_v1",
    "graph_family_key": "gfk_9c0ab1de",
    "normalized_source_hash": "nsh_51a84db9",
    "difficulty_bucket": "core",
    "pattern_name": "toward_each_other_then_stop_near_marked_object",
    "correction_tier": "tier_b_deterministic_canonical"
  }
}
```

Правила:
- `messages` должны быть построены тем же prompt renderer, который обслуживает runtime/train contract
- `assistant.content` обязан быть canonical serialized JSON string
- `target_json` дублируется как parsed form для offline checks и dataset introspection
- Track 7 не меняет field order вручную; он вызывает canonical serializer

### Preference Record

Рекомендуемый record:

```json
{
  "preference_id": "pref-rtf-000921",
  "task_type": "preference",
  "messages": [
    {
      "role": "system",
      "content": "SceneScript parser instruction block..."
    },
    {
      "role": "user",
      "content": "Task instruction\\nOutput contract\\nAction/object constraints\\nMarked objects\\nSource text..."
    }
  ],
  "chosen": "{\"actors\":[...],\"objects\":[...],\"beats\":[...]}",
  "rejected": "{\"actors\":[...],\"objects\":[...],\"beats\":[...]}",
  "chosen_json": {
    "actors": [],
    "objects": [],
    "beats": []
  },
  "rejected_json": {
    "actors": [],
    "objects": [],
    "beats": []
  },
  "packaging_metadata": {
    "split": "train",
    "task_type": "preference",
    "contract_version": "sg_v7_contract_v1",
    "preference_origin": "runtime_failure_reviewed_merge",
    "correction_tier": "tier_c_reviewed_merge",
    "difficulty_bucket": "hard",
    "graph_family_key": "gfk_9c0ab1de",
    "normalized_source_hash": "nsh_51a84db9",
    "runtime_failure_id": "rtf-000921",
    "split_family_id": "gfk_9c0ab1de",
    "family_resolution_proof": {
      "input_anchor_type": "runtime_failure_id",
      "input_anchor_value": "rtf-000921",
      "resolution_method": "deterministic_cir_join_v1",
      "resolved_graph_family_key": "gfk_9c0ab1de",
      "proof_status": "resolved"
    }
  }
}
```

Правила:
- `chosen` всегда должен иметь approved provenance
- `rejected` должен быть реальным model output, merge candidate или documented bad target, а не synthetic "нарочно испорченный" JSON
- если `chosen` и `rejected` семантически слишком близки и не несут полезного preference signal, pair отбрасывается

## Eligibility Policy

### SFT Admission

В `train/val/test` SFT могут входить только:
- `accepted` + `direct_sft`
- `accepted` + `hard_or_preference_only`
- `manual_review_promoted` с promotion не выше provenance ceiling

Нельзя включать:
- `manual_review` без promotion artifact
- `rejected`
- `tier_d_auto_repair_only`

### Bucket Routing

`direct_sft`
- может идти в `core` или `hard` по исходному `difficulty_bucket`

`hard_or_preference_only`
- может идти только в `hard` SFT views и preference views
- не должен silently попадать в `core`

### Preference Admission

В `preference` могут входить:
- `tier_c_reviewed_merge` runtime failures с approved `corrected_target_json`
- `tier_b_deterministic_canonical` runtime failures, если bad side является реальным raw output
- manually reviewed rejected/merge cases из offline eval

Нельзя включать:
- пары без explicit `bad_json` provenance
- `tier_d_auto_repair_only` как chosen side

## Dedup Policy

Track 7 делает dedup в три слоя.

### Layer 1. Record Identity

Reject conditions:
- duplicate `sample_id` with conflicting content
- duplicate `preference_id`
- same `sample_id` across different `contract_version`

### Layer 2. Graph Family Dedup

Цель:
- не раздувать train множеством почти одинаковых descendants одного graph

Политика v1:
- все records группируются по `graph_family_key`
- внутри одного `graph_family_key` сохраняется не более:
- `core`: 2 SFT records
- `hard`: 3 SFT records

Рекомендуемый приоритет выбора:
1. `generation_pass=base_paraphrase`
2. safe `augmentation`
3. promoted reviewed sample

Внутри одинакового приоритета выигрывает record с:
1. более высоким `recoverability_score`
2. меньшим `source_text_token_count`, если semantics одинаковы
3. lexicographically smaller stable id как deterministic tie-breaker

### Layer 3. Near-Duplicate Surface Dedup

Цель:
- не хранить в разных splits тексты, отличающиеся только пунктуацией или `е/ё`

`normalized_source_hash` v1 строится после:
- lowercase
- trim
- whitespace collapse
- safe punctuation strip на границах
- `е/ё` folding

Если `graph_hash` одинаков и `normalized_source_hash` одинаков, остаётся только один record.

Дополнительное anti-leakage правило:
- для split-able artifacts `normalized_source_hash` считается самостоятельным guard key
- одинаковый `normalized_source_hash` в разных splits недопустим даже при разных `graph_hash`, если запись относится к одному task domain (`sft` либо `preference`)

## Semantic-Aware Split Strategy

### Split Units

Базовая единица split assignment:
- `split_family_id`

Это гарантирует family-level holdout:
- base paraphrase
- augmentation descendants
- reviewed corrections для того же canonical graph

не могут разойтись между `train`, `val` и `test`.

### Target Ratios

Рекомендуемые default ratios для SFT:
- `train`: 84%
- `val`: 8%
- `test`: 8%

Для preference:
- `train`: 85%
- `val`: 10%
- `test`: 5%

Fallback coverage rule:
- `preference_test.jsonl` всегда materialize-ится как output artifact
- если eligible preference family groups достаточно, builder обязан выделить минимум `1` family в `preference_test`
- если после family-level grouping `preference_test` иначе оказался бы пустым, builder обязан сделать deterministic rebalance в пользу non-empty `preference_test`
- если eligible preference family groups < 3, builder всё равно пишет `preference_test.jsonl`, но manifest обязан пометить `preference_test_coverage_status=undersized_preference_corpus`
- corpus с `undersized_preference_corpus` не считается release-grade preference dataset и не должен использоваться для финального release comparison без отдельного решения

### Stratification Axes

Split planner обязан учитывать минимум:
- `difficulty_bucket`
- `semantic_family_key`
- `correction_tier`
- `train_eligibility`
- `complexity_class`
- critical tags из eval doc:
  - `ordinal_cases`
  - `marked_object_morphology`
  - `same_type_markers`
  - `unsupported_action_cases`
  - `three_beat_cases`
  - `exact_marker_identity_cases`
  - `reviewed_merge_cases`

### Family-Level Holdout Rule

Обязательное правило:
- все records c одинаковым `split_family_id` попадают ровно в один split

Следствие:
- утечка между paraphrase и augmentation невозможна
- один runtime failure и его corrected/promoted варианты не могут оказаться одновременно в train и test

### Assignment Algorithm

Рекомендуемый deterministic algorithm:
1. Построить SFT candidates после dedup.
2. Сгруппировать их по `split_family_id`.
3. Для каждой family вычислить stratification profile.
4. Стабильно отсортировать families по `(difficulty_bucket, scarcity_score, split_family_id)`.
5. Greedy-assign family в split с минимальным текущим отклонением от target ratios и tag coverage floors.
6. После primary assignment прогнать leakage audit и coverage audit.
7. Если `val` или `test` не покрывают критичный family/tag, выполнить limited deterministic swap.

`scarcity_score` должен повышать приоритет для редких `hard` families и `tier_c_reviewed_merge`.

## Balancing Policy

Track 7 не дублирует rows для oversampling. Он балансирует набор через caps и minima.

### SFT Balancing

Default цели для master SFT artifacts:
- `core`: 80-85%
- `hard`: 15-20%
- `tier_c_reviewed_merge` в SFT: не более 5% от `hard`
- `complexity_class=L`: не более 12% от всего train SFT

### Hard Bucket Accounting

Manifest обязан отдельно считать:
- total `hard`
- `hard` by `pattern_family`
- `hard` by `correction_tier`
- `hard` by critical eval tags
- долю promoted reviewed samples внутри `hard`

### Family Caps

Чтобы один family не забил train:
- один `semantic_family_key` не должен занимать больше 18% `core train`
- один `semantic_family_key` не должен занимать больше 25% `hard train`

Если floor для редкого bucket конфликтует с cap, редкий bucket имеет приоритет.

## Preference Pair Policy

### Pair Construction

V1 поддерживает два canonical origin-а:
- `runtime_failure_reviewed_merge`
- `offline_eval_bad_vs_corrected`

Pair builder обязан:
- использовать общий prompt context для `chosen` и `rejected`
- canonical-serialize обе стороны одной и той же serializer policy
- сохранять `final_decision`, `correction_tier` и source provenance

### Pair Quality Rules

Pair reject-ится, если:
- `chosen` не проходит contract validation
- `rejected` не является реальным observed output
- различие касается только formatting noise, а не semantics
- `rejected` содержит уже исправленный merge, практически равный `chosen`

### Preference Split Safety

Preference pairs с тем же `graph_family_key` / `split_family_id`, что и held-out SFT artifacts, не должны попадать в preference artifacts.

Причина:
- preference tuning иначе может leak-нуть exact hard failures в evaluation.

Дополнительное правило:
- SFT и preference artifacts обязаны публиковать общий cross-task family key `graph_family_key`
- leakage audit обязан проверять reuse этого key между `sft_test`, `sft_val`, `preference_train`, `preference_val` и `preference_test`

## Output Artifact Contract

Рекомендуемая структура выходной директории:

```text
docs/SGv7pipeline/dataset_builder/output/
  sft_train.jsonl
  sft_val.jsonl
  sft_test.jsonl
  preference_train.jsonl
  preference_val.jsonl
  preference_test.jsonl
  split_manifest.json
  preference_manifest.json
  leakage_report.json
```

### `split_manifest.json`

Обязательные разделы:
- build config
- input artifact versions
- counts by split
- counts by `difficulty_bucket`
- counts by `correction_tier`
- counts by `semantic_family_key`
- counts by critical eval tags
- dropped by dedup reason
- contract versions present

### `preference_manifest.json`

Обязательные разделы:
- build config
- counts by split
- counts by `preference_origin`
- counts by `difficulty_bucket`
- counts by `correction_tier`
- counts by `graph_family_key`
- `preference_test_coverage_status`
- quarantined candidate counts and reasons
- family-resolution proof summary

### `leakage_report.json`

Обязательные проверки:
- no shared `sample_id` across splits
- no shared `split_family_id` across splits
- no shared `graph_hash + normalized_source_hash` across splits
- no shared `normalized_source_hash` across splits for same task domain
- no shared `normalized_source_hash` between held-out SFT artifacts and any preference artifact, including `preference_test`
- no shared `graph_family_key` across splits
- no shared `split_family_id` between held-out SFT artifacts and any preference artifact
- no shared `graph_family_key` between held-out SFT artifacts and any preference artifact, including `preference_test`
- no shared `sample_id` between SFT held-out artifacts and preference artifacts when `sample_id` is present
- no shared `graph_hash` between SFT held-out artifacts and preference artifacts when `graph_hash` is present
- all emitted artifacts persist `normalized_source_hash`
- all emitted preference records have `family_resolution_proof.proof_status=resolved`
- no mixed `contract_version` in emitted files
- no `hard_or_preference_only` records in `core-only` views

## Recommended Module Structure

```text
docs/SGv7pipeline/dataset_builder/
  __init__.py
  config.py
  ingest.py
  dedup.py
  splitter.py
  renderer.py
  preference.py
  manifest.py
  writer.py
  06_build_dataset_splits.py
  tests/
    test_dataset_ingest.py
    test_dataset_dedup.py
    test_dataset_splitter.py
    test_preference_builder.py
    test_dataset_cli.py
```

## Public API

Рекомендуемый Python API:

```python
from dataclasses import dataclass
from pathlib import Path

@dataclass(frozen=True)
class DatasetBuildRequest:
    accepted_jsonl: Path
    cir_jsonl: Path
    output_dir: Path
    seed: int
    manual_review_jsonl: Path | None = None
    review_promoted_jsonl: Path | None = None
    rejected_jsonl: Path | None = None
    runtime_failures_jsonl: Path | None = None
    contract_version: str = "sg_v7_contract_v1"
    sft_train_ratio: float = 0.84
    sft_val_ratio: float = 0.08
    sft_test_ratio: float = 0.08

def build_dataset(request: DatasetBuildRequest) -> DatasetBuildResult: ...
def plan_splits(request: DatasetBuildRequest) -> SplitPlan: ...
def build_preference_pairs(request: DatasetBuildRequest) -> PreferenceBuildResult: ...
```

Рекомендуемый CLI:

```bash
python docs/SGv7pipeline/dataset_builder/06_build_dataset_splits.py \
  --accepted-jsonl /tmp/sgv7_validated_accepted.jsonl \
  --manual-review-jsonl /tmp/sgv7_validated_manual_review.jsonl \
  --cir-jsonl /tmp/sgv7_graphs.jsonl \
  --runtime-failures-jsonl /tmp/runtime_failures.jsonl \
  --output-dir /tmp/sgv7_dataset \
  --seed 20260413
```

## Implementation Backlog

### 1. Input Normalization

Реализовать:
- readers для `accepted`, `manual_review`, `review_promoted`, `runtime_failures`
- strict join с `cir_jsonl`
- contract checks для `contract_version`
- contract checks для `family_anchor`

### 2. Packaging Metadata Builder

Реализовать:
- `split_family_id`
- `graph_family_key`
- `semantic_family_key`
- `dedup_group_key`
- `normalized_source_hash`
- budget counters merge из CIR и validated artifact
- preference `difficulty_bucket` derivation

### 3. Dedup Engine

Реализовать:
- exact duplicate detection
- graph family caps
- near-duplicate normalized source dedup

### 4. Split Planner

Реализовать:
- deterministic family assignment
- ratio tracking
- critical tag coverage floors
- leakage audit and swap repair

### 5. Prompt/Target Renderer

Реализовать:
- integration с Track 0 training prompt renderer
- canonical JSON serialization for `assistant.content`
- parsed `target_json` sidecar field

### 6. Preference Builder

Реализовать:
- runtime failure ingestion
- quarantine path для preference candidates без deterministic canonical family join
- chosen/rejected pair builder
- preference-specific dedup
- emission-time validation for `family_resolution_proof` consistency with final `graph_family_key`
- emission-time validation for persisted `normalized_source_hash`

### 7. Manifests And CLI

Реализовать:
- split manifest
- preference manifest
- leakage report
- reproducible CLI summary

## Test Plan

Обязательные tests первой версии:

- unit test: identical `sample_id` with conflicting payload reject-ится
- unit test: all records with same `split_family_id` always end up in one split
- unit test: all records with same `graph_family_key` always end up in one split even when `sample_id` differs
- unit test: same `graph_hash` + same normalized source collapse to one kept record
- unit test: `hard_or_preference_only` never enters `core-only` views
- unit test: `tier_d_auto_repair_only` never enters SFT or chosen side of preference
- unit test: split planner keeps at least one sample for each critical hard tag in `val` or `test`, если такие samples вообще есть
- unit test: mixed `contract_version` build fails fast
- unit test: promotion sidecar without matching `manual_review` record fails fast
- unit test: offline-eval preference candidate without `family_anchor` rooted in `sample_id` or `graph_hash` is rejected
- unit test: runtime-failure preference pair without deterministic join to `graph_family_key` is quarantined and excluded from split-able preference artifacts
- unit test: runtime-failure preference pair with resolvable `sample_id` or `graph_hash` is canonicalized to final `graph_family_key`
- unit test: emitted preference record without valid `family_resolution_proof` is rejected
- unit test: emitted `sft` and `preference` records without persisted `normalized_source_hash` are rejected
- unit test: preference pair with formatting-only difference is dropped
- unit test: any preference artifact build fails or swaps when `split_family_id` overlaps with held-out SFT family
- unit test: leakage audit rejects shared `normalized_source_hash` across splits even when `graph_hash` differs
- unit test: builder materializes non-empty `preference_test` whenever eligible preference family groups >= 3
- unit test: manifest marks `preference_test_coverage_status=undersized_preference_corpus` when family groups < 3
- smoke test: deterministic seed produces byte-identical manifests
- smoke test: rendered `messages` preserve Track 0 section order

## Invariants

1. Dataset builder не переоценивает semantic correctness; он уважает Track 6 verdict.
2. `sample_id` остаётся immutable join key до финального emitted dataset.
3. Один `split_family_id` не может пересекать два splits.
4. Один emitted artifact не может смешивать несколько `contract_version`.
5. `tier_c_reviewed_merge` не может silently стать `core`.
6. `tier_d_auto_repair_only` не может стать direct SFT gold.
7. Oversampling делается в Track 8, а не через дубли rows в Track 7.
8. Preference `chosen` обязан иметь provenance не ниже reviewed quality.
9. Leakage audit обязателен для каждого build-а, а не только для release builds.
10. Preference origin без canonical `family_anchor` не может участвовать в build-е.
11. Promoted reviewed sample должен иметь и decision sidecar, и authoritative reviewed source record.
12. `graph_family_key`, а не `sample_id`, является final family root для split planning.
13. Preference sample без deterministic join к canonical `graph_family_key` не может входить в split-able artifacts.
14. Каждый emitted preference record обязан содержать проверяемый `family_resolution_proof`.
15. Каждый emitted `sft` и `preference` record обязан persist-ить canonical `normalized_source_hash`.
16. `preference_test.jsonl` всегда materialize-ится; при нехватке данных manifest обязан явно маркировать undersized coverage.

## Non-Blocking Open Questions

1. Стоит ли Track 6 в следующей версии persist-ить `pattern_family` напрямую, чтобы Track 7 не делал lookup/join через CIR для этого поля.
2. Нужен ли обязательный `preference_test.jsonl`, если runtime reviewed pairs в первой версии окажется мало.

Обе точки не блокируют реализацию v1.

## Implementation Handoff

Инженер может начинать реализацию `docs/SGv7pipeline/dataset_builder/06_build_dataset_splits.py` со следующими boundary rules:
- брать только validated artifacts Track 6 плюс authoritative `cir_jsonl`
- считать `graph_family_key` canonical family root
- canonicalize preference families к `graph_family_key` через deterministic CIR join
- runtime-only preference candidate без canonical family join отправлять в quarantine, а не в split-able artifacts
- делать split assignment по family groups, а не по одиночным rows
- формировать train-ready `messages` только через Track 0 contract renderer
- писать отдельные manifests и leakage report как обязательные build outputs

Если эти правила соблюдены, dataset assembler можно реализовать без дополнительных архитектурных решений.
