# 10. Eval Harness (PR-014)

Статус: design spec (source-of-truth) + reference implementation

Дата: 2026-04-20

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md)
- [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md)
- [07-critique-engine.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/07-critique-engine.md)
- [08-ui-integration.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/08-ui-integration.md)
- [09-reasoning-provider.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/09-reasoning-provider.md)
- [camera-analysis-v1-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-v1-architecture.md)
- [example_eval_bundle_manifest.json](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/example_eval_bundle_manifest.json)
- [example_golden_cases.jsonl](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/example_golden_cases.jsonl)
- [example_compare_report.json](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/example_compare_report.json)
- [example_report.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/example_report.md)

## Цель

Зафиксировать воспроизводимый `eval harness` для `Camera Analysis v1`, чтобы можно было:
- сравнивать `legacy baseline` и новый pipeline на frozen кейсах;
- измерять не только `issue detection`, но и полезность действий и faithfulness объяснения;
- отдельно видеть поведение на `good frames`, `needs_fix`, `fallback` и scene-aware исключениях;
- выпускать новые PR по deterministic core и optional reasoning без "визуально кажется лучше".

Этот документ закрывает design-часть `Track 9 / PR-014` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md).

## Scope

`PR-014` отвечает за:
- frozen curated eval bundle;
- schema для golden cases;
- deterministic scoring issues / strengths / actions / explainability;
- baseline-vs-current compare artifacts;
- bucket reports по cinematic failure classes;
- report, который читается инженером и подходит для демо/комиссии.

`PR-014` не отвечает за:
- переопределение domain contracts;
- runtime logging inside the app;
- ручную экспертную prose-оценку как основной источник истины;
- замену unit tests end-to-end eval'ом.

## Design Summary

Ключевые решения:
- source-of-truth для `v1` eval строится на frozen structured inputs, а не на ad-hoc скриншотах и свободных текстах;
- обязательный replay path использует `FrameFeatureSnapshot` + `SceneSemanticsReport` как детерминированный вход для critique/planner/explainability;
- image references могут храниться для audit/demo, но scoring не зависит от ручного перечитывания картинки;
- metrics разделены на 4 слоя: `detection`, `action usefulness`, `explanation faithfulness`, `live behavior`;
- human prose review допускается только как secondary appendix, а не как release gate;
- compare выполняется попарно `baseline vs candidate` на одном frozen bundle.

Базовый flow:

```text
frozen eval bundle
  -> load golden case
  -> replay candidate pipeline on structured inputs
  -> materialize critique / plan / trace / live-hint projection
  -> deterministic case scoring
  -> set metrics
  -> bucket metrics
  -> baseline-vs-current paired compare
  -> markdown + json reports
```

## Eval Layers

### 1. Contract Replay Layer

Обязательный слой `v1`.

Вход:
- `FrameFeatureSnapshot`
- `SceneSemanticsReport`

Выход candidate:
- `CritiqueReport`
- `RecommendationPlan`
- `ExplainabilityTraceBundle`
- `LiveHintProjection` или эквивалентный presentation snapshot

Зачем нужен:
- полностью воспроизводим;
- не зависит от drift в vision-инференсе;
- измеряет именно core logic, который мы строим в `PR-007 ... PR-013`.

### 2. Presentation Layer Eval

Нужен для проверки:
- что `live` показывает одну главную подсказку;
- что `pause` подтверждает хорошие кадры и не плодит fake issues;
- что summary/expanded sections не противоречат structured critique.

Этот слой измеряется по структурированным presentation artifacts, а не по субъективному "текст красивый/некрасивый".

### 3. Optional Image Audit Layer

Не является gate для `v1`, но полезен для:
- демонстрации комиссии;
- ручной sanity-check привязки кейсов к реальным кадрам;
- последующего перехода к end-to-end image replay.

Image audit может хранить:
- `image_ref`
- `annotated_ref`
- короткую human note

Но эти поля не участвуют в core score.

## Owned Artifacts

Минимальный набор артефактов `PR-014`:
- `eval_bundle_manifest.json`
- `golden_cases.jsonl`
- `case_results.jsonl`
- `set_metrics.json`
- `bucket_metrics.json`
- `compare_report.json`
- `eval_summary.md`

Опционально:
- `baseline_outputs.jsonl`
- `candidate_outputs.jsonl`
- `image_refs_manifest.json`
- `review_appendix.md`

## CLI Contract

Для implement-этапа рекомендуется зафиксировать такой интерфейс:

```text
python3 docs/cameraanalysis/eval/run_eval.py \
  --bundle <eval_bundle_dir> \
  --candidate <candidate_artifact_or_mode> \
  --baseline <baseline_artifact_or_mode> \
  --output <report_dir>
```

Требования к CLI:
- одинаковый bundle для baseline и candidate;
- одинаковая scoring policy;
- deterministic seed/write order;
- все report files materialize-ятся в один output dir.
- baseline путь обязан идти через `LegacyFeatureAdapter + LegacyEvalAdapter` (см. `Baseline Adapter Contract` ниже), без ad-hoc scorer shortcuts.
- для `live_sequence` scorer обязан использовать deterministic metadata из `sequenceMeta` и frame-level flags (`jitterExempt`, `countsTowardStability`) из `Sequence Case Extension` ниже.

## Baseline Adapter Contract

Чтобы paired compare был исполним для `legacy_suggestion_engine`, eval harness обязан иметь явный deterministic adapter, а не ad-hoc логику внутри scorer.

Минимальный baseline replay path:

```text
FrameFeatureSnapshot
  -> LegacyFeatureAdapter
  -> CoachingFeatures
  -> fresh SuggestionEngine instance
  -> legacy suggestions
  -> LegacyEvalAdapter
  -> LegacyEvalProjection
  -> shared scorer
```

Обязательные правила:
- для каждого eval case создается новый `SuggestionEngine` instance;
- history/cooldown counters не переносятся между кейсами;
- `live` single-frame cases используют `nextSuggestion(from:)`;
- `pause` single-frame cases используют `rankedSuggestions(from:topN:)`;
- `live_sequence` использует один свежий engine instance на sequence, чтобы anti-flicker/cooldown поведение было воспроизводимо внутри sequence.

### `LegacyFeatureAdapter`

`LegacyFeatureAdapter` детерминированно преобразует `FrameFeatureSnapshot` в `CoachingFeatures`:
- `composition.horizontalOffset` <- `snapshot.composition.horizontalOffset`
- `composition.verticalOffset` <- `snapshot.composition.verticalOffset`
- `composition.saliencyLeftRightBalance` <- `snapshot.composition.saliencyLeftRightBalance`
- `composition.saliencyTopBottomBalance` <- `snapshot.composition.saliencyTopBottomBalance`
- `composition.subjectAreaRatio` <- `snapshot.composition.subjectAreaRatio`
- `horizon.angle` <- `snapshot.horizon.angleDegrees`
- `horizon.confidence` <- `snapshot.horizon.confidence`
- `lighting.backlightIndex` <- `snapshot.lighting.backlightIndex`
- `lighting.keyToFillRatio` <- `snapshot.lighting.keyToFillRatio ?? 1.0`
- `lighting.exposureBiasHint` <- `snapshot.lighting.exposureBiasHint`
- `motion.shakeLevel` <- `snapshot.motion.shakeLevel`
- `motion.state` <- `snapshot.motion.state`
- `subject.isFace` <- `snapshot.subjectSignals.faceDetected`
- `subject.isPerson` <- `snapshot.subjectSignals.personDetected`
- `subject.count` <- `snapshot.subjectSignals.personCount`
- `subject.objectName` <- `snapshot.subjectSignals.topObjectLabel`
- `aestheticScore` <- `snapshot.aesthetics.score`

### `LegacyEvalProjection`

Legacy path не обязан притворяться полным новым pipeline. Вместо этого он обязан materialize-ить deterministic normalized projection:

```text
LegacyEvalProjection
- evalCaseId: String
- mode: AnalysisMode
- suggestionTypes: [SuggestionType]
- primarySuggestionType: SuggestionType?
- primaryActionType: ActionTypeV1?
- proxyVerdict: FrameVerdict
- proxyIssueTypes: [IssueTypeV1]
- fallbackState: LegacyFallbackState
- proxyTraceAvailable: Bool
- proxyTraceStageCoverage: LegacyTraceCoverage
```

```text
LegacyFallbackState
- visible_suggestion
- hidden_due_to_motion
- no_suggestion

LegacyTraceCoverage
- hasObservation: Bool
- hasInterpretation: Bool
- hasRecommendation: Bool
```

### Proxy mapping rules

`primaryActionType` обязан использовать тот же deterministic mapping, что и legacy bridge path в runtime UI.

`proxyIssueTypes` задаются только по фиксированной таблице:
- `horizon` -> `horizon_distracts`
- `composition` -> `insufficient_look_space`, если `sceneSemantics.readability.lookSpaceAdequate == false` и `primarySubject.kind` входит в `{face, person, group}`; иначе `subject_too_close_to_edge`
- `lighting` -> `backlight_hides_subject`, если `snapshot.lighting.backlightIndex >= 0.35`; иначе `subject_not_prominent_enough`
- `exposure` -> `backlight_hides_subject`, если `snapshot.lighting.backlightIndex >= 0.35`; иначе `subject_not_prominent_enough`
- `lens` -> `subject_not_prominent_enough`
- `other` -> `scene_has_no_clear_focus`

`proxyVerdict` задается только по этим правилам:
- `hidden_due_to_motion` -> `mixed`
- `primarySuggestionType == nil` и `mode == pause` -> `good`
- `primarySuggestionType == nil` и `mode == live` -> `good`
- `primarySuggestionType` входит в `{horizon, composition, lighting, exposure}` -> `needs_fix`
- `primarySuggestionType` входит в `{lens, other}` -> `mixed`

`proxyTraceAvailable` и `proxyTraceStageCoverage` считаются по deterministic proxy trace:
- если suggestion есть, adapter обязан materialize-ить:
  - observation item из threshold-crossing feature keys;
  - interpretation item вида `legacy heuristic raised <suggestionType>`;
  - recommendation item из `primaryActionType`;
- если suggestion нет, proxy trace отсутствует.

Это делает baseline explanation metrics воспроизводимыми и избавляет implement-этап от скрытых adapter-решений.

## Eval Bundle Contract

### Manifest

Минимальный `eval_bundle_manifest.json`:

```json
{
  "bundle_id": "camera_analysis_eval_v1_demo",
  "bundle_version": "camera_analysis_eval_v1",
  "contract_version": "camera_analysis_contract_v1",
  "created_at": "2026-04-20T12:00:00Z",
  "baseline_adapter_version": "legacy_eval_adapter_v1",
  "required_inputs": [
    "feature_snapshot",
    "scene_semantics"
  ],
  "required_outputs": [
    "critique_report",
    "recommendation_plan",
    "explainability_trace"
  ],
  "eval_sets": {
    "pause_curated": 0,
    "live_curated": 0,
    "live_sequence": 0
  }
}
```

Пример лежит в [example_eval_bundle_manifest.json](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/example_eval_bundle_manifest.json).

### Golden Case Schema

Каждый case должен быть self-contained и не требовать runtime join-ов.

Минимальный record:

```json
{
  "eval_case_id": "pause-edge-backlight-001",
  "eval_set": "pause_curated",
  "case_kind": "single_frame_pause",
  "bucket_tags": [
    "single_subject",
    "edge_pressure",
    "backlight",
    "needs_fix"
  ],
  "image_ref": "optional://demo/frame001.jpg",
  "input": {
    "feature_snapshot": {
      "...": "FrameFeatureSnapshot"
    },
    "scene_semantics": {
      "...": "SceneSemanticsReport"
    }
  },
  "gold_expectations": {
    "verdict": "needs_fix",
    "required_issues": [
      "subject_too_close_to_edge",
      "backlight_hides_subject"
    ],
    "forbidden_issues": [
      "horizon_distracts"
    ],
    "required_strengths": [],
    "forbidden_strengths": [
      "good_light_emphasis"
    ],
    "allowed_primary_actions": [
      "move_frame_left",
      "improve_front_light"
    ],
    "required_fix_types": [
      "reframing",
      "lighting_adjustment"
    ],
    "fallback_expected": false,
    "good_frame_policy": "must_not_confirm_good_frame",
    "explainability": {
      "required_issue_links": [
        "subject_too_close_to_edge",
        "backlight_hides_subject"
      ],
      "required_action_support_issue_count": 1,
      "require_observation_interpretation_recommendation_chain": true,
      "summary_must_reference_any": [
        "edge",
        "light"
      ]
    }
  }
}
```

### Sequence Case Extension

Для `live_sequence` вместо одного frozen input используется:

```text
sequenceMeta:
- stabilityAnchorFrame: Int?          // с какого кадра начинаем мерить time-to-stable
- stablePrimaryAction: ActionTypeV1?  // целевое action после стабилизации
- maxFramesToStable: Int?             // допустимое окно до правильного stable hint

sequence:
- frameOrdinal: Int
- featureSnapshot
- sceneSemantics
- expectedHintState
- expectedPrimaryAction?
- jitterExempt: Bool                  // переходы с/на этот кадр не считаются jitter
- countsTowardStability: Bool         // этот кадр участвует в поиске first stable correct hint
```

`expectedHintState`:
- `visible_action`
- `hidden_due_to_motion`
- `hidden_due_to_low_confidence`
- `confirm_good_frame`

Правила scoring:
- `hint_jitter_rate` считает только смены между соседними кадрами, где оба кадра имеют `jitterExempt == false`;
- если хотя бы один из двух соседних кадров `jitterExempt == true`, такой переход не штрафуется;
- `frames_to_stable_correct_hint` считается только от `sequenceMeta.stabilityAnchorFrame`;
- correct stable hint найден, когда кадр имеет `countsTowardStability == true`, `expectedHintState == visible_action` и candidate `primaryAction == stablePrimaryAction`;
- если correct stable hint не найден до `maxFramesToStable`, sequence получает hard fail по stability metric.
- если `sequenceMeta` или любой required frame-level flag отсутствует, harness обязан считать такой sequence contract-invalid и завершать run ошибкой валидации (а не пытаться угадывать transition policy).

Это делает stability scoring детерминированным и не оставляет implement-этапу свободы интерпретации.

## Quality Metrics

## 1. Detection Metrics

### `verdict_accuracy`
- exact match между candidate `CritiqueReport.verdict` и gold `verdict`.

### `issue_precision`, `issue_recall`, `issue_f1`
- считаются по `IssueTypeV1`;
- `required_issues` дают recall target;
- `forbidden_issues` штрафуют precision;
- для `v1` score считается на уровне типов, а не free-text rationale.

### `strength_precision`, `strength_recall`, `strength_f1`
- аналогично, но по `StrengthTypeV1`.

### `no_false_problem_rate`
- доля `good-frame` кейсов, где candidate не создал критических или запрещенных issues.
- это отдельная метрика, потому что для UX очень важно не "ругать" удачный кадр.

### `fallback_policy_accuracy`
- доля кейсов, где `fallbackUsed` совпал с `fallback_expected`.

### `region_grounding_iou_mean`
- optional `v1.1`;
- средний IoU между candidate `affectedRegion/targetRegion` и gold region, если gold region materialized.
- не является блокером для первой версии, но schema должна это позволять.

## 2. Action Usefulness Metrics

### `primary_action_match_rate`
- candidate `primaryAction.actionType` входит в `allowed_primary_actions`.

### `fix_type_coverage_rate`
- объединение `suggestedFixTypes` из candidate issues покрывает `required_fix_types`.
- применяется только к corrective-кейсам, где `required_fix_types` не пустой.
- `required_fix_types` не должен содержать `leave_frame_as_is`; этот action относится к no-change ветке и проверяется через `good_frame_confirmation_rate` + `allowed_primary_actions`.
- если в eval set нет corrective-кейсов с непустым `required_fix_types`, метрика помечается как `not_applicable` и не участвует в gate.

### `issue_to_action_link_rate`
- доля кейсов, где primary action ссылается хотя бы на один issue из `required_issues`.

### `guardrail_compliance_rate`
- action respect'ит live/pause ограничения:
  - `live` не содержит secondary actions;
  - corrective action не выдается без `linkedIssueIds`;
  - `good` case использует `leave_frame_as_is` или `nil`.

### `good_frame_confirmation_rate`
- доля `good-frame` кейсов, где candidate либо явно подтверждает `leave_frame_as_is`, либо возвращает согласованный no-change path.

## 3. Explanation Faithfulness Metrics

### `trace_issue_coverage_rate`
- каждый required issue имеет хотя бы один `interpretation` trace item с `TraceLink(kind: issue, ...)`.

### `trace_action_coverage_rate`
- для primary action есть `recommendation` trace item с `TraceLink(kind: action, ...)`.

### `three_stage_chain_rate`
- доля кейсов, где для action существует связанная цепочка:
  `observation -> interpretation -> recommendation`.

### `evidence_key_validity_rate`
- все `evidenceKeys` и `EvidenceRef.key` ссылаются на реально существующие поля snapshot/semantics/rule/planner namespace.

### `summary_consistency_rate`
- `CritiqueSummary.shortVerdict`, `whyGood`, `whyProblematic` не противоречат:
  - итоговому `verdict`;
  - списку issues/strengths;
  - `good_frame_policy`.

### `unsupported_claim_rate`
- optional metric для pause-text/refined explanation;
- deterministic checker ищет claims о сцене/объектах, которых нет в:
  - `snapshot.subjectSignals`
  - `semantics.primarySubject.label`
  - `objects.topKLabels`
  - frozen `summary_must_reference_any`

Это не full NLP judge; это safety-метрика против галлюцинаций.

### `explanation_faithfulness_score`

Composite metric для dashboard:

```text
0.25 * trace_issue_coverage_rate
+ 0.20 * trace_action_coverage_rate
+ 0.25 * three_stage_chain_rate
+ 0.15 * evidence_key_validity_rate
+ 0.15 * summary_consistency_rate
```

`unsupported_claim_rate` выводится отдельно как red-flag metric и не прячется внутри composite.

## 4. Live Behavior Metrics

### `hint_visibility_policy_accuracy`
- совпадение `expectedHintState` с candidate presentation state на frame и sequence cases.

### `hint_jitter_rate`
- число изменений primary live hint на sequence / длину sequence.
- changes, затрагивающие кадры с `jitterExempt == true`, не штрафуются.

### `frames_to_stable_correct_hint`
- через сколько кадров после `sequenceMeta.stabilityAnchorFrame` live hint выходит на `sequenceMeta.stablePrimaryAction`.

Для `v1` эти метрики применяются только к `live_sequence` bucket'ам.

## Curated Cinematic Eval Buckets

Минимальный bucket catalog `v1`:

1. `good_clean_single_subject`
- читаемый субъект;
- clean background;
- система должна подтверждать хороший кадр.

2. `edge_pressure_portrait`
- главный субъект прижат к краю;
- ожидается `reframing`.

3. `backlit_face_loss`
- контровой свет скрывает лицо/главный субъект;
- ожидается световой или угловой fix.

4. `dialogue_look_space`
- двухперсонажный или profile-like кадр с дефицитом воздуха по направлению взгляда.

5. `background_competition`
- фон и вторичные объекты спорят за внимание.

6. `object_insert_readability`
- предметный кадр, где важна читаемость объекта, а не portrait heuristics.

7. `establishing_frame_exception`
- кадр может быть насыщенным, но это не всегда ошибка;
- нужен guard against false overload penalties.

8. `moody_backlight_exception`
- backlight художественно допустим;
- eval должен проверять scene-aware сдержанность, а не слепое наказание за backlight.

9. `ambiguous_primary_subject`
- несколько кандидатов близки по confidence;
- ожидается мягкий verdict или fallback.

10. `weak_signal_fallback`
- low scene confidence / moving camera / partial source loss;
- candidate обязан деградировать корректно.

11. `live_motion_suppression`
- во время активного движения hint либо скрыт, либо снижен по уверенности;
- после стабилизации возвращается корректный primary action.

12. `good_frame_do_not_overcoach`
- отдельный критический bucket;
- нужен, чтобы новая система не стала "слишком умной" и навязчивой.

Рекомендуемое распределение:
- не меньше 20% кейсов в `good-frame` bucket'ах;
- не меньше 20% кейсов в `scene-aware exception` bucket'ах;
- не меньше 15% кейсов в `fallback/live suppression`;
- оставшаяся часть покрывает явные failure classes.

## Baseline vs Current Compare Contract

Сравнение должно быть paired и case-aligned.

Минимальный `compare_report.json`:

```json
{
  "compare_id": "camera_analysis_eval_compare_2026_04_20",
  "bundle_id": "camera_analysis_eval_v1_demo",
  "baseline_id": "legacy_suggestion_engine",
  "candidate_id": "camera_analysis_v1_core",
  "overall": {
    "issue_f1": {
      "baseline": 0.58,
      "candidate": 0.79,
      "delta": 0.21
    },
    "primary_action_match_rate": {
      "baseline": 0.41,
      "candidate": 0.83,
      "delta": 0.42
    },
    "explanation_faithfulness_score": {
      "baseline": 0.34,
      "candidate": 0.86,
      "delta": 0.52
    }
  },
  "bucket_wins": {
    "candidate": 0,
    "baseline": 0,
    "tie": 0
  },
  "case_deltas": []
}
```

Правила победы на кейсе:
1. сначала сравнивается `verdict_accuracy`;
2. затем `issue_f1`;
3. затем `primary_action_match_rate`;
4. затем `explanation_faithfulness_score`;
5. если всё одинаково, фиксируется `tie`.

Почему так:
- candidate не должен выигрывать только за счет более красивого summary;
- detection и useful action важнее cosmetic prose.

## Example Markdown Report

Итоговый markdown report обязан иметь 4 читаемые секции:
- `Strengths`
- `Issues`
- `Actions`
- `Explanation Faithfulness`

И плюс блок:
- `Release / Merge Recommendation`

Пример лежит в [example_report.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/example_report.md).

## Release Rules For `v1`

Candidate считается проходящим gate, если одновременно:
- нет деградации по `issue_f1` более чем на `0.03`;
- нет деградации по `primary_action_match_rate` более чем на `0.03`;
- нет деградации по `good_frame_confirmation_rate`;
- `unsupported_claim_rate` не растет;
- есть improvement хотя бы в 2 critical buckets из:
  - `edge_pressure_portrait`
  - `background_competition`
  - `dialogue_look_space`
  - `weak_signal_fallback`
  - `good_frame_do_not_overcoach`

Если optional reasoning layer подключен, он не может считаться улучшением, если:
- вырос `unsupported_claim_rate`;
- ухудшился `summary_consistency_rate`;
- или candidate выигрывает только в prose-like секциях без улучшения actions/issues.

## Implementation Guidance

Рекомендуемая раскладка для implement-этапа:

```text
docs/cameraanalysis/eval/
  run_eval.py
  scorer.py
  compare.py
  io.py
  fixtures/
```

Реализовано в текущем репозитории:
- [run_eval.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/run_eval.py)
- [scorer.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/scorer.py)
- [compare.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/compare.py)
- [adapters.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/adapters.py)
- [eval_io.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/eval_io.py)
- tests: [docs/cameraanalysis/eval/tests](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/tests)

Smoke run:

```text
python3 docs/cameraanalysis/eval/run_eval.py \
  --bundle docs/cameraanalysis/eval \
  --candidate camera_analysis_v1_core \
  --baseline legacy_suggestion_engine \
  --output /tmp/camera_eval_demo_out
```

Минимальные unit tests:
- parsing bundle schema;
- issue/strength/action scoring;
- explanation_faithfulness_score calculation;
- compare winner selection;
- sequence jitter calculation.

## Почему этого достаточно для DoD

`Prompt 8` требует:
- quality metrics;
- golden case format;
- baseline-vs-current compare;
- curated cinematic buckets;
- example report.

Этот документ фиксирует все 5 частей и делает следующий implement-этап детерминированным:
- формат входа уже frozen;
- scoring не зависит только от subjective prose review;
- report schema читается и инженером, и комиссией;
- `explanation faithfulness` измеряется структурно, а не "на глаз".
