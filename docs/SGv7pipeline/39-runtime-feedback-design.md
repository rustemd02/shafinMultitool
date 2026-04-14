# 39. Runtime Feedback Design

## Цель

Зафиксировать исполнимый дизайн `runtime feedback loop` для `SG v7`, чтобы инженер мог реализовать:
- runtime logging внутри iOS приложения
- нормализацию runtime-парсов в `runtime_failures.jsonl`
- deterministic failure clustering
- corrected-sample export обратно в `SG v7` dataset/eval pipeline
- privacy/safety gate для реальных пользовательских данных

без дополнительных архитектурных решений по:
- границе между сырыми runtime events и train/eval-ready artifacts
- обязательным полям feedback schema
- taxonomy failure-кейсов
- provenance и `train_eligibility`
- способу привязки runtime cases к `pattern_family` и `graph_family_key`

Этот документ закрывает design-часть `Track 10` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/11-implementation-backlog.md).

## Scope

Track 10 отвечает за:
- capture каждого runtime parse как traceable event
- выделение failure и low-quality accept cases
- присвоение taxonomy labels и cluster ids
- сбор corrected targets с provenance
- экспорт reviewed runtime artifacts в формат, пригодный для Track 7 и Track 9
- traceability от runtime failure до `pattern_family`/`graph_family_key`, если это возможно детерминированно

Track 10 не отвечает за:
- изменение runtime/train contract
- автоматическое дообучение модели прямо из приложения
- auto-promotion `tier_d_auto_repair_only` в SFT
- хранение сырых пользовательских данных без privacy gate
- переопределение policy `accept/merge/reject` в [SceneParserService.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/SceneParserService.swift)

## Исходные зависимости

Runtime feedback loop обязан опираться на уже зафиксированные source-of-truth артефакты:

- общий индекс пакета: [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/README.md)
- runtime feedback baseline: [10-runtime-feedback-loop.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/10-runtime-feedback-loop.md)
- implementation backlog: [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/11-implementation-backlog.md)
- fixed decisions: [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
- runtime failure seeds: [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- codebase entry points: [16-codebase-entry-points.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/16-codebase-entry-points.md)
- runtime/train contract: [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)
- validator stack design: [30-validator-stack-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/30-validator-stack-design.md)
- dataset assembly design: [31-dataset-assembly-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/31-dataset-assembly-design.md)
- eval harness design: [36-eval-harness-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/36-eval-harness-design.md)
- runtime LLM parser: [LLMParserService.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/LLMParserService.swift)
- runtime parser policy: [SceneParserService.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/SceneParserService.swift)
- runtime diagnostics: [DiagnosticsCalculator.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/DiagnosticsCalculator.swift)
- runtime schema: [SceneScript.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Models/SceneScript.swift)

## Design Summary

Ключевые решения:
- feedback loop разделяется на `bronze -> silver -> gold` слои, а не пишет train-ready sample напрямую из приложения
- приложение пишет append-only `runtime_parse_events.jsonl`, который хранит решение parser policy, диагностики и LLM trace
- только `failure` и `low_quality_accept` cases materialize-ятся в `runtime_failures.jsonl`
- `runtime_failures.jsonl` является canonical bridge-артефактом для Track 7 и Track 9, поэтому он обязан содержать provenance, review status и family anchor
- clustering в `v1` детерминированный и rule-based; эмбеддинги допустимы только как analyst-side secondary hint, но не как source of truth
- corrected target без `correction_tier`, `gold_source`, `review_status` и `final_script_source` не считается train/eval-ready gold
- privacy gate выполняется до любого offline export; blocked cases могут оставаться в cluster metrics, но не могут попадать в dataset artifacts

Базовый flow:

```text
iOS runtime parse
  -> runtime_parse_events.jsonl (bronze)
  -> failure normalizer
  -> taxonomy labeling + family-anchor attempt
  -> runtime_failures.jsonl (silver bridge)
  -> cluster builder + review queue
  -> corrected target / provenance assignment
  -> validator-compatible reviewed export (gold)
  -> Track 7 preference/SFT ingestion + Track 9 real-runtime eval
```

## Слои и owned artifacts

### 1. Bronze: raw runtime capture

Первая версия должна materialize-ить:
- `runtime_parse_events.jsonl`
- `runtime_parse_manifest.json`

Это append-only слой для локального capture. Он может содержать больше данных, чем downstream pipeline.

### 2. Silver: normalized failure bridge

Первая версия должна materialize-ить:
- `runtime_failures.jsonl`
- `runtime_failure_clusters.json`
- `runtime_review_queue.jsonl`
- `runtime_failure_manifest.json`

Именно `runtime_failures.jsonl` считается canonical contract между Track 10 и Track 7/9.

### 3. Gold: reviewed and promoted feedback

Первая версия должна materialize-ить:
- `runtime_feedback_promoted.jsonl`
- `runtime_patch_candidates.jsonl`
- `runtime_feedback_summary.md`

`runtime_feedback_promoted.jsonl` может быть либо отдельным artifact, либо filtered view поверх `runtime_failures.jsonl` по `review_status=approved`, если это удобно реализации. Source of truth при этом остаётся `runtime_failures.jsonl`.

## Instrumentation boundary в runtime

### LLMParserService

[LLMParserService.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/LLMParserService.swift) обязан отдавать в feedback layer:
- `prompt_hash`
- `model_id`
- список generation attempts с `max_tokens`, длительностью и raw text
- `raw_llm_text`
- `json_candidates`
- `repaired_llm_output`, если repair/canonical cleanup действительно произошёл
- `parsed_script_json`, если JSON удалось декодировать

Важно:
- feedback layer не должен пересобирать LLM trace по логам `print`
- trace должен возвращаться структурно, а не парситься из console output

### SceneParserService

[SceneParserService.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/SceneParserService.swift) обязан отдавать в feedback layer:
- `rule_based_result`
- `llm_result`, если есть
- `selection.decision` = `accept | merge | reject | rule_only`
- `selection.reason`
- `final_script_source` = `llm | merged | rule_based`
- rule-based и final diagnostics
- список precomputed taxonomy hints на основе decision reason и diagnostics

### Runtime capture policy

В `v1` логируется каждый parse event, но в silver-слой попадает не каждый event.

Event попадает в `runtime_failures.jsonl`, если выполняется хотя бы одно условие:
- `selection.decision == reject`
- `selection.decision == merge`
- `selection.decision == accept`, но final diagnostics показывают semantically poor result
- пользователь или reviewer пометил кейс как incorrect
- quality heuristics нашли один из critical buckets даже при формальном `accept`

### Low-quality accept policy (`low_quality_accept_v1`)

Чтобы избежать drift между реализациями normalizer-а, `semantically poor result` для `selection.decision=accept` определяется только по rules ниже (first-match wins):

1. `final_result.script_json.actions_count <= 1` и в source есть минимум 2 action-intents -> включить case в `runtime_failures`.
2. `final_result.script_json.beat_count == 1` и source classified как `expected_multi_beat=true` -> включить case в `runtime_failures`.
3. `final_result.diagnostics.unresolvedMarkedObjects == true` -> включить case в `runtime_failures`.
4. `final_result.diagnostics.matchedMarkedObjectsCount < expected_marked_object_mentions` -> включить case в `runtime_failures`.
5. source содержит ordinal markers (`первый|второй|третий`), но final graph не содержит соответствующие `actor_1/actor_2/actor_3` bindings -> включить case в `runtime_failures`.
6. source содержит unsupported-action lemma из frozen списка, но final graph не содержит `described_action` -> включить case в `runtime_failures`.
7. Если ни одно правило не сработало -> case остаётся только в bronze.

Нормализатор обязан писать:
- `low_quality_accept_policy_version = "low_quality_accept_v1"`
- `low_quality_accept_reason` (одно из `lqa_rule_1` ... `lqa_rule_6` или пусто)

### Source expectations contract (`runtime_source_expectations_v1`)

Чтобы `low_quality_accept_v1` был полностью исполнимым, входные предикаты фиксируются отдельным contract-слоем.

Authoritative artifact:
- `docs/SGv7pipeline/runtime_feedback/contracts/runtime_source_expectations_v1.md`

Обязательные вычисляемые поля:
- `expected_multi_beat`
- `expected_marked_object_mentions`
- `unsupported_action_present`

Deterministic rules v1:
- `expected_multi_beat=true`, если source содержит минимум 2 phase cues из списка:
  - `идут|подходят|двигаются`
  - `останавливаются|останавливается|стоп`
  - `проходят мимо|проходит мимо`
  - `затем|после этого|потом`
  - `начинает|начинают`
- `expected_marked_object_mentions` = число уникальных marked objects, чьи `name`/lemma обнаружены в source deterministic matcher-ом.
- `unsupported_action_present=true`, если в source найдено хотя бы одно lemma из frozen списка `unsupported_action_lemmas_v1`.

Contract rule:
- normalizer и iOS capture обязаны использовать один и тот же `runtime_source_expectations_v1`.
- если expectation block не удалось вычислить, event не может проходить как `low_quality_accept` и маркируется `expectation_compute_failed`.

## Bronze schema: runtime_parse_events.jsonl

Минимальный record:

```json
{
  "event_version": "sgv7_runtime_feedback_event_v1",
  "event_id": "rtp_2026_04_14_000921",
  "timestamp": "2026-04-14T10:21:03Z",
  "app_build": "ios_1.0.0_245",
  "contract_version": "sg_v7_contract_v1",
  "runtime_parser_version": "scene_parser_v1",
  "source": "2 актёра идут навстречу друг другу, останавливаются у компа, первый начинает курить",
  "source_sha256": "sha256:3e7b...",
  "marked_objects": [
    {
      "marker_id_hash": "mkh_18fa9e4c",
      "name_normalized": "комп",
      "type": "generic",
      "mentioned_in_source": true
    }
  ],
  "rule_based_result": {
    "script_json": { "...": "SceneScript" },
    "diagnostics": {
      "confidence": 0.62,
      "coverage": 0.57,
      "missingActors": false,
      "missingObjects": false,
      "unresolvedPronouns": false,
      "unresolvedMarkedObjects": false,
      "matchedMarkedObjectsCount": 1
    }
  },
  "llm_result": {
    "available": true,
    "model_id": "qwen2.5-1.5b-instruct.Q4_K_M",
    "prompt_hash": "ph_893d0a71",
    "generation_attempts": [
      {
        "attempt_index": 0,
        "max_tokens": 512,
        "duration_ms": 713,
        "raw_text": "{...}"
      }
    ],
    "raw_llm_text": "{...}",
    "json_candidates": ["{...}"],
    "parsed_script_json": { "...": "SceneScript" },
    "repaired_llm_output": { "...": "SceneScript" },
    "diagnostics": {
      "confidence": 0.58,
      "coverage": 0.49,
      "missingActors": false,
      "missingObjects": false,
      "unresolvedPronouns": false,
      "unresolvedMarkedObjects": true,
      "matchedMarkedObjectsCount": 0
    }
  },
  "selection": {
    "decision": "merge",
    "reason": "потеряны размеченные объекты (0 < 1)",
    "final_script_source": "merged"
  },
  "final_result": {
    "script_json": { "...": "SceneScript" },
    "diagnostics": {
      "confidence": 0.71,
      "coverage": 0.55,
      "missingActors": false,
      "missingObjects": false,
      "unresolvedPronouns": false,
      "unresolvedMarkedObjects": false,
      "matchedMarkedObjectsCount": 1
    }
  },
  "privacy": {
    "status": "clear",
    "pii_flags": []
  }
}
```

### Bronze invariants

- `event_id` immutable и уникален
- `source` хранится только после privacy gate уровня bronze
- `marker_id_hash` не должен содержать исходный `UUID`
- `selection.final_script_source` обязан совпадать с реально выбранным runtime output
- `parsed_script_json` и `repaired_llm_output` допускаются только если удалось декодировать JSON

## Silver schema: runtime_failures.jsonl

`runtime_failures.jsonl` должен быть self-contained bridge-артефактом. Он обязан поддерживать:
- preference pair extraction в Track 7
- real-runtime eval cases в Track 9
- cluster dashboards
- reviewer promotion without повторного чтения bronze logs

Минимальный record:

```json
{
  "failure_id": "rtf_2026_04_14_000921",
  "event_id": "rtp_2026_04_14_000921",
  "timestamp": "2026-04-14T10:21:03Z",
  "contract_version": "sg_v7_contract_v1",
  "source": "2 актёра идут навстречу друг другу, останавливаются у компа, первый начинает курить",
  "source_sha256": "sha256:3e7b...",
  "privacy_status": "clear",
  "marked_objects": [
    {
      "marker_id_hash": "mkh_18fa9e4c",
      "name_normalized": "комп",
      "type": "generic",
      "mentioned_in_source": true
    }
  ],
  "raw_llm_output": { "...": "bad_or_partial_json" },
  "raw_llm_text": "{...}",
  "repaired_llm_output": { "...": "repaired_json_or_null" },
  "diagnostics": {
    "rule_based_confidence": 0.62,
    "llm_confidence": 0.58,
    "final_confidence": 0.71,
    "unresolved_marked_objects": false,
    "matched_marked_objects_count": 1
  },
  "rule_based_reference_json": { "...": "rule_based_scene_script_snapshot" },
  "runtime_policy_inputs": {
    "rule_confidence": 0.62,
    "rule_object_count": 1,
    "rule_action_count": 3,
    "rule_has_dangling_targets": false,
    "rule_matched_marked_object_count": 1,
    "mentioned_marked_object_ids": ["object_marked_ab12"]
  },
  "final_decision": "merge",
  "final_script_source": "merged",
  "reject_reason": "потеряны размеченные объекты (0 < 1)",
  "failure_taxonomy": {
    "labels": ["lost_marked_object", "merge_required", "unsupported_action_lost"],
    "dominant": "lost_marked_object"
  },
  "cluster": {
    "failure_signature": "ffs_v1:lost_marked_object|merge|mo1|ord0|da1|beat2p",
    "cluster_id": "rfc_8ca7f3d1",
    "cluster_version": "runtime_cluster_v1"
  },
  "family_anchor": {
    "anchor_type": "unresolved_runtime_case",
    "anchor_value": "source_sha256:3e7b..."
  },
  "family_resolution_proof": {
    "input_anchor_type": "unresolved_runtime_case",
    "input_anchor_value": "source_sha256:3e7b...",
    "resolution_method": "",
    "resolved_graph_family_key": "",
    "proof_status": "quarantined"
  },
  "corrected_target_json": { "...": "good_json_or_null" },
  "gold_source": "pending_review",
  "correction_tier": "tier_c_reviewed_merge",
  "review_status": "pending",
  "review_notes": "",
  "train_eligibility": "review_only"
}
```

### Silver invariants

- `failure_id` immutable и уникален
- `contract_version` обязателен
- `source` может быть redacted, но тогда `privacy_status` не может быть `clear`
- `raw_llm_output` должен быть `dict` или JSON-строкой только если модель вернула parseable candidate
- `corrected_target_json` не должен появляться без `gold_source`, `correction_tier`, `review_status`
- `rule_based_reference_json` обязателен для всех silver-records с `privacy_status in {clear, redacted}`; без него case не может идти в Track 9
- `runtime_policy_inputs` обязателен для всех silver-records с `privacy_status in {clear, redacted}`; без него case не может идти в Track 9
- `train_eligibility` должен соответствовать policy из Track 6:
  - `accepted + tier_a_human_gold` -> `direct_sft`
  - `accepted + tier_b_deterministic_canonical` -> `direct_sft`
  - `accepted + tier_c_reviewed_merge` -> `hard_or_preference_only`
  - `* + tier_d_auto_repair_only` -> `reject_only`
  - `pending/manual review` -> `review_only`

## Track 9 bridge contract (`runtime_failures -> eval_cases`)

Для `eval_set=real_runtime` из [36-eval-harness-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/36-eval-harness-design.md) нормализатор обязан поддерживать deterministic export без reread bronze.

### Mapping contract v1

- `eval_case_id` <- `failure_id`
- `source_text` <- `source`
- `rule_based_reference_json` <- `rule_based_reference_json` (1:1)
- `runtime_policy_inputs` <- `runtime_policy_inputs` (1:1)
- `provenance.correction_tier` <- `correction_tier`
- `provenance.gold_source` <- `gold_source`
- `provenance.final_script_source` <- `final_script_source`
- `provenance.review_status` <- `review_status`
- `provenance.runtime_failure_id` <- `failure_id`
- `gold_target_json` <- `corrected_target_json` (только для `review_status=approved`)
- `eval_expectations` <- deterministic join с authoritative `CIR` по `sample_id|graph_hash|graph_family_key`; если join невозможен, case не `eval_bridge_ready`

### Export readiness

Silver case считается `eval_bridge_ready`, если одновременно:
- `privacy_status in {clear, redacted}`
- `review_status == approved`
- `correction_tier in {tier_a_human_gold, tier_b_deterministic_canonical, tier_c_reviewed_merge}`
- `corrected_target_json` заполнен
- `rule_based_reference_json` заполнен
- `runtime_policy_inputs` заполнен

Если хотя бы одно условие не выполнено:
- case остаётся в `runtime_failures.jsonl`
- `eval_bridge_ready = false`
- reason пишется в `eval_bridge_block_reason`

## Canonical failure taxonomy

Taxonomy multi-label, но `dominant` label обязан быть ровно один.

### Core labels

- `lost_marked_object`: source упоминает marked object, но final path потерял exact grounding
- `same_type_marker_conflict`: exact `object_marked_*` identity схлопнулась до `type`-only
- `ordinal_lost`: `first/second/third` не сохранились детерминированно
- `actor_disappeared`: один из актёров исчез из final graph
- `beat_collapse`: multi-phase scene схлопнулась в меньшее число beats
- `chronology_rewrite`: события присутствуют, но порядок нарушен
- `action_missing`: один из явных action-intents исчез
- `unsupported_action_lost`: unsupported action не ушёл в `described_action`
- `dangling_target`: action target отсутствует или неразрешим
- `minimal_valid_json`: формально валидный, но семантически пустой JSON
- `merge_required`: LLM-результат пришлось дополнять rule-based path
- `policy_acceptability_drift`: parser policy формально принял слабый output
- `repair_semantic_drift`: automatic repair изменил смысл, а не только синтаксис
- `privacy_blocked`: кейс полезен для cluster metrics, но blocked для dataset/eval export

### Deterministic labeling rules v1

Нормализатор обязан сначала вычислить `taxonomy_hints` из runtime signal, затем materialize-ить labels:

- `unresolvedMarkedObjects=true` или reject reason про marked objects -> `lost_marked_object`
- source содержит ordinal markers, но final graph не даёт стабильного actor binding -> `ordinal_lost`
- source/heuristics ожидают `>=2 beats`, а final graph имеет `1 beat` -> `beat_collapse`
- source содержит lemma из frozen списка [unsupported_action_lemmas_v1.txt](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runtime_feedback/contracts/unsupported_action_lemmas_v1.txt), но final graph не содержит `described_action` -> `unsupported_action_lost`
- финальный decision `merge` -> добавить `merge_required`
- финальный decision `accept`, но confidence/coverage выше порога не компенсируют poor structure -> `policy_acceptability_drift`
- action target в final graph `nil` для `approach|stop|stand|pass_by` -> `dangling_target`

Если deterministic labels дают несколько bucket-ов, `dominant` выбирается по приоритету:
1. `lost_marked_object`
2. `same_type_marker_conflict`
3. `ordinal_lost`
4. `actor_disappeared`
5. `beat_collapse`
6. `chronology_rewrite`
7. `unsupported_action_lost`
8. `action_missing`
9. `dangling_target`
10. `minimal_valid_json`
11. `policy_acceptability_drift`
12. `merge_required`
13. `repair_semantic_drift`
14. `privacy_blocked`

## Failure clustering strategy

### Почему не embedding-first

Для `v1` clustering должен быть:
- детерминированным
- воспроизводимым в CI/offline batch
- объяснимым reviewer-у
- независимым от внешних API

Поэтому source of truth в `v1`:
- lexical normalization
- structural failure signature
- deterministic anchor resolution

Embeddings допустимы только как optional analyst hint и не должны менять `cluster_id`.

### failure_signature_v1

Нормализатор обязан строить `failure_signature` из:
- `dominant taxonomy label`
- `final_decision`
- `marked_object_count_bucket`
- `same_type_marker_flag`
- `ordinal_flag`
- `described_action_flag`
- `estimated_beat_bucket`
- `actor_count_bucket`
- `privacy_status`

`bucket` правила фиксированы:
- `marked_object_count_bucket`: `0`, `1`, `2p`
- `estimated_beat_bucket`: `0`, `1`, `2`, `3p`
- `actor_count_bucket`: `0`, `1`, `2`, `3p`

Флаги фиксированы как `0|1`:
- `same_type_marker_flag`
- `ordinal_flag`
- `described_action_flag`

### failure_signature normalization policy (`failure_signature_normalization_v1`)

Перед расчётом `failure_signature` normalizer обязан:
- приводить текст к `lowercase`
- делать Unicode normalization `NFC`
- делать `ё -> е`
- схлопывать whitespace в single-space
- удалять edge punctuation
- заменять все exact marker names на `<marked_object>`
- заменять явные actor ordinals (`первый`, `второй`, `третий`) на `<ordinal_ref>`
- заменять числовые actor counts на `<actor_count>`

`cluster_id` обязан считаться только из:
- `failure_signature`
- `normalized_source_template` после policy выше

Любые дополнительные эвристики запрещены в `v1`.

Рекомендуемый формат:

```text
ffs_v1:<dominant>|<decision>|mo<bucket>|stm<0/1>|ord<0/1>|da<0/1>|beat<bucket>|act<bucket>|p<status>
```

Пример:

```text
ffs_v1:lost_marked_object|merge|mo1|stm0|ord0|da1|beat2p|act2|pclear
```

### cluster_id

`cluster_id` считается как:
- `cluster_id = "rfc_" + sha256(failure_signature + "|" + normalized_source_template)[:8]`

`normalized_source_template`:
- lowercased source
- collapsed whitespace
- removed edge punctuation
- `ё -> е`
- числа актёров сведены к bucket template
- exact marker names заменены на `<marked_object>`

Следствие:
- кластеры стабильны между batch runs
- одинаковая проблема на разных user phrasings всё ещё может попасть в один cluster, если template совпадает
- reviewer видит понятный reason, почему кейсы сгруппированы вместе

### Cluster manifest

`runtime_failure_clusters.json` должен хранить:
- `cluster_id`
- `failure_signature`
- `dominant_label`
- `case_count`
- `first_seen_at`
- `last_seen_at`
- `top_marked_object_types`
- `example_failure_ids`
- `resolved_pattern_family_distribution`
- `resolved_graph_family_distribution`
- `review_queue_size`
- `promotion_counts_by_tier`

## Family-anchor and dataset join policy

Track 7 не может безопасно использовать runtime sample без deterministic family join. Поэтому Track 10 обязан различать:

- `resolved` cases: есть `sample_id`, `graph_hash` или reviewer-assigned canonical family link
- `unresolved` cases: кейс полезен для cluster mining, но не split-able для Track 7

### Допустимые anchor types

- `sample_id`
- `graph_hash`
- `graph_family_key`
- `reviewed_pattern_family_seed`
- `unresolved_runtime_case`

### Правила

- raw runtime `failure_id` не является допустимым final family root для Track 7
- если case уже соответствует frozen eval case или ранее известному canonical sample, предпочтителен `sample_id`
- если reviewer руками привязал кейс к pattern family, это должно materialize-иться как `reviewed_pattern_family_seed`, а затем в офлайн batch преобразовываться в `graph_family_key` или уходить в quarantine
- если deterministic join не найден, `family_resolution_proof.proof_status` остаётся `quarantined`

Rule for `reviewed_pattern_family_seed` in v1:
- `reviewed_pattern_family_seed` сам по себе не является deterministic join source.
- такие кейсы остаются `quarantined` и `review_only`, пока не появится deterministic связь через `sample_id|graph_hash|graph_family_key`.
- normalizer не имеет права повышать такие кейсы в split-able artifacts эвристически.

### Resolved family anchor schema v1

Для split-able preference/export artifacts обязателен materialized anchor:

```json
{
  "family_anchor": {
    "anchor_type": "graph_family_key",
    "anchor_value": "gfk_9c0ab1de",
    "graph_family_key": "gfk_9c0ab1de",
    "split_family_id": "gfk_9c0ab1de"
  },
  "family_resolution_proof": {
    "input_anchor_type": "sample_id",
    "input_anchor_value": "sgv7-hard-000421",
    "resolution_method": "deterministic_cir_join_v1:sample_id",
    "resolved_graph_family_key": "gfk_9c0ab1de",
    "proof_status": "resolved"
  }
}
```

Обязательные поля:
- `family_anchor.anchor_type`
- `family_anchor.anchor_value`
- `family_anchor.graph_family_key`
- `family_anchor.split_family_id`
- `family_resolution_proof.input_anchor_type`
- `family_resolution_proof.input_anchor_value`
- `family_resolution_proof.resolution_method`
- `family_resolution_proof.resolved_graph_family_key`
- `family_resolution_proof.proof_status`

### Quarantined family anchor schema v1

Если deterministic join невозможен, кейс остаётся только для cluster/review:

```json
{
  "family_anchor": {
    "anchor_type": "unresolved_runtime_case",
    "anchor_value": "source_sha256:3e7b..."
  },
  "family_resolution_proof": {
    "input_anchor_type": "unresolved_runtime_case",
    "input_anchor_value": "source_sha256:3e7b...",
    "resolution_method": "",
    "resolved_graph_family_key": "",
    "proof_status": "quarantined"
  }
}
```

Ограничение:
- `proof_status=quarantined` запрещает admission в `preference_train|preference_val|preference_test` и в `direct_sft|hard_or_preference_only`.

## Corrected-sample export flow

### Ступени

1. Runtime event captured в bronze.
2. Silver normalizer выделяет failure candidate и taxonomy.
3. Cluster builder группирует кандидатов.
4. Reviewer или deterministic canonicalizer создаёт `corrected_target_json`.
5. Provenance policy присваивает `gold_source`, `correction_tier`, `review_status`.
6. Family resolution step пытается получить `graph_family_key`.
7. Track 6-compatible validation проверяет corrected target.
8. Только после этого case становится:
   - `direct_sft`
   - `hard_or_preference_only`
   - `review_only`
   - `reject_only`

### Provenance assignment

Разрешённые `correction_tier` и их meaning:
- `tier_a_human_gold`: человек вручную исправил или подтвердил gold
- `tier_b_deterministic_canonical`: target получен детерминированным canonicalizer-ом из проверенного structured source
- `tier_c_reviewed_merge`: merged/repaired target reviewed и одобрен
- `tier_d_auto_repair_only`: только авто-repair, без достаточного review

Разрешённые `gold_source`:
- `human_review`
- `deterministic_canonicalizer`
- `reviewed_merge`
- `pending_review`
- `auto_repair_only`

Разрешённые `review_status`:
- `pending`
- `approved`
- `rejected`
- `quarantined`

### Provenance state machine (`runtime_feedback_provenance_state_v1`)

Начальное состояние каждого silver-case:
- `review_status=pending`
- `gold_source=pending_review`
- `train_eligibility=review_only`
- `correction_tier` допускается как `provisional_tier` только для сортировки review queue

Разрешённые переходы:
1. `pending -> approved`
- требуются `corrected_target_json`, `gold_source != pending_review`, Track 6 pass
- `correction_tier` становится final
- `train_eligibility` вычисляется по tier/policy

2. `pending -> rejected`
- reviewer отклонил correction как непригодный
- `train_eligibility=reject_only`

3. `pending -> quarantined`
- deterministic family join невозможен или privacy-policy блокирует export
- `train_eligibility=review_only` либо `reject_only` по privacy outcome

4. `approved -> quarantined`
- post-review audit нашёл privacy/family-join violation
- downstream admission немедленно блокируется

Запрещённые комбинации:
- `review_status=approved` и `gold_source=pending_review`
- `review_status=approved` и пустой `corrected_target_json`
- `review_status=approved` и `correction_tier=tier_d_auto_repair_only`
- `review_status=approved` и `train_eligibility=review_only`
- `review_status in {rejected, quarantined}` и `train_eligibility=direct_sft`

### Export admission rules

Case может идти в `direct_sft`, только если:
- `privacy_status` не `blocked`
- `review_status == approved`
- `correction_tier in {tier_a_human_gold, tier_b_deterministic_canonical}`
- corrected target проходит Track 6 validators
- `family_resolution_proof.proof_status == resolved`

Case может идти только в `hard_or_preference_only`, если:
- `review_status == approved`
- `correction_tier == tier_c_reviewed_merge`
- corrected target валиден

Case остаётся `review_only`, если:
- reviewer ещё не завершил решение
- family join не resolved
- privacy требует redaction verification

Case становится `reject_only`, если:
- `correction_tier == tier_d_auto_repair_only`
- privacy blocked
- corrected target не проходит validators

## Privacy and safety constraints

### Что нельзя экспортировать из runtime как dataset signal

Нельзя экспортировать:
- AR world coordinates
- raw camera frames / screenshots
- device identifiers
- account identifiers
- исходные `UUID` размеченных объектов
- свободный текст reviewer notes с PII без redaction

### Privacy statuses

- `clear`: текст и metadata безопасны для export
- `redacted`: source хранится в redacted виде, кейс можно использовать для clustering/eval/preference только если смысл не разрушен
- `blocked`: кейс нельзя использовать для train/eval export, только для aggregate metrics

### Minimal privacy gate v1

Перед записью в silver-слой нужно выполнить:
- PII scan по `source`
- redaction телефонов, email, URL, явных account identifiers
- hash/pseudonymize всех local ids
- удалить AR-specific coordinates и anchors

Если redaction ломает семантическую ценность кейса:
- `privacy_status = blocked`
- `source` заменяется на краткое redacted summary
- cluster metrics сохраняются
- `train_eligibility = reject_only`

### Redaction quality gate (`redaction_quality_check_v1`)

После redaction запускается обязательный deterministic check:
- сохраняются ли `marked object mentions` (count и факт упоминания)
- сохраняются ли ordinal cues (`first/second/third`)
- сохраняется ли action-intent skeleton (минимум один action lemma)
- сохраняется ли исходный language tag (`ru`)

Результат gate:
- `pass` -> `privacy_status=redacted` допустим для review/eval/preference
- `fail` -> `privacy_status=blocked`, `train_eligibility=reject_only`

Normaliser обязан materialize-ить:
- `redaction_quality_check_version = "redaction_quality_check_v1"`
- `redaction_quality_check_result = pass|fail`
- `redaction_quality_fail_reasons` (массив кодов)

### Safety boundary

Runtime feedback loop не должен:
- автоматически делать новый gold из user prompt без validation
- подмешивать rejected/runtime-only artifacts в SFT напрямую
- считать `final_script_source=merged` достаточным основанием для `tier_b`

## Implementation handoff

### Рекомендуемые модули

Первая реализация Track 10 может быть разбита на:
- iOS `RuntimeFeedbackRecorder`
- iOS `RuntimeFeedbackEvent`/`RuntimeFailureRecord` Codable models
- offline `normalize_runtime_feedback.py`
- offline `cluster_runtime_failures.py`
- offline `review_and_promote_runtime_feedback.py`

### Suggested file ownership

- iOS capture: `shafinMultitool/SceneGeneratorModule/Services/`
- offline pipeline: новый пакет `docs/SGv7pipeline/runtime_feedback/`
- docs/contracts: этот design doc + обновления в README/backlog

## Backlog на реализацию

### Phase A. Runtime capture

- добавить structured feedback trace в `LLMParserService`
- добавить selection-event emission в `SceneParserService`
- реализовать `RuntimeFeedbackRecorder` с append-only JSONL writer
- писать `runtime_parse_manifest.json` с `app_build`, `contract_version`, `event_schema_version`

### Phase B. Failure normalization

- реализовать bronze -> silver normalizer
- materialize-ить taxonomy labels и `dominant`
- materialize-ить `failure_signature` и `cluster_id`
- внедрить `low_quality_accept_v1` (first-match policy table)
- вычислять `privacy_status`
- писать `runtime_failures.jsonl` и `runtime_review_queue.jsonl`

### Phase C. Cluster analytics

- строить `runtime_failure_clusters.json`
- считать counts by label / cluster / review status
- выделять top-3 clusters для следующего retraining cycle
- добавить frozen fixtures для проверки стабильности `failure_signature`/`cluster_id`

### Phase D. Corrected export

- добавить review/promotion workflow
- materialize-ить `corrected_target_json`
- присваивать `gold_source`, `correction_tier`, `review_status`, `train_eligibility`
- делать deterministic family resolution или quarantine
- валидировать `runtime_feedback_provenance_state_v1` и reject-ить недопустимые field combinations

### Phase E. Validation and integration

- прогонять corrected exports через Track 6 validators
- подавать approved runtime artifacts в Track 7 preference ingestion
- использовать approved runtime artifacts в Track 9 real-runtime eval bundle
- добавить deterministic exporter `runtime_failures -> eval_cases(real_runtime)` по `eval_bridge_ready`

## Test plan

Первая реализация обязана иметь:

- unit tests на taxonomy labeling по seed-примерам из [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- unit tests на `low_quality_accept_v1` (все правила `lqa_rule_1..6`)
- unit tests на `failure_signature_v1`
- unit tests на `failure_signature_normalization_v1` (включая `ё->е`, marker redaction, ordinal normalization)
- unit tests на `cluster_id` stability
- unit tests на `train_eligibility` mapping
- unit tests на `runtime_feedback_provenance_state_v1` transitions и invalid combinations
- unit tests на privacy redaction и `blocked` routing
- unit tests на `redaction_quality_check_v1`
- integration test на bronze -> silver normalization
- integration test на silver -> Track 7 preference pair extraction
- integration test на silver -> Track 9 real-runtime eval case packaging

## Design invariants

- feedback loop не bypass-ит Track 6 provenance policy
- `runtime_failures.jsonl` должен быть достаточен для downstream без чтения app console logs
- `runtime_failures.jsonl` должен содержать всё необходимое для deterministic export в `real_runtime` eval cases
- unresolved runtime cases допустимы для cluster mining, но не для split assignment
- `tier_d_auto_repair_only` никогда не считается SFT gold
- privacy gate выполняется до train/eval export, а не после
- top-3 failure clusters должны быть измеримы между model releases одинаковым способом
- `low_quality_accept_v1`, `failure_signature_normalization_v1` и `redaction_quality_check_v1` versioned и неизменяемы внутри одного contract_version

## Open questions

- нужен ли отдельный reviewer UI или v1 достаточно JSONL-sidecar workflow
- будет ли `reviewed_pattern_family_seed` достаточно, или нужен отдельный deterministic mapper `runtime_case -> CIR family`
