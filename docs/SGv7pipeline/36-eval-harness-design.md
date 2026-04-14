# 36. Eval Harness Design

## Цель

Зафиксировать исполнимый дизайн `eval harness` для `SG v7` и локальной `qwen 1.5B`, чтобы инженер мог реализовать:
- `docs/SGv7pipeline/eval/07_eval_local_model.py`
- пакет `docs/SGv7pipeline/eval/`

без дополнительных архитектурных решений по:
- структуре frozen eval bundles
- metric computation
- bucket reports
- release gate
- A/B compare protocol
- формату persisted report artifacts

Этот документ закрывает design-часть `Track 9` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/11-implementation-backlog.md).

## Scope

Track 9 отвечает за:
- офлайн replay eval локальной модели на frozen prompt bundle
- вычисление syntax, grounding, chronology и runtime-policy metrics
- bucket-level отчёты по critical failure classes
- paired A/B compare между baseline и candidate checkpoint
- deterministic release-gate summary для Track 8 и release decision
- хранение raw outputs, case-level scores и aggregated manifests

Track 9 не отвечает за:
- переопределение runtime/train contract
- пересборку train/val/test splits
- выбор training curriculum
- runtime logging внутри iOS приложения
- автоматическую коррекцию model outputs в gold target

## Исходные зависимости

Eval harness обязан опираться на уже зафиксированные source-of-truth артефакты:

- общий индекс пакета: [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/README.md)
- eval/release baseline: [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md)
- runtime feedback contract: [10-runtime-feedback-loop.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/10-runtime-feedback-loop.md)
- fixed decisions: [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
- runtime failure seeds: [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- codebase entry points: [16-codebase-entry-points.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/16-codebase-entry-points.md)
- runtime/train contract: [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)
- canonical CIR contract: [19-canonical-intermediate-representation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/19-canonical-intermediate-representation.md)
- pattern library: [20-pattern-library.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/20-pattern-library.md)
- graph generator design: [21-graph-generator-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/21-graph-generator-design.md)
- validator stack design: [30-validator-stack-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/30-validator-stack-design.md)
- dataset assembly design: [31-dataset-assembly-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/31-dataset-assembly-design.md)
- training harness playbook: [32-training-strategy-playbook.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/32-training-strategy-playbook.md)
- runtime parser selection policy: [SceneParserService.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/SceneParserService.swift)
- runtime diagnostics heuristics: [DiagnosticsCalculator.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/DiagnosticsCalculator.swift)

## Design Summary

Ключевые решения:
- eval harness работает по frozen eval bundle, а не по ad-hoc набору prompt-ов
- prompt для офлайн eval materialize-ится тем же contract formatter-ом, что и train/runtime, а bundle хранит prompt hash для drift detection
- scoring разделяется на два слоя: `model-only fidelity scoring` и `runtime-policy replay scoring`
- metrics считаются не только по валидности JSON, но и по exact grounding, ordinals, chronology и hard buckets
- case-level expectations не выводятся эвристически из свободного текста во время eval; они должны быть заранее materialized в bundle из authoritative `CIR` и runtime artifacts
- release gate выражается как deterministic threshold policy поверх paired A/B compare, а не как "визуально лучше"

Базовый flow:

```text
frozen eval bundle
  -> prompt replay through Track 0 contract formatter
  -> local model generation
  -> parse + canonical re-serialization
  -> model-only fidelity scoring against gold expectations
  -> runtime-policy replay against rule-based reference
  -> aggregate set metrics
  -> bucket metrics
  -> paired A/B deltas
  -> release gate summary
  -> persisted reports + raw outputs
```

## Почему Track 9 отделён от Track 8

Track 8 выбирает phase winner среди checkpoints, но не должен сам:
- определять metric semantics
- пересчитывать bucket rules на лету
- изобретать новый report schema
- менять release threshold под конкретный запуск

Отдельный Track 9 даёт:
- один источник правды для offline eval и release readiness
- одинаковые compare artifacts для `Phase 1`-`Phase 4`
- возможность повторно сравнивать checkpoints без нового training run
- прямую связку с runtime feedback taxonomy и hard buckets

## Owned Artifacts

Первая версия Track 9 должна materialize-ить:
- `eval_bundle_manifest.json`
- `eval_cases.jsonl`
- `raw_outputs.jsonl`
- `case_results.jsonl`
- `set_metrics.json`
- `bucket_metrics.json`
- `release_gate_summary.json`
- `eval_summary.md`
- `ab_summary.json`
- `ab_report.md`

Дополнительно для reproducibility:
- `prompt_contract_snapshot.json`
- `decoding_config_snapshot.json`
- `grammar_constraint_snapshot.json`
- `normalization_policy_snapshot.json`
- `runtime_policy_snapshot.json`
- `run_manifest.json`

## Eval Modes

### 1. Synthetic Held-Out

Нужен для:
- общей regression проверки
- контроля, что модель не ломает canonical structure на clean synthetic data

Обязательные свойства:
- cases frozen после Track 7
- не пересекаются по `graph_family_key` с training pool
- покрывают `core` и безопасную часть `hard`

### 2. Hard Held-Out

Нужен для:
- stress cases из critical buckets
- проверки exact grounding, ordinals и chronology под нагрузкой

Обязательные свойства:
- повышенная плотность `ordinal_cases`, `same_type_markers`, `three_beat_cases`, `unsupported_action_cases`
- не используется для training phase materialization

### 3. Real Runtime Replay

Нужен для:
- оценки реальных пользовательских формулировок
- проверки того, что candidate checkpoint улучшает фактический runtime outcome

Обязательные свойства:
- source берётся из reviewed runtime logs / corrected samples
- каждый case имеет provenance
- для каждого case есть `rule_based_reference_json` или эквивалентный runtime baseline artifact

### 4. Optional Preference Eval

Нужен только для `Phase 4`:
- pairwise comparison на `preference_val/test`
- не заменяет основной fidelity eval

## Input Contract

### Eval Bundle Structure

Первая версия harness должна принимать один каталог `eval_bundle_dir` со следующими canonical файлами:
- `eval_bundle_manifest.json`
- `eval_cases.jsonl`
- `prompt_contract_snapshot.json`
- `decoding_config_snapshot.json`
- `grammar_constraint_snapshot.json`
- `normalization_policy_snapshot.json`
- `runtime_policy_snapshot.json`

Опционально:
- `baseline_outputs.jsonl`
- `baseline_metrics.json`

### Manifest

Минимальный `eval_bundle_manifest.json`:

```json
{
  "bundle_id": "sgv7_eval_bundle_2026_04_14",
  "contract_version": "sg_v7_contract_v1",
  "bundle_version": "sgv7_eval_v1",
  "created_at": "2026-04-14T10:30:00Z",
  "required_contract_snapshots": [
    "prompt_contract_snapshot.json",
    "decoding_config_snapshot.json",
    "grammar_constraint_snapshot.json",
    "normalization_policy_snapshot.json",
    "runtime_policy_snapshot.json"
  ],
  "set_counts": {
    "synthetic_heldout": 300,
    "hard_heldout": 180,
    "real_runtime": 120
  },
  "required_metrics": [
    "json_valid_rate",
    "marked_object_recall",
    "exact_marked_object_id_accuracy",
    "beat_count_accuracy",
    "action_recall",
    "described_action_precision",
    "dangling_target_rate",
    "ordinal_actor_binding_accuracy",
    "target_resolution_accuracy",
    "chronology_phase_accuracy",
    "llm_accept_rate",
    "llm_merge_rate",
    "llm_reject_rate",
    "runtime_fallback_rate"
  ]
}
```

### Eval Case Schema

Каждый `eval_case` обязан быть self-contained и не требовать онлайн join-ов.

Минимальный record:

```json
{
  "eval_case_id": "hard-000421",
  "eval_set": "hard_heldout",
  "sample_id": "sgv7-hard-000421",
  "graph_family_key": "gfk_71d8f922",
  "contract_version": "sg_v7_contract_v1",
  "difficulty_bucket": "hard",
  "source_text": "2 актёра идут навстречу друг другу, останавливаются у компа, первый начинает курить сигарету",
  "marked_objects": [
    {
      "id": "object_marked_ab12",
      "name": "комп",
      "type": "generic",
      "mentioned_aliases": ["комп", "компа", "компу"]
    }
  ],
  "gold_target_json": {
    "...": "canonical SceneScript JSON"
  },
  "rule_based_reference_json": {
    "...": "runtime rule-based output snapshot"
  },
  "eval_expectations": {
    "expected_marked_object_ids": ["object_marked_ab12"],
    "expected_ordinal_bindings": {
      "first": "actor_1",
      "second": "actor_2"
    },
    "expected_action_units": [
      {
        "beat_index": 1,
        "actor_id": "actor_1",
        "action_type": "approach",
        "target_id": "actor_2",
        "phase_label": "move_toward_each_other"
      },
      {
        "beat_index": 2,
        "actor_id": "actor_1",
        "action_type": "stop",
        "target_id": "object_marked_ab12",
        "phase_label": "stop_near_marked_object"
      },
      {
        "beat_index": 3,
        "actor_id": "actor_1",
        "action_type": "described_action",
        "fallback_text_lemmas": ["курить"],
        "phase_label": "described_action_smoke"
      }
    ],
    "expected_phase_sequence": [
      "move_toward_each_other",
      "stop_near_marked_object",
      "described_action_smoke"
    ],
    "critical_eval_tags": [
      "ordinal_cases",
      "marked_object_morphology",
      "unsupported_action_cases",
      "three_beat_cases",
      "exact_marker_identity_cases"
    ]
  },
  "runtime_policy_inputs": {
    "rule_confidence": 0.78,
    "rule_object_count": 1,
    "rule_action_count": 3,
    "rule_has_dangling_targets": false,
    "rule_matched_marked_object_count": 1,
    "mentioned_marked_object_ids": ["object_marked_ab12"]
  },
  "provenance": {
    "origin": "runtime_reviewed",
    "correction_tier": "tier_c_reviewed_merge",
    "review_status": "approved",
    "gold_source": "corrected_target_json",
    "final_script_source": "merge_reviewed",
    "runtime_failure_id": "rtf-000921"
  }
}
```

Обязательные правила:
- `gold_target_json` должен уже быть canonical serialized target по Track 0 contract
- `rule_based_reference_json` обязателен для runtime-policy replay metrics
- `eval_expectations` materialize-ятся заранее из authoritative `CIR` и/или reviewed runtime artifact, а не вычисляются из `source_text`
- `critical_eval_tags` должны повторять must-have buckets из [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md)
- `graph_family_key` нужен для auditability и leakage checks между eval bundle и training artifacts
- `runtime_policy_inputs` обязателен для deterministic mirror policy replay
- для `eval_set=real_runtime` обязательны `provenance.correction_tier`, `provenance.gold_source`, `provenance.final_script_source`, `provenance.review_status` по [10-runtime-feedback-loop.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/10-runtime-feedback-loop.md)
- для `eval_set=real_runtime` поле `provenance.correction_tier` должно быть одним из `tier_a_human_gold`, `tier_b_deterministic_canonical`, `tier_c_reviewed_merge`
- `tier_d_auto_repair_only` не допускается как gold для release-gate eval и может использоваться только в отдельном diagnostics-only наборе

## Prompt Replay Contract

Harness обязан использовать тот же semantic contract, что и runtime/train:
- одинаковый section order
- одинаковый marked-object block
- одинаковый JSON contract
- одинаковый decoding config snapshot
- одинаковый grammar snapshot
- одинаковый normalization policy snapshot

Правило v1:
- harness получает `source_text` и `marked_objects` из case
- prompt materialize-ится локально через Track 0 formatter
- вычисленный `prompt_hash` сравнивается с hash из `prompt_contract_snapshot.json`
- hash grammar сравнивается с `grammar_constraint_snapshot.json`
- hash normalization policy сравнивается с `normalization_policy_snapshot.json`
- при mismatch eval run fail-fast завершает выполнение как `contract_drift`

Запрещено:
- подставлять для eval упрощённый prompt
- менять decoding config только ради лучшего офлайн score
- менять grammar или normalization policy только ради offline score
- silently чинить prompt drift внутри `07_eval_local_model.py`

## Runtime-Policy Replay

Eval harness должен считать не только gold-vs-pred metrics, но и replay outcome текущей runtime policy:
- `accept`
- `merge`
- `reject`

Для этого v1 использует materialized `rule_based_reference_json` из eval bundle.

Replay policy:
- candidate model output canonicalize-ится в predicted `SceneScript`
- predicted script сравнивается с `rule_based_reference_json`
- decision logic должна быть фиксирована как versioned mirror policy и повторять runtime boundary из [SceneParserService.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/SceneParserService.swift)
- decision replay живёт в Python harness как deterministic policy table, а не через прямой вызов Swift runtime

Почему нужен mirror policy вместо вызова iOS кода:
- eval должен быть reproducible вне приложения
- Track 8 должен уметь гонять compare на checkpoint-ах без iOS build шага
- rule-based baseline snapshot уже достаточно информативен для `accept/merge/reject/fallback` metrics

### Mirror Policy Contract (`runtime_policy_mirror_v1`)

Bundle обязан содержать `runtime_policy_snapshot.json` с:
- `mirror_policy_version`
- decision rules hash
- source runtime policy ref

`eval_case.runtime_policy_inputs` обязан содержать:
- `rule_confidence`
- `rule_object_count`
- `rule_action_count`
- `rule_has_dangling_targets`
- `rule_matched_marked_object_count`
- `mentioned_marked_object_ids`

Auxiliary signals, которые harness вычисляет из predicted script:
- `pred_actions_empty`
- `pred_object_count`
- `pred_action_count`
- `pred_has_beats`
- `pred_has_dangling_targets`
- `pred_matched_marked_object_count`
- `pred_unresolved_mentioned_marked_objects`
- `pred_confidence`

`pred_confidence` считается детерминированно локальной mirror-функцией из `runtime_policy_snapshot.json`. Если `pred_confidence` не удаётся вычислить, case помечается `policy_inputs_missing` и идёт в `reject`.

Decision table (правило first-match wins):
1. Если `pred_actions_empty=true` -> `reject`.
2. Если `pred_matched_marked_object_count < rule_matched_marked_object_count`:
- если `pred_has_beats=true` и `rule_object_count > 0` -> `merge`
- иначе -> `reject`
3. Если `pred_unresolved_mentioned_marked_objects=true` -> `reject`.
4. Если `pred_object_count < rule_object_count` и `rule_object_count > 0`:
- если `pred_has_beats=true` -> `merge`
- иначе -> `reject`
5. Если `pred_action_count + 1 < rule_action_count` -> `reject`.
6. Если `pred_has_dangling_targets=true` и `rule_has_dangling_targets=false`:
- если `rule_object_count > 0` -> `merge`
- иначе -> `reject`
7. Если `pred_confidence + 0.05 < rule_confidence` -> `reject`.
8. Иначе -> `accept`.

Deterministic mapping в runtime outcome:
- `accept` -> `runtime_outcome=llm_only`
- `merge` -> `runtime_outcome=fallback_partial`
- `reject` -> `runtime_outcome=fallback_full`

## Metric Layers

Harness считает четыре слоя метрик:

### 1. Contract And Syntax

- `prompt_contract_match_rate`
- `json_valid_rate`
- `canonical_parse_rate`
- `schema_valid_rate`

`prompt_contract_match_rate` нужен как hard precondition и не является release-improvement metric.

### 2. Semantic Fidelity

- `marked_object_recall`
- `exact_marked_object_id_accuracy`
- `beat_count_accuracy`
- `action_recall`
- `described_action_precision`
- `ordinal_actor_binding_accuracy`
- `target_resolution_accuracy`
- `chronology_phase_accuracy`

### 3. Runtime-Policy Metrics

- `llm_accept_rate`
- `llm_merge_rate`
- `llm_reject_rate`
- `runtime_fallback_rate`
- `dangling_target_rate`

### 4. Reporting Support Metrics

- `average_target_length`
- `prediction_action_count_mean`
- `prediction_beat_count_mean`
- `case_strict_success_rate`

Support metrics не участвуют в release gate напрямую, если это не оговорено отдельным thresholds file.

Release-critical required metrics:
- `json_valid_rate`
- `marked_object_recall`
- `exact_marked_object_id_accuracy`
- `beat_count_accuracy`
- `action_recall`
- `described_action_precision`
- `dangling_target_rate`
- `ordinal_actor_binding_accuracy`
- `target_resolution_accuracy`
- `chronology_phase_accuracy`
- `llm_accept_rate`
- `llm_merge_rate`
- `llm_reject_rate`
- `runtime_fallback_rate`

Support-only metrics:
- `average_target_length`
- `prediction_action_count_mean`
- `prediction_beat_count_mean`
- `case_strict_success_rate`

## Canonical Metric Definitions

### `json_valid_rate`

Доля cases, где raw model output:
- распарсился как JSON
- прошёл базовый cleanup boundary без фатальных ошибок

Формула:
- numerator: количество cases со статусом `json_valid=true`
- denominator: все cases в set

### `canonical_parse_rate`

Доля cases, где `json_valid` output:
- успешно приведён к canonical `SceneScript` representation
- прошёл canonical re-serialization без потери обязательных полей

Формула:
- numerator: cases with `canonical_parse=true`
- denominator: все cases в set

### `schema_valid_rate`

Доля cases, где canonical parsed output:
- проходит schema validation `SceneScript`
- не нарушает enum/id constraints

Формула:
- numerator: cases with `schema_valid=true`
- denominator: все cases в set

### `marked_object_recall`

Micro-averaged recall по всем gold marked-object references.

Формула:
- numerator: число gold marked object ids, которые реально присутствуют в predicted script
- denominator: общее число gold marked object ids в `eval_expectations.expected_marked_object_ids`

Если в case нет marked objects, case не входит в denominator метрики.

### `exact_marked_object_id_accuracy`

Accuracy по exact identity, а не по `type`.

Формула:
- numerator: число gold marked object references, где predicted id точно совпал с gold `object_marked_<SHORTID>`
- denominator: общее число gold marked object references

Case-level strict pass:
- все expected marked ids присутствуют
- нет подмены exact id на другой same-type marker

### `beat_count_accuracy`

Доля cases, где количество `beats` в predicted script равно gold beat count.

Формула:
- numerator: cases with `predicted_beats == gold_beats`
- denominator: cases with `gold_beats >= 1`

### `action_recall`

Micro-averaged recall по `expected_action_units`.

Action match должен сравнивать:
- `actor_id`
- `action_type`
- `target_id`, если он обязателен
- `beat_index`, если case принадлежит `chronology_sensitive_buckets`

Для `described_action` action match требует совпадение по `fallback_text_lemmas`.

`chronology_sensitive_buckets` v1:
- `ordinal_cases`
- `three_beat_cases`
- `unsupported_action_cases`
- `exact_marker_identity_cases`
- `reviewed_merge_cases`

### `described_action_precision`

Precision только по predicted actions c `action_type=described_action`.

Формула:
- numerator: predicted described actions, подтверждённые `expected_action_units`
- denominator: все predicted described actions

Если predicted described actions нет, metric:
- равна `1.0`, если gold described actions тоже нет
- равна `0.0`, если gold described action был обязателен

### `dangling_target_rate`

Доля predicted actions, которым нужен target, но target:
- отсутствует
- не существует среди actors/objects
- указывает не на тот semantic entity, если это явный exact-grounding case

Формула:
- numerator: число invalid target-bearing predicted actions
- denominator: число predicted actions, для которых target обязателен

### `ordinal_actor_binding_accuracy`

Accuracy по explicit ordinal bindings `first/second/third`.

Формула:
- numerator: число ordinal references, где predicted actor binding совпал с `eval_expectations.expected_ordinal_bindings`
- denominator: общее число expected ordinal bindings

### `target_resolution_accuracy`

Accuracy по gold actions, которые требуют правильный actor/object target.

Формула:
- numerator: число gold target-bearing actions, для которых predicted target существует и совпадает с gold target id
- denominator: число gold target-bearing actions

Эта метрика строже, чем `marked_object_recall`, потому что она требует не просто наличие объекта, а правильную привязку действия.

### `chronology_phase_accuracy`

Case-level accuracy по `expected_phase_sequence`.

Формула v1:
- case pass, если predicted normalized phase sequence точно совпадает с gold `expected_phase_sequence`
- aggregate metric: число passed cases / число cases с `expected_phase_sequence`

Нормализация phase sequence:
- sequence строится только по `eval_expectations.expected_action_units[*].phase_label`
- harness находит в predicted script ordered-matches для каждого expected action unit
- если unit не найден, в predicted sequence вставляется `missing::<phase_label>`
- внутри одного beat действия сравниваются в порядке появления в `expected_action_units`
- case pass требует:
- predicted sequence ровно равна `expected_phase_sequence`
- нет ни одного `missing::<phase_label>` токена
- sequence collapse по `type-only` запрещён для всех `chronology_sensitive_buckets`

### `llm_accept_rate`

Доля cases, где replay policy выбирает чистый predicted LLM output.

Формула:
- numerator: cases with `runtime_policy_decision=accept`
- denominator: все cases с `rule_based_reference_json`

### `llm_merge_rate`

Доля cases, где replay policy выбирает `merge`.

Формула:
- numerator: cases with `runtime_policy_decision=merge`
- denominator: все cases с `rule_based_reference_json`

### `llm_reject_rate`

Доля cases, где replay policy выбирает `reject`.

Формула:
- numerator: cases with `runtime_policy_decision=reject`
- denominator: все cases с `rule_based_reference_json`

### `runtime_fallback_rate`

Доля cases, где final runtime-like outcome требует fallback на rule-based path.

Формула v1:
- `runtime_fallback_rate = (merge_cases + reject_cases) / all_policy_cases`

Обоснование:
- `merge` уже означает неполный успех чистого model output
- `reject` означает полный fallback

### `average_target_length`

Средняя длина canonical predicted target в символах UTF-8 после canonical re-serialization.

Формула:
- numerator: сумма `len(predicted_canonical_json_string)` по cases с `canonical_parse=true`
- denominator: число cases с `canonical_parse=true`

### `prediction_action_count_mean`

Среднее число predicted actions на case.

Формула:
- numerator: сумма количества predicted actions по cases с `canonical_parse=true`
- denominator: число cases с `canonical_parse=true`

### `prediction_beat_count_mean`

Среднее число predicted beats на case.

Формула:
- numerator: сумма количества predicted beats по cases с `canonical_parse=true`
- denominator: число cases с `canonical_parse=true`

### `case_strict_success_rate`

Доля cases, где case-level critical checks полностью пройдены.

Case strict success = `true`, если одновременно:
- `json_valid=true`
- `schema_valid=true`
- `metric_flags.exact_marked_object_id_pass=true`
- `metric_flags.ordinal_binding_pass=true`
- `metric_flags.target_resolution_pass=true`
- `metric_flags.chronology_phase_pass=true`
- `runtime_policy_decision != reject`

Формула:
- numerator: число cases с `case_strict_success=true`
- denominator: все cases в set

## Bucket Metrics

Обязательные buckets v1:
- `ordinal_cases`
- `marked_object_morphology`
- `same_type_markers`
- `unsupported_action_cases`
- `three_beat_cases`
- `exact_marker_identity_cases`
- `reviewed_merge_cases`

Для каждого bucket считать минимум:
- `json_valid_rate`
- `marked_object_recall`
- `exact_marked_object_id_accuracy`
- `beat_count_accuracy`
- `action_recall`
- `ordinal_actor_binding_accuracy`
- `target_resolution_accuracy`
- `chronology_phase_accuracy`
- `dangling_target_rate`
- `llm_accept_rate`
- `llm_merge_rate`
- `llm_reject_rate`
- `runtime_fallback_rate`

Правило bucket assignment:
- bucket tags materialize-ятся в каждом case явно
- harness не должен заново классифицировать case по свободному тексту
- один case может принадлежать нескольким buckets

## Case Result Schema

Каждый обработанный case должен попасть в `case_results.jsonl`.

Минимальный result:

```json
{
  "eval_case_id": "hard-000421",
  "eval_set": "hard_heldout",
  "checkpoint_id": "phase3_candidate_004",
  "json_valid": true,
  "schema_valid": true,
  "runtime_policy_decision": "merge",
  "metric_flags": {
    "marked_object_recall_pass": true,
    "exact_marked_object_id_pass": true,
    "beat_count_pass": true,
    "action_recall_pass": true,
    "ordinal_binding_pass": true,
    "target_resolution_pass": true,
    "chronology_phase_pass": true
  },
  "metric_values": {
    "marked_object_recall_case": 1.0,
    "action_recall_case": 1.0,
    "described_action_precision_case": 1.0,
    "dangling_target_rate_case": 0.0
  },
  "bucket_tags": [
    "ordinal_cases",
    "unsupported_action_cases",
    "three_beat_cases"
  ],
  "diagnostics": {
    "parse_error": null,
    "gate_blocker": null,
    "notes": []
  }
}
```

## Failure Clusterization Policy

Для release-gate и markdown summary clusterization должна быть детерминированной.

Cluster inputs:
- `metric_flags`
- `runtime_policy_decision`
- `bucket_tags`
- `eval_set`

Primary failure code (first-match wins):
1. `json_invalid`
2. `schema_invalid`
3. `exact_marker_id_fail`
4. `ordinal_binding_fail`
5. `target_resolution_fail`
6. `chronology_phase_fail`
7. `beat_count_fail`
8. `action_recall_fail`
9. `fallback_reject`
10. `fallback_merge`
11. `pass`

Mapping к taxonomy из [10-runtime-feedback-loop.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/10-runtime-feedback-loop.md):
- `exact_marker_id_fail` -> `lost_marked_object` или `same_type_marker_conflict`
- `ordinal_binding_fail` -> `ordinal_lost`
- `target_resolution_fail` -> `dangling_target`
- `chronology_phase_fail` -> `beat_collapse`
- `action_recall_fail` -> `action_missing` или `unsupported_action_lost`

`cluster_id` v1:
- `cluster_id = "{eval_set}::{primary_failure_code}::{primary_bucket_or_none}"`
- `primary_bucket_or_none` это лексикографически первый bucket tag из case, если теги есть

Top-3 failure clusters:
- считаются отдельно для `hard_heldout` и `real_runtime`
- сортировка: `count desc`, затем `cluster_id asc`
- baseline compare идёт по пересечению baseline top-3 cluster ids и candidate cluster ids

Gate-compatible cluster regression rule:
- для каждого baseline top-3 cluster id candidate count не должен расти более чем на `max(2 cases, 10%)`

## Report Format

### JSON Reports

`set_metrics.json` должен содержать:
- run metadata
- aggregated metrics per eval set
- weighted overall metrics
- counts and denominators

`bucket_metrics.json` должен содержать:
- все bucket metrics
- support counts per bucket
- comparison against baseline when available

`release_gate_summary.json` должен содержать:
- `gate_status`
- `blocking_reasons`
- `passed_checks`
- `critical_deltas`
- `bucket_deltas`
- `recommended_action`

### Markdown Summary

`eval_summary.md` должен иметь фиксированные разделы:
1. Run metadata
2. Contract / decoding snapshot
3. Set-level metrics
4. Critical bucket metrics
5. Runtime-policy summary
6. Release gate verdict
7. Top failure clusters by count

Минимальный шаблон:

```text
# Eval Summary

## Run Metadata
- bundle_id:
- checkpoint_id:
- contract_version:
- decoding_config:
- grammar_snapshot:
- normalization_snapshot:
- runtime_policy_snapshot:

## Set Metrics
| Set | json_valid_rate | exact_marked_object_id_accuracy | ordinal_actor_binding_accuracy | target_resolution_accuracy | chronology_phase_accuracy | runtime_fallback_rate |

## Critical Buckets
| Bucket | cases | exact_marked_object_id_accuracy | ordinal_actor_binding_accuracy | chronology_phase_accuracy | runtime_fallback_rate | delta_vs_baseline |

## Release Gate
- status:
- blockers:
- improvements:
- recommended_action:
```

## Release Gate

Release gate v1 должен быть baseline-relative, но поддерживать fallback absolute floors на случай первого запуска.

Direction rules:
- для accuracy-like metrics improvement = `candidate - baseline`, regression если значение `< 0`
- для error-like metrics improvement = `baseline - candidate`, regression если значение `< 0`

Core metrics из [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md):
- `json_valid_rate`
- `marked_object_recall`
- `exact_marked_object_id_accuracy`
- `beat_count_accuracy`
- `action_recall`
- `described_action_precision`
- `dangling_target_rate`
- `ordinal_actor_binding_accuracy`
- `target_resolution_accuracy`
- `chronology_phase_accuracy`
- `llm_accept_rate`
- `llm_merge_rate`
- `llm_reject_rate`
- `runtime_fallback_rate`

### Gate 0. Contract Integrity

Обязательные условия:
- `contract_version` совпадает с frozen bundle
- `prompt_contract_snapshot.prompt_hash` совпадает с expected hash из frozen bundle snapshot
- `prompt_contract_match_rate = 1.0`
- `decoding_config_snapshot` совпадает с expected snapshot
- `grammar_constraint_snapshot` совпадает с expected snapshot
- `normalization_policy_snapshot` совпадает с expected snapshot
- `runtime_policy_snapshot` совпадает с expected snapshot

Нарушение Gate 0 блокирует релиз независимо от остальных метрик.

### Gate 1. Critical No-Regression Metrics

Candidate не проходит gate, если против baseline есть regression хотя бы по одному core metric.

No-regression checks:
- `json_valid_rate`, `marked_object_recall`, `exact_marked_object_id_accuracy`, `beat_count_accuracy`, `action_recall`, `described_action_precision`, `ordinal_actor_binding_accuracy`, `target_resolution_accuracy`, `chronology_phase_accuracy`, `llm_accept_rate` должны иметь `candidate >= baseline`
- `dangling_target_rate`, `llm_merge_rate`, `llm_reject_rate` должны иметь `candidate <= baseline`
- `runtime_fallback_rate` должен строго уменьшаться: `candidate < baseline`

Если baseline отсутствует, используются fallback floors:
- `json_valid_rate >= 0.95`
- `marked_object_recall >= 0.90`
- `exact_marked_object_id_accuracy >= 0.90`
- `beat_count_accuracy >= 0.85`
- `action_recall >= 0.85`
- `described_action_precision >= 0.85`
- `ordinal_actor_binding_accuracy >= 0.90`
- `target_resolution_accuracy >= 0.90`
- `chronology_phase_accuracy >= 0.85`
- `runtime_fallback_rate <= 0.25`

### Gate 2. Hard Bucket Guardrails

Critical buckets:
- `ordinal_cases`
- `marked_object_morphology`
- `same_type_markers`
- `unsupported_action_cases`
- `three_beat_cases`
- `exact_marker_identity_cases`
- `reviewed_merge_cases`

Gate 2 metric set:
- `exact_marked_object_id_accuracy`
- `ordinal_actor_binding_accuracy`
- `target_resolution_accuracy`
- `chronology_phase_accuracy`
- `runtime_fallback_rate`
- `dangling_target_rate`

Bucket delta semantics:
- accuracy-like bucket metrics: `delta_pp = candidate - baseline`
- error-like bucket metrics (`runtime_fallback_rate`, `dangling_target_rate`): `delta_pp = baseline - candidate`

Rule for buckets with `support >= 40`:
- bucket fails, если любой `delta_pp < -0.2`

Rule for buckets with `support < 40`:
- считать `bucket_failed_case`, если выполнено хотя бы одно из условий:
- `exact_marked_object_id_pass=false`
- `ordinal_binding_pass=false`
- `target_resolution_pass=false`
- `chronology_phase_pass=false`
- `runtime_policy_decision=reject`
- bucket fails, если `candidate_failed_cases - baseline_failed_cases > 1`

Tie-break rule:
- значения ровно на пороге (`delta_pp = -0.2` или `failed_case_delta = 1`) считаются `pass`.

### Gate 3. Improvement Requirement

Кандидат проходит Gate 3 только если одновременно:
- improvement condition выполнен:
- либо `>= 0.5 pp` в двух разных critical buckets по любому Gate 2 metric
- либо `>= 1.0 pp` в одном critical bucket по любому Gate 2 metric
- на `hard_heldout` нет regressions по Gate 2 metric set
- на `real_runtime` `runtime_fallback_rate` строго ниже baseline

Это правило фиксирует требование из `09`: checkpoint должен не только не ломать качество, но и улучшать critical buckets.

### Gate 4. Runtime Outcome Sanity

На `real_runtime`:
- `llm_reject_rate` не должен расти
- `llm_merge_rate` может вырасти только если одновременно падает `llm_reject_rate` и не ухудшаются grounding metrics
- top-3 failure clusters проверяются по [Failure Clusterization Policy](#failure-clusterization-policy):
- baseline top-3 cluster counts не должны расти выше лимита `max(2 cases, 10%)`
- hard runtime prompts не должны ухудшаться (эквивалентно отсутствию Gate 2 regressions в hard buckets)

### Gate Output

`release_gate_summary.json` должен возвращать один из статусов:
- `pass`
- `pass_with_watchlist`
- `fail`

`pass_with_watchlist` допускается только если:
- Gate 0-4 пройдены
- есть minor ухудшение только в support metric либо non-critical small bucket

## A/B Protocol

Сравнение `model_a` и `model_b` обязано быть paired и reproducible.

### Invariants

Обе модели сравниваются на:
- одном и том же `eval_bundle`
- одном и том же `contract_version`
- одном и том же `prompt formatter`
- одном и том же `decoding_config`
- одном и том же `post-parse canonicalization boundary`

Обязательно сохранять:
- raw outputs обеих моделей
- case-level scores
- aggregated deltas

### Paired Comparison Logic

Для каждого case вычисляется:
- `model_a_case_score`
- `model_b_case_score`
- `winner`

`winner` определяется по release-critical priority:
1. `json_valid`
2. `exact_marked_object_id_pass`
3. `ordinal_binding_pass`
4. `target_resolution_pass`
5. `chronology_phase_pass`
6. `runtime_policy_decision` preference order: `accept > merge > reject`

Если обе модели равны по всем release-critical priority checks, case получает `tie`.

### A/B Artifacts

Harness должен materialize-ить:
- `ab_summary.json`
- `ab_report.md`
- `paired_case_results.jsonl`

`ab_summary.json` обязан содержать:
- `wins_model_a`
- `wins_model_b`
- `ties`
- deltas по всем release-critical metrics
- deltas по всем critical buckets

### Promotion Rule From A/B

Candidate checkpoint может заменить baseline только если:
- проходит release gate
- не проигрывает baseline по paired case wins на `real_runtime`
- имеет non-negative net wins на `hard_heldout`

## CLI Contract

Первая версия `07_eval_local_model.py` должна поддерживать минимум два режима:
- `score`
- `compare`

Пример `score`:

```bash
python3 docs/SGv7pipeline/eval/07_eval_local_model.py \
  --mode score \
  --eval-bundle-dir /path/to/eval_bundle \
  --checkpoint-id phase3_candidate_004 \
  --model-path /path/to/checkpoint \
  --output-dir /path/to/out \
  --seed 20260414
```

Пример `compare`:

```bash
python3 docs/SGv7pipeline/eval/07_eval_local_model.py \
  --mode compare \
  --eval-bundle-dir /path/to/eval_bundle \
  --candidate-report /path/to/candidate \
  --baseline-report /path/to/baseline \
  --output-dir /path/to/out
```

Минимальные exit codes:
- `0` - run completed, release gate may still be `fail`
- `2` - contract drift / malformed bundle
- `3` - fatal model inference error

## Suggested Package Layout

Рекомендуемая структура будущего implementation:

```text
docs/SGv7pipeline/eval/
  07_eval_local_model.py
  __init__.py
  bundle.py
  contract.py
  inference.py
  scorer.py
  runtime_policy.py
  reporter.py
  release_gate.py
  tests/
```

Ownership модулей:
- `bundle.py` отвечает за manifest/case loading и validation
- `contract.py` за prompt hash и decoding snapshot checks
- `inference.py` за model invocation
- `scorer.py` за metric computation
- `runtime_policy.py` за accept/merge/reject replay
- `reporter.py` за JSON/Markdown artifacts
- `release_gate.py` за threshold evaluation

## Implementation Backlog

Порядок реализации v1:
1. Загрузчик bundle и manifest validation
2. Prompt/decoding/grammar/normalization/runtime-policy drift checks
3. Model invocation + raw output persistence
4. Canonical parse + case-level scorer
5. Runtime-policy replay
6. Set metrics and bucket metrics
7. Release gate summary
8. Paired A/B compare
9. Regression tests и fixture bundle

## Test Plan

Обязательные тесты для implementation:

- unit test на manifest validation и missing required files
- unit test на `contract_drift` при mismatch prompt hash
- unit test на `contract_drift` при mismatch grammar snapshot
- unit test на `contract_drift` при mismatch normalization snapshot
- unit test на `json_valid_rate` и `schema_valid_rate` aggregation
- unit test на `exact_marked_object_id_accuracy` для same-type markers
- unit test на `ordinal_actor_binding_accuracy` для `first/second/third`
- unit test на `chronology_phase_accuracy` для three-beat cases
- unit test на `runtime_fallback_rate = merge + reject`
- unit test на `runtime_policy_mirror_v1` decision table (accept/merge/reject)
- unit test на `Failure Clusterization Policy` и top-3 cluster compare
- golden test на `release_gate_summary.json`
- golden test на `ab_summary.json`
- smoke test на маленьком frozen eval bundle

## Open Questions

Открытые вопросы, не блокирующие v1 design:
- нужен ли в `chronology_phase_accuracy` отдельный relaxed companion metric помимо strict exact sequence
- стоит ли для real runtime eval сохранять ещё и original runtime decision рядом с replay decision для drift audit
- нужен ли отдельный bucket для `three_actor_cases` уже в v1 или его можно временно покрыть через `ordinal_cases`

## Definition Of Done For Design

Design считается достаточным, если:
- инженер может реализовать `07_eval_local_model.py` без новых решений по schema, metrics, reporting и gate semantics
- frozen eval bundle format определён
- обязательные bucket metrics определены
- report artifacts и release gate имеют фиксированный contract
- A/B protocol исключает ad-hoc сравнение "на глаз"
