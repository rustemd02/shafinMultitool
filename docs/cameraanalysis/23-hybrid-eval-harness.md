# 23. Hybrid Eval Harness (PR-H14)

Статус: design spec + design verify (ready for implement)

Дата: 2026-04-22

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- [10-eval-harness.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/10-eval-harness.md)
- [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)
- [14-hybrid-research-framing.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/14-hybrid-research-framing.md)
- [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md)
- [16-dataset-schema-and-labeling-guide.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/16-dataset-schema-and-labeling-guide.md)
- [17-ava-usage-policy-and-pretraining-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/17-ava-usage-policy-and-pretraining-design.md)
- [18-hybrid-model-architecture-spec.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/18-hybrid-model-architecture-spec.md)
- [19-neural-evidence-domain-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/19-neural-evidence-domain-contract.md)
- [20-on-device-inference-wrapper.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/20-on-device-inference-wrapper.md)
- [21-hybrid-fusion-layer.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/21-hybrid-fusion-layer.md)
- [22-offloading-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/22-offloading-contract.md)
- [run_eval.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/run_eval.py)
- [compare.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/compare.py)
- [scorer.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/scorer.py)

## Цель

Расширить `PR-014` до честного и воспроизводимого `hybrid eval harness`, чтобы можно было:
- сравнивать `deterministic-only`, `local hybrid`, `live hybrid gating` и optional `offloaded` variants на одном frozen bundle;
- измерять hybrid uplift не только по detection/action, но и по explainability agreement и mobile viability;
- прогонять ablations из `PR-H05`, `PR-H09`, `PR-H11` и `PR-H12` без переопределения labels, taxonomy и bundle semantics;
- выпускать thesis/demo-уровневые отчеты, где явно видно, где hybrid полезен, где он безопасно ничего не меняет, и во что это обходится устройству.

Этот документ закрывает design-часть `PR-H14` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md).

## Scope

`PR-H14` отвечает за:
- расширение frozen eval bundle под hybrid fixtures;
- multi-variant orchestration поверх существующего deterministic scorer;
- hybrid-specific metrics;
- ablation compare contract;
- explainability agreement metrics;
- mobile/runtime system metrics;
- markdown/json report template для research, demo и merge-gates.

`PR-H14` не отвечает за:
- новый dataset schema или relabeling policy;
- изменение issue/action taxonomy;
- изменение fusion formulas;
- runtime telemetry collection inside app;
- превращение offloading в обязательный путь;
- единый "cinematic score", который скрывает trade-offs.

## Design Summary

Ключевая формула `PR-H14`:

`same frozen cases -> replay multiple variants -> paired scoring -> explainability/mobile checks -> ablation report`

Из нее следуют обязательные правила:
- `PR-H14` наследует базовые case metrics и compare priorities из [10-eval-harness.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/10-eval-harness.md), а не заменяет их;
- каждый hybrid variant сравнивается на том же bundle, на тех же gold expectations и по тем же core metrics;
- hybrid success никогда не сводится к одному aggregated quality score;
- `deterministic-only` остается anchor baseline для всех hybrid candidate variants;
- explainability и mobile metrics являются release-relevant gates, а не appendix "на потом";
- если neural path skipped, unavailable или disabled, eval обязан уметь доказать safe fallback к deterministic output;
- offloading metrics считаются отдельно от local hybrid, чтобы remote path не маскировал локальные regressions.

## Отношение к `PR-014`

`PR-H14` не форкает старый eval harness, а расширяет его в 3 слоя.

### 1. Reuse from `PR-014`

Без изменений наследуются:
- `golden_cases.jsonl` как base source-of-truth для verdict/issues/actions/explainability expectations;
- core metrics из [scorer.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/scorer.py);
- pairwise compare priorities из [compare.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/compare.py);
- release logic о non-regression по critical deterministic behaviors.

### 2. Hybrid extension

Добавляются:
- variant matrix;
- hybrid case extensions;
- explainability agreement scorer;
- mobile/runtime metric ingestion;
- ablation summary and leaderboard.

### 3. Output principle

Базовый `PR-014` report отвечает на вопрос:

`candidate core better than baseline?`

`PR-H14` обязан отвечать на более широкий набор вопросов:
- где hybrid реально улучшает paused critique;
- где hybrid должен безопасно не вмешаться;
- сохраняется ли traceability при fusion;
- выдерживает ли устройство latency/thermal/memory constraints;
- какой ablation дает лучший Pareto trade-off.

## Variant Matrix Contract

### Canonical variant ids

Каждый запуск `PR-H14` обязан объявлять variants явным списком.

Минимальный implementable baseline для самого `PR-H14` при зависимости только от `PR-H09`:

1. `deterministic_only`
- replay path без `NeuralEvidenceSnapshot`, fusion и offloading.

2. `hybrid_pause_local`
- local neural evidence в `pause`;
- bounded fusion из `PR-H09`;
- `live` работает как deterministic-only.

Optional extension variants, которые разрешены только после появления соответствующих upstream PR:

3. `hybrid_pause_live_local`
- все из `hybrid_pause_local`;
- плюс guarded `live` neural path из `PR-H11`.
- не является required variant для initial implement `PR-H14`.

4. `hybrid_pause_live_offload_structured`
- все из `hybrid_pause_live_local`;
- optional offloading по `structured_only` policy из `PR-H12`.
- не является required variant для initial implement `PR-H14`.

5. `hybrid_pause_live_offload_visual`
- debug/eval-only variant;
- redacted visual tier разрешен только для explicit/deeper-analysis experiments.
- не является required variant для initial implement `PR-H14`.

Нормативные правила:
- любой ablation variant обязан указывать `parentVariantId`;
- все variants обязаны использовать один и тот же eval bundle;
- compare against `deterministic_only` обязателен для каждого hybrid variant;
- compare against `parentVariantId` обязателен для каждого ablation variant;
- `PR-H14` implementation считается complete уже при поддержке `deterministic_only` + `hybrid_pause_local`;
- variants, требующие `PR-H11` или `PR-H12`, могут добавляться позже без переоткрытия core harness contract;
- если variant не поддерживает какой-то mode path, это должно выражаться через deterministic replay или policy skip, а не через удаление кейсов из bundle.

### Recommended ablation groups

`PR-H14` фиксирует 3 canonical family catalogs для всех последующих hybrid runs.

Нормативные правила staged support:
- initial implement `PR-H14` обязан поддержать как минимум те variants/ablations, которые совместимы с зависимостями до `PR-H09`;
- variants, зависящие от `PR-H11` или `PR-H12`, добавляются позже в тот же family catalog без изменения имен и compare rules;
- family catalog фиксируется сейчас именно для того, чтобы future ablations не изобретали новые id и несовместимые report shapes.

1. `model_architecture`
- `A0_deterministic_only`
- `A1_full_frame_only`
- `A2_no_mode_flag`
- `A3_no_ava_warm_start`
- `A4_relaxed_applicability`
- `A5_score_only_no_confidence_heads`
- `A6_no_supporting_signal_supervision`
- `A7_width_050`
- `A7_width_075`
- `A7_width_100`

2. `runtime_policy`
- `R0_pause_only`
- `R1_pause_plus_live`
- `R2_pause_plus_live_degraded`
- `R3_offload_structured_only`
- `R4_offload_redacted_visual`

3. `fusion_behavior`
- `F0_no_fusion`
- `F1_fusion_full_policy`
- `F2_fusion_without_contextual_heads`
- `F3_fusion_without_trace_materialization`

Нормативное ограничение:
- `F3` разрешен только как debug ablation to prove explainability cost; он не может считаться shipping candidate.

## Eval Bundle Extension

`PR-H14` использует тот же bundle directory, что и `PR-014`, но расширяет manifest и case schema.

### Manifest extension

Минимальное расширение `eval_bundle_manifest.json`:

```json
{
  "bundle_id": "camera_analysis_hybrid_eval_v1",
  "bundle_profile": "hybrid_v1",
  "gold_schema_version": "hybrid_eval_v1",
  "critical_buckets": [
    "edge_pressure_portrait",
    "background_competition",
    "dialogue_look_space",
    "weak_signal_fallback",
    "good_frame_do_not_overcoach"
  ],
  "hybrid_critical_buckets": [
    "ambiguity_borderline",
    "style_vs_failure_conflict",
    "pause_neural_value",
    "live_guarded_value",
    "hybrid_degraded_fallback"
  ]
}
```

Нормативные правила для hybrid bucket projection:
- canonical deterministic `bucket_tags` из `PR-014` сохраняются как есть;
- `hybrid_critical_buckets` не дублируются вручную в каждом case, а materialize-ятся scorer-ом из `hybrid_eval` metadata по fixed rules ниже;
- один case может входить сразу в несколько hybrid buckets.

### Case extension

Каждый golden case может иметь optional `hybrid_eval` block:

```text
hybrid_eval
- ambiguityBucket: clear | borderline | hard_ambiguous
- conflictBucket: none | style_vs_failure | weak_signal | neural_vs_rule
- expectedGainMode: none | pause_only | pause_and_live
- expectedEligibleHeadIds: [EvidenceHeadId]
- forbiddenAppliedHeadIds: [EvidenceHeadId]
- expectedFusionBehavior: noop | reinforce | soften | mixed
- offloadTierAllowed: none | structured_only | redacted_visual
- visualReplayRef: String?
- visualReplayTrigger: explicit_user_request?
- mobilitySensitivity: low | medium | high
```

Смысл полей:
- `ambiguityBucket` нужен для calibration-heavy cases, где hybrid thesis должен приносить основной выигрыш;
- `conflictBucket` фиксирует тип конфликта, а не "правильный winner";
- `expectedEligibleHeadIds` проверяет, что `PR-H09/H11` использует только допустимые heads;
- `forbiddenAppliedHeadIds` защищает от accidental policy drift;
- `expectedFusionBehavior` не диктует exact delta, но задает expected effective fusion direction for agreement scoring;
- `offloadTierAllowed` помогает отдельно считать `structured_only` и `redacted_visual` paths;
- `visualReplayRef` указывает на заранее подготовленный redacted visual artifact для future offload replay;
- `visualReplayTrigger` фиксирует legal trigger для `redacted_visual` replay и в baseline должен быть только `explicit_user_request`;
- `mobilitySensitivity` маркирует кейсы, где high-cost path легко ломает thesis.

Нормативное правило:
- отсутствие `hybrid_eval` блока означает ordinary deterministic-compatible case; такой case все равно участвует во всех variants.
- если `offloadTierAllowed == redacted_visual`, case обязан содержать и `visualReplayRef`, и `visualReplayTrigger == explicit_user_request`;
- если redacted visual requirements не выполнены, visual offload variant обязан materialize-иться как `blocked`, а не invent-ить payload.
- `expectedFusionBehavior` и `forbiddenAppliedHeadIds` не являются decorative metadata: scorer обязан учитывать их в explicit agreement metrics ниже;
- scorer обязан hard-fail run validation, если case содержит эти поля, а implementation path их silently игнорирует.

### Eligibility rules for coverage metrics

Чтобы `eligible_head_availability_rate` и `case_neural_coverage_rate` были воспроизводимыми, `PR-H14` фиксирует один canonical source-of-truth для eligibility.

`policyEligibleHeadIds(caseMode)`:
- для `pause`: все heads, разрешенные `PR-H09` для pause decision/eval path, кроме purely eval/debug-neutral paths, если они явно excluded below;
- для `live`: только heads, разрешенные `PR-H09/H11` для guarded live path.

Для `v1` canonical policy sets:
- `pause`
  - `subject_prominence`
  - `background_clutter`
  - `lighting_quality`
  - `face_saliency`
  - `balance_confidence`
  - `depth_separation`
  - `shot_type_confidence`
- `live`
  - `subject_prominence`
  - `background_clutter`
  - `lighting_quality`
  - `face_saliency`

`semanticApplicability(case, headId)`:
- `face_saliency`
  - applicable only if `SceneSemanticsReport.primarySubject.kind in {face, person, group}` is available for the case/frame;
  - `not_applicable` if `primarySubject.kind in {object, unknown}`;
  - `unavailable` if semantics input required for this decision is missing or invalid.
- pause-only heads in `live`
  - always `not_applicable`.
- all other heads
  - applicable unless an already-frozen upstream policy marks them `not_applicable`.

`degradedApplicability(case, headId, executionProfile)`:
- for normal execution: same as semantic applicability;
- for `degraded_pause_profile`:
  - only heads that remain active under degraded pause profile count as eligible coverage targets;
  - if degraded profile disables a head from active fusion/eval path, that head becomes `coverage_not_applicable` for this execution and must not penalize coverage metrics.

Нормативные правила:
- `cinematic_expressiveness` не входит в coverage denominators, потому что в `PR-H09` остается debug/eval-only observation и не участвует в bounded decision path;
- базовый effective eligible set считается как:
  - `policyEligibleHeadIds(caseMode)`
  - intersect `semanticApplicability(case, headId) == applicable`
  - intersect `degradedApplicability(case, headId, executionProfile) == applicable`, если execution profile materialized for this case/frame;
- если case содержит `hybrid_eval.expectedEligibleHeadIds`, effective eligible set дополнительно сужается через `intersection(..., expectedEligibleHeadIds)`;
- если `hybrid_eval.expectedEligibleHeadIds` отсутствует или пуст, extra narrowing не применяется;
- `expectedEligibleHeadIds` не может расширять policy set, только сужать его;
- если intersection пуст, case считается `coverage_not_applicable` и не входит в denominator coverage metrics;
- ordinary cases без `hybrid_eval` блока используют canonical policy + semantic/degraded applicability rules без guesswork;
- scorer не имеет права штрафовать case за head со status `not_applicable`, если этот status является correct output according to frozen applicability rules.

### Hybrid bucket derivation rules

Чтобы release gate "improvement хотя бы в 2 hybrid-critical buckets" был implement-ready, `PR-H14` фиксирует явное отображение `hybrid_eval -> hybrid_critical_buckets`:

- `ambiguity_borderline`
  materialize-ится, если `ambiguityBucket in {borderline, hard_ambiguous}`

- `style_vs_failure_conflict`
  materialize-ится, если `conflictBucket == style_vs_failure`

- `pause_neural_value`
  materialize-ится, если `expectedGainMode in {pause_only, pause_and_live}`

- `live_guarded_value`
  materialize-ится, если `expectedGainMode == pause_and_live`

- `hybrid_degraded_fallback`
  materialize-ится, если `conflictBucket == weak_signal` или deterministic `bucket_tags` уже содержат `weak_signal_fallback`

Нормативное ограничение:
- scorer не имеет права угадывать дополнительные hybrid buckets вне этих правил;
- если case не попал ни в один hybrid bucket, он все равно участвует в overall compare, но не в hybrid-critical bucket gate.

## Candidate Output Contract

Чтобы scorer мог повторяемо считать hybrid metrics, candidate output для `PR-H14` должен materialize-ить normal form поверх существующего output envelope.

Для single-frame `pause` и `single_frame_live` cases минимальный `HybridEvalProjection`:

```text
HybridEvalProjection
- evalCaseId: String
- mode: AnalysisMode
- deterministicOutput: EvalOutputEnvelope
- finalOutput: EvalOutputEnvelope            // final scoreable output for this variant
- localPhaseOutput: EvalOutputEnvelope       // always the local-first output before offloading
- augmentedOutput: EvalOutputEnvelope?       // optional advisory-applied output after validated offload
- inferenceOutcome: HybridInferenceEvalOutcome?
- neuralSnapshot: NeuralEvidenceSnapshot?
- neuralMetadata: NeuralEvidenceRuntimeMetadata?
- fusionDecisions: [HybridFusionDecision]
- offloadOutcome: HybridOffloadEvalOutcome?
```

```text
HybridInferenceEvalOutcome
- status: disabled | executed | policySkipped | failed
- mode: AnalysisMode
- hasSnapshot: Bool
- failureReason: NeuralEvidenceFailureReason?

HybridOffloadEvalOutcome
- status: disabled | notTriggered | blocked | completed | failed
- tier: none | structured_only | redacted_visual
- trigger: none | explicit_user_request | ambiguous_local_case | fusion_disagreement_probe | partial_local_failure | eval_sampling
- failureKind: none | timeout | transport_error | policy_refused | capability_mismatch | validation_failed | unknown
- responseApplied: Bool
- boundarySafe: Bool
- localFirstPublished: Bool
```

Нормативные правила:
- `deterministicOutput` и `finalOutput` обязаны быть scoreable тем же deterministic scorer-ом, что и `PR-014`;
- `localPhaseOutput` обязателен для всех variants и должен быть byte-equivalent local result-у до offloading;
- если `offloadOutcome.status != completed`, `finalOutput` обязан быть score-equivalent `localPhaseOutput`;
- если `offloadOutcome.status == completed` и advisory не был applied, `finalOutput` обязан оставаться score-equivalent `localPhaseOutput`;
- `augmentedOutput` разрешен только для `offloadOutcome.status == completed`;
- `finalOutput` не может быть ambiguous смешением local baseline и not-yet-applied remote advisory;
- если neural path не использовался, `fusionDecisions == []`;
- если local hybrid skipped/failed, `finalOutput` обязан оставаться score-equivalent deterministic path-у;
- `inferenceOutcome` обязателен для every local hybrid path and must preserve `PR-H07` outcome semantics;
- `offloadOutcome` не может присутствовать для variants без offloading;
- `offloadOutcome.status` обязан сохранять canonical `PR-H12` outcome semantics и не может collapse-иться в plain Bool flags;
- `boundarySafe == false` автоматически проваливает explainability/contract gate.

### Sequence extension for `live_sequence`

Так как `PR-014` уже имеет contract для `live_sequence`, `PR-H14` обязан фиксировать per-frame hybrid sidecars и не может полагаться на один case-level `neuralSnapshot`.

Минимальный `HybridEvalSequenceProjection`:

```text
HybridEvalSequenceProjection
- evalCaseId: String
- mode: live
- deterministicOutput: EvalOutputEnvelope
- finalOutput: EvalOutputEnvelope
- frameArtifacts: [HybridEvalFrameArtifact]
```

```text
HybridEvalFrameArtifact
- frameOrdinal: Int
- inferenceOutcome: HybridInferenceEvalOutcome?
- neuralSnapshot: NeuralEvidenceSnapshot?
- neuralMetadata: NeuralEvidenceRuntimeMetadata?
- fusionDecisions: [HybridFusionDecision]
- traceItems: [ExplainabilityTraceItem]?      // optional per-frame trace sidecar for live explainability checks
- staleDropped: Bool
- runtimeSample: HybridRuntimeSample?
```

Нормативные правила:
- `frameArtifacts.count` обязан совпадать с количеством фактически materialized `frame_outputs`, а не обязательно с длиной source sequence;
- для `live_sequence` metrics `live_policy_skip_rate`, `critical_thermal_skip_rate`, `stale_result_drop_rate` и любые per-frame explainability checks считаются только по `frameArtifacts`;
- отсутствие `frameArtifacts` для `live`-capable variant делает run contract-invalid;
- для pause-only variants `live_sequence` может по-прежнему replay-иться deterministic path-ом без `frameArtifacts`, но такой variant не имеет права репортить `live` hybrid metrics как будто путь был реализован.

### Runtime sample sidecar

Чтобы mobile gates не зависели от ad-hoc ingestion, `PR-H14` фиксирует минимальный sidecar shape для single-frame и sequence artifacts:

```text
HybridRuntimeSample
- variantId: String
- evalCaseId: String
- frameOrdinal: Int?                       // nil for single-frame pause cases
- mode: AnalysisMode
- executionProfile: normal | degraded_pause_profile | unknown
- thermalTier: unrestricted | constrained | critical | unknown
- peakMemoryMB: Double?
- staleDropped: Bool
- inferenceLatencyMs: Int?
```

Нормативные правила:
- `variantId + evalCaseId + frameOrdinal?` являются join key для runtime/mobile aggregation;
- `executionProfile` описывает policy-level runtime profile, а не inferred implementation detail:
  - `normal` = обычный execution path без explicit degraded policy;
  - `degraded_pause_profile` = explicit degraded path из `PR-H07`, даже если ROI strategy совпала бы с обычным `full_frame_only`;
  - `unknown` допустим только для variants/path-ов, где runtime sample отсутствует и related metric становится `n/a`;
- `peakMemoryMB` считается sample-level peak, а `peak_memory_p95_mb` агрегируется поверх всех samples variant-а;
- `staleDropped` обязан дублироваться и в frame artifact, и в runtime sample для stable aggregation;
- если runtime sample отсутствует, scorer может считать только те mobile metrics, которые выводятся напрямую из `NeuralEvidenceRuntimeMetadata`;
- shipping/mobile gates не имеют права требовать metric, для которой нет source-of-truth field в `HybridRuntimeSample` или `NeuralEvidenceRuntimeMetadata`.

## Runner Contract

Для implement-этапа рекомендуется ввести новый orchestration layer, не ломая базовый `run_eval.py`:

```text
python3 docs/cameraanalysis/eval/run_hybrid_eval.py \
  --bundle <eval_bundle_dir> \
  --matrix <variant_matrix.json> \
  --output <report_dir>
```

Рекомендуемая стратегия:
- `run_eval.py` остается pairwise scorer-ом для одного baseline/candidate compare;
- `run_hybrid_eval.py` генерирует outputs для каждого variant;
- затем вызывает shared scorer/compare для:
  - `deterministic_only` vs каждый hybrid variant;
  - `parentVariantId` vs child ablation variant;
- собирает общие hybrid reports.

Минимальные output artifacts:
- `variant_outputs/<variantId>.jsonl`
- `pairwise_compare/<baseline>__vs__<candidate>.json`
- `pairwise_summary/<baseline>__vs__<candidate>.md`
- `hybrid_metrics.json`
- `explainability_agreement.json`
- `mobile_system_metrics.json`
- `ablation_summary.json`
- `hybrid_eval_summary.md`

Нормативные правила для `variant_outputs/<variantId>.jsonl`:
- каждая строка обязана иметь discriminator `projectionKind`;
- допустимые значения:
  - `single_frame`
  - `live_sequence`
- `projectionKind == single_frame` сериализуется по `HybridEvalProjection`;
- `projectionKind == live_sequence` сериализуется по `HybridEvalSequenceProjection`;
- runner не может silently смешивать разные shape без discriminator field.

## Metric Families

## 1. Core Non-Regression Metrics

Для каждого variant без изменений считаются metrics из `PR-014`:
- `issue_f1`
- `strength_f1`
- `primary_action_match_rate`
- `good_frame_confirmation_rate`
- `fallback_policy_accuracy`
- `hint_visibility_policy_accuracy`
- `hint_jitter_rate`
- `explanation_faithfulness_score`
- и остальные metrics из [scorer.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/eval/scorer.py)

Причина:
- hybrid stage не имеет права объявлять "улучшение", если базовые product behaviors деградировали.

## 2. Hybrid Utility Metrics

Эта группа отвечает на вопрос:

`дал ли neural layer полезный вклад и остался ли bounded?`

### `safe_noop_rate`

Доля кейсов, где hybrid path был disabled/skipped/unavailable, и `finalOutput` остался score-equivalent `deterministicOutput`.

Формула:

```text
safe_noop_rate =
  noop_cases_without_score_drift / all_cases_with_no_effective_neural_path
```

Ожидаемое baseline значение:
- `1.0`

### `eligible_head_availability_rate`

Доля eligible head slots, которые materialize-ились как `available`.

Формула:

```text
eligible_head_availability_rate =
  available_eligible_head_slots / all_eligible_head_slots
```

Эта метрика нужна отдельно от runtime failures:
- low availability может значить bad model/runtime fit even without visible product regression.

Нормативное правило:
- `eligible head` всегда считается по canonical eligibility rules above и не может вычисляться из ad-hoc fusion usage.

### `case_neural_coverage_rate`

Доля hybrid-eligible кейсов, где есть хотя бы один eligible `available` head.

Нормативные правила:
- `hybrid-eligible case` означает case, для которого effective eligible set не пуст;
- если case помечен `coverage_not_applicable`, он не входит в denominator;
- наличие `available`, но policy-ineligible head не влияет на эту метрику.

### `applied_fusion_rate`

Доля кейсов с хотя бы одним `HybridFusionDecision.outcome in {reinforced, softened}` и `abs(delta) >= 0.03`.

### `pause_uplift_win_rate`

Доля `pause` cases, где hybrid variant выигрывает у `deterministic_only` по priority order из `PR-014`.

Считать отдельно по buckets:
- `ambiguity_borderline`
- `style_vs_failure_conflict`
- `pause_neural_value`

### `live_guarded_win_rate`

Доля `live` cases, где `hybrid_pause_live_local` или его потомок выигрывает у `deterministic_only` без роста:
- `hint_jitter_rate`
- `unsupported_claim_rate`

Case-level winner для `live_guarded_value` фиксируется по live-specific priority order:
- выше `hint_visibility_policy_accuracy`;
- затем ниже `frames_to_stable_correct_hint`;
- затем ниже `hint_jitter_rate`;
- затем ниже `unsupported_claim_rate`.

### `hybrid_degraded_fallback_case_pass_rate`

Case-level metric for cases inside `hybrid_degraded_fallback`.

Case-level `degraded_fallback_pass(case)` equals `1.0`, if simultaneously:
- degraded/failed path preserved deterministic-safe behavior for this case;
- no hidden crash state occurred;
- final output remained contract-safe and scoreable;
- degraded path did not violate `fallback_policy_accuracy` for this case.

Otherwise:
- `0.0`

Нормативные правила:
- this is the only canonical case-level degraded fallback predicate;
- scorer must not infer a different case-level degraded verdict from set-level aggregates.

### `hybrid_degraded_fallback_score`

Set-level aggregate for dashboard and gate summary.

Формула:

```text
hybrid_degraded_fallback_score =
  mean(degraded_fallback_pass(case) for all cases in hybrid_degraded_fallback)
```

Нормативное правило:
- эта метрика используется как set-level gate/dashboard metric и не подменяет case-level predicate.

### `hybrid_degraded_fallback_win_rate`

Bucket-level compare metric для cases, попавших в `hybrid_degraded_fallback`.

Case считается win для candidate variant, если одновременно:
- `degraded_fallback_pass(case) == 1.0`;
- нет деградации по `fallback_policy_accuracy`;
- нет деградации по priority order `verdict_accuracy -> issue_f1 -> primary_action_match_rate -> explanation_faithfulness_score`.

Эта метрика нужна, чтобы `hybrid_degraded_fallback` мог участвовать в release gate как настоящий compare bucket, а не как глобальный Boolean.

## 3. Explainability Agreement Metrics

Эта группа отвечает на вопрос:

`совпадает ли фактическое hybrid влияние с замороженными contracts?`

### `fusion_trace_coverage_rate`

Для каждого applied fusion decision проверяется:
- есть observation trace item с `neural.<headId>.*` key;
- есть interpretation item, который связывает deterministic finding и bounded neural calibration;
- recommendation stage не ссылается напрямую на raw neural verdict semantics.

Формула:

```text
fusion_trace_coverage_rate =
  applied_fusion_decisions_with_complete_trace / all_applied_fusion_decisions
```

### `head_policy_agreement_rate`

Все реально использованные `appliedHeadIds` должны одновременно:
- быть разрешены policy для current mode;
- иметь `status == available`;
- соответствовать allowed finding mapping из [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md) и [21-hybrid-fusion-layer.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/21-hybrid-fusion-layer.md).

### `forbidden_head_violation_rate`

Доля applicable cases, где effective fusion использовал хотя бы один head из `hybrid_eval.forbiddenAppliedHeadIds`.

Effective fusion decision:
- `HybridFusionDecision.outcome in {reinforced, softened}`
- `abs(delta) >= 0.03`

Формула:

```text
forbidden_head_violation_rate =
  applicable_cases_with_forbidden_applied_head / all_cases_with_forbiddenAppliedHeadIds
```

Нормативные правила:
- если `forbiddenAppliedHeadIds` отсутствует или пуст, case не входит в denominator;
- case считается violation, если любой effective fusion decision имеет `appliedHeadIds ∩ forbiddenAppliedHeadIds != ∅`;
- `forbidden_head_violation_rate` обязан быть `0.0` для shipping-grade variant.

### `fusion_expectation_agreement_rate`

Доля applicable cases, где realized effective fusion behavior совпал с `hybrid_eval.expectedFusionBehavior`.

`realizedEffectiveFusionBehavior(case)` определяется так:
- `noop`
  - нет effective fusion decisions
- `reinforce`
  - есть хотя бы один effective decision c `outcome == reinforced`
  - и нет effective decisions c `outcome == softened`
- `soften`
  - есть хотя бы один effective decision c `outcome == softened`
  - и нет effective decisions c `outcome == reinforced`
- `mixed`
  - есть хотя бы один effective `reinforced`
  - и хотя бы один effective `softened`

Формула:

```text
fusion_expectation_agreement_rate =
  applicable_cases_with_matching_realized_behavior / all_cases_with_expectedFusionBehavior
```

Нормативные правила:
- если `expectedFusionBehavior` отсутствует, case не входит в denominator;
- `ignored` и `unchanged` decisions не влияют на `realizedEffectiveFusionBehavior`;
- scorer не может подменять `noop` low-delta drift-ом: только effective decisions участвуют в classification;
- для shipping-grade variant expectation agreement должен быть release-relevant, а не appendix metric.

### `status_trace_consistency_rate`

Trace не имеет права ссылаться на unavailable/not_applicable head как на использованный evidence source.

### `supporting_signal_contract_rate`

Для available scalar heads проверяется:
- supporting tags входят в allow-list;
- cardinality `0...2`;
- canonical order сохранен;
- `shot_type_confidence` всегда имеет `[]`.

### `offload_boundary_compliance_rate`

Для variants с offloading:
- advisory layer не мутирует frozen taxonomy;
- remote path не переписывает baseline verdict source-of-truth;
- `structured_only` и `redacted_visual` репортятся раздельно;
- `boundarySafe == true`.

Нормативное правило:
- если offloading path вообще используется в report, эта метрика обязательна и release-relevant.

## 4. Mobile System Metrics

Эта группа отвечает на вопрос:

`не ломает ли neural path mobile-first thesis?`

Источник данных:
- `NeuralEvidenceRuntimeMetadata`
- `HybridRuntimeSample`
- optional device benchmark samples, нормализованные к тому же `HybridRuntimeSample` shape

Обязательные metrics зависят от типа variant-а:
- для любого variant-а обязательны only metrics того runtime path, который variant реально реализует;
- для pause-only local hybrid variant обязательны `pause_*` metrics и optional summary of deterministic `live_sequence` behavior;
- `live_*` metrics становятся release-relevant только для variants, которые действительно включают `PR-H11` live path;
- offloading metrics становятся release-relevant только для variants, которые действительно включают `PR-H12`.

Обязательные metrics:

### `live_policy_skip_rate`

Доля live requests, завершившихся `policySkipped`.

Интерпретация:
- слишком низкое значение подозрительно и может означать unsafe over-execution;
- слишком высокое значение означает, что live hybrid почти не приносит пользы.

### `live_latency_p50_ms` / `live_latency_p95_ms`

Считаются только по реально начатым `live` execution.

Target from `PR-H05`:
- `p50 <= 18`
- `p95 <= 28`

### `pause_latency_p50_ms` / `pause_latency_p95_ms`

Target from `PR-H05`:
- `p50 <= 30`
- `p95 <= 45`

### `pause_execute_success_rate`

Доля explicit pause requests, завершившихся валидным executed snapshot.

### `pause_degraded_execution_rate`

Доля pause executions, которые прошли через degraded profile, но остались valid.

Формула:

```text
pause_degraded_execution_rate =
  pause_samples_with_executionProfile_degraded_pause_profile / all_valid_pause_execution_samples
```

Нормативные правила:
- метрика считается только по `HybridRuntimeSample.executionProfile`;
- ROI strategy, отсутствие crop branch или `full_frame_only` сами по себе не могут считаться degraded profile;
- если `executionProfile` не materialized for a path, метрика должна быть `n/a`, а не inferred post-hoc.

### `pause_failure_rate`

Доля pause requests, завершившихся hard-failure snapshot.

### `peak_memory_p95_mb`

Target from `PR-H05`:
- preferred `<= 90`
- hard ceiling `<= 140`

### `critical_thermal_skip_rate`

Доля live requests, корректно soft-disabled из-за `thermalTier == .critical`.

### `stale_result_drop_rate`

Доля результатов, которые были вычислены, но отброшены как устаревшие для текущего `frameId`.

Нормативное правило:
- metric может быть `n/a` только если конкретный variant не реализует соответствующий path;
- `n/a` по `live_*` metrics допустим для `hybrid_pause_local`;
- `n/a` по offloading metrics допустим для всех variants без `PR-H12` path.

## Compare Contract

### Pairwise winner rules

На уровне case и bucket сохраняется priority order из `PR-014`:
1. `verdict_accuracy`
2. `issue_f1`
3. `primary_action_match_rate`
4. `explanation_faithfulness_score`

Hybrid-specific metrics не подменяют этот порядок, а идут отдельным слоем verdict explanation.

### Hybrid report verdict categories

Для каждого variant должен materialize-иться один из verdict-ов:
- `ship_candidate`
- `research_only`
- `regression_blocked`
- `mobile_blocked`
- `explainability_blocked`
- `no_meaningful_gain`

Смысл:
- `ship_candidate`: проходит non-regression, explainability и mobile gates и дает measurable uplift;
- `research_only`: есть интересные gains, но еще не пройдены shipping gates;
- `regression_blocked`: variant показал regression или safe-fallback drift и не может маскироваться как neutral/no-gain result;
- `mobile_blocked`: gains есть, но нарушены latency/memory/thermal limits;
- `explainability_blocked`: gains есть, но нарушен contract-safe trace/agreement;
- `no_meaningful_gain`: regressions нет, но measurable value не показана.

## Release Rules For Hybrid Variants

### Gate A. Pause-only local hybrid

Pause-only local hybrid variant (`hybrid_pause_local`) считается проходящим gate, если одновременно:
- нет деградации по `issue_f1` более чем на `0.03` относительно `deterministic_only`;
- нет деградации по `primary_action_match_rate` более чем на `0.03`;
- `good_frame_confirmation_rate` не ухудшается;
- `unsupported_claim_rate` не растет;
- `safe_noop_rate == 1.0`;
- `fusion_trace_coverage_rate >= 0.95`;
- `head_policy_agreement_rate == 1.0`;
- если есть applicable denominator по `forbiddenAppliedHeadIds`, `forbidden_head_violation_rate == 0.0`;
- если есть applicable denominator по `expectedFusionBehavior`, `fusion_expectation_agreement_rate >= 0.95`;
- `status_trace_consistency_rate == 1.0`;
- `pause_execute_success_rate >= 0.90`;
- `pause_failure_rate <= 0.10`;
- если в bundle есть хотя бы один degraded pause sample, `pause_degraded_execution_rate > 0.0`;
- `pause_latency_p95_ms` не выходит за targets из `PR-H05`;
- `peak_memory_p95_mb <= 140`;
- есть improvement хотя бы в 2 hybrid-critical buckets из:
  - `ambiguity_borderline`
  - `style_vs_failure_conflict`
  - `pause_neural_value`
  - `hybrid_degraded_fallback`, measured via `hybrid_degraded_fallback_win_rate`

Нормативные правила для Gate A:
- explicit pause path не может считаться shipping-grade, если reliable execution происходит реже чем в `90%` sampled pause cases;
- hard failures выше `10%` automatically block `ship_candidate`;
- если bundle специально содержит degraded pause coverage, candidate обязан показать хотя бы некоторую successful degraded execution path instead of always failing or bypassing it;
- если bundle не содержит degraded pause samples, `pause_degraded_execution_rate` может быть `n/a` и не блокирует Gate A by itself.

### Gate B. Full local hybrid with live path

Variant с `PR-H11` live path дополнительно должен пройти:
- `live_latency_p95_ms` не выходит за targets из `PR-H05`;
- `live_policy_skip_rate` обязан лежать в диапазоне `0.25 ... 0.95`;
- `critical_thermal_skip_rate == 1.0` на critical-thermal live samples;
- improvement в `live_guarded_value` bucket считается только для таких variants.

Нормативные правила для Gate B:
- нижняя граница `0.25` фиксирует, что live path остается guarded и не превращается в always-on inference loop;
- верхняя граница `0.95` фиксирует, что live path не деградировал в practically never-run mode;
- если в bundle нет ни одного critical-thermal live sample, `critical_thermal_skip_rate` помечается `n/a` и Gate B не может дать `ship_candidate`; максимум `research_only` until thermal coverage appears;
- если bundle содержит менее `10` live samples for a live-capable variant, Gate B не считается release-conclusive и variant не может получить `ship_candidate`.

Для offloading variants дополнительно:
- `offload_boundary_compliance_rate == 1.0`;
- uplift и disagreement считаются отдельно для `structured_only` и `redacted_visual`;
- итоговый report обязан materialize-ить explicit per-tier split, а не только generic offload aggregate;
- offloading не может быть единственной причиной, почему variant побеждает local hybrid baseline.

## Report Template

Итоговый markdown report обязан иметь минимум 7 секций:
- `Executive Summary`
- `Core Non-Regression`
- `Hybrid Utility`
- `Explainability Agreement`
- `Mobile Viability`
- `Ablation Highlights`
- `Representative Cases`

И блок:
- `Release Recommendation`

Если в run есть offloading variants, дополнительно materialize-ится секция:
- `Offload Tier Split`

Минимальный skeleton:

```text
# Hybrid Eval Summary

Run
- bundle: `camera_analysis_hybrid_eval_v1`
- anchor: `deterministic_only`
- best local variant: `hybrid_pause_local`

## Executive Summary
- local hybrid improved `pause_uplift_win_rate` on ambiguity buckets without core regressions
- where implemented, live gains remained bounded and did not increase hint jitter
- offloading variants stayed advisory-only but are not required for local shipping value

## Core Non-Regression
- `issue_f1`: `0.79 -> 0.82`
- `primary_action_match_rate`: `0.83 -> 0.85`
- `good_frame_confirmation_rate`: `0.92 -> 0.92`

## Hybrid Utility
- `safe_noop_rate`: `1.00`
- `case_neural_coverage_rate`: `0.68`
- `applied_fusion_rate`: `0.41`
- `ambiguity_borderline` win rate: `0.73`

## Explainability Agreement
- `fusion_trace_coverage_rate`: `0.98`
- `head_policy_agreement_rate`: `1.00`
- `status_trace_consistency_rate`: `1.00`

## Mobile Viability
- `live_latency_p95_ms`: `24` or `n/a` for pause-only variant
- `pause_latency_p95_ms`: `39`
- `peak_memory_p95_mb`: `88`

## Ablation Highlights
- `A1_full_frame_only` loses on `pause_uplift_win_rate`
- `A5_score_only_no_confidence_heads` regresses explainability and safety gates
- `R3_offload_structured_only` improves conflict resolution but remains research-only

## Representative Cases
- `case_012`: hybrid softened false backlight critique in moody portrait
- `case_041`: low-confidence live evidence correctly ignored
- `case_067`: degraded pause path preserved deterministic result under critical thermal

## Release Recommendation
- verdict: `ship_candidate`
- because: non-regression passed, ambiguity buckets improved, mobile targets preserved
```

## Implementation Guidance

Рекомендуемая раскладка для implement-этапа:

```text
docs/cameraanalysis/eval/
  run_eval.py
  run_hybrid_eval.py
  scorer.py
  scorer_hybrid.py
  compare.py
  compare_hybrid.py
  variant_matrix.example.json
  example_hybrid_report.md
```

Рекомендуемые шаги реализации:
1. переиспользовать current deterministic scorer как base metric engine;
2. ввести normalized `HybridEvalProjection`;
3. добавить scorer для hybrid agreement/mobile metrics;
4. добавить multi-variant orchestrator;
5. отрендерить pairwise и ablation reports без изменения существующего deterministic CLI.

## Test Matrix

`PR-H14` должен иметь минимум следующие tests.

1. Pairwise parity test
Проверяет, что `deterministic_only` через hybrid runner дает те же core metrics, что и existing `run_eval.py`.

2. Safe noop equivalence test
Проверяет, что skipped/disabled/unavailable hybrid path не меняет финальный scoreable output.

3. Eligible head policy test
Проверяет, что `head_policy_agreement_rate` падает при использовании head-а вне mode/mapping policy.

4. Trace agreement test
Проверяет, что applied fusion without complete observation+interpretation trace penalizes `fusion_trace_coverage_rate`.

5. Supporting signal contract test
Проверяет cardinality/order/mask invariants для supporting tags.

6. Mobile metric ingestion test
Проверяет корректный подсчет latency/skip/failure metrics по runtime sidecars.

7. Ablation parent compare test
Проверяет, что каждый ablation variant сравнивается и с `deterministic_only`, и со своим `parentVariantId`.

8. Offloading tier split test
Проверяет, что `structured_only` и `redacted_visual` отчеты считаются и репортятся отдельно.

9. Report rendering test
Проверяет наличие обязательных секций и verdict category в markdown report.

10. Release gate test
Проверяет, что нарушение `safe_noop_rate`, `head_policy_agreement_rate` или mobile targets приводит к blocked verdict.

## Что это разблокирует дальше

После фиксации этого документа:
- `PR-H14 implement` может расширить existing eval scripts без скрытых product assumptions;
- `PR-H15` может логировать disagreements и hard cases в format, совместимый с hybrid reports;
- `PR-H16` может собрать committee-ready before/after narrative на тех же paired artifacts;
- команда получает repeatable answer не только на вопрос "лучше ли стало", но и на вопросы "где именно", "почему" и "какой ценой".

## Design Verify (2026-04-22)

Источник независимой проверки:
- reviewer subagent по Prompt 18 (`design verify`)
- локальный cross-check против [10-eval-harness.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/10-eval-harness.md), [14-hybrid-research-framing.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/14-hybrid-research-framing.md), [19-neural-evidence-domain-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/19-neural-evidence-domain-contract.md), [20-on-device-inference-wrapper.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/20-on-device-inference-wrapper.md), [21-hybrid-fusion-layer.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/21-hybrid-fusion-layer.md) и [22-offloading-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/22-offloading-contract.md)

Закрытые замечания:
- устранён scope-conflict с backlog dependency `PR-H09`: initial required baseline сужен до `deterministic_only` + `hybrid_pause_local`, а `PR-H11/H12` variants переведены в explicit staged extensions;
- устранён replay gap для `redacted_visual`: добавлены `visualReplayRef` и `visualReplayTrigger`, а при их отсутствии visual path обязан materialize-иться как `blocked`;
- устранён artifact gap для runtime/offload outcomes: добавлены `HybridInferenceEvalOutcome`, `HybridOffloadEvalOutcome`, `localPhaseOutput` и `augmentedOutput`;
- устранён live-sequence gap: добавлены `HybridEvalSequenceProjection`, `HybridEvalFrameArtifact` и правила для per-frame hybrid sidecars;
- устранён bucket-compare gap: добавлена `hybrid_degraded_fallback_win_rate`;
- устранён mobile-sidecar gap: зафиксирован `HybridRuntimeSample` и join/aggregation contract;
- устранена неоднозначность хранения projection shape: `variant_outputs/<variantId>.jsonl` теперь обязан иметь `projectionKind`.
- устранён gap case-level fusion expectations: `expectedFusionBehavior` и `forbiddenAppliedHeadIds` теперь обязаны участвовать в `fusion_expectation_agreement_rate` и `forbidden_head_violation_rate`;
- устранён gap live Gate B thresholds: `live_policy_skip_rate` и `critical_thermal_skip_rate` теперь имеют canonical pass/fail rules.
- устранён gap Gate A pause reliability: `pause_execute_success_rate`, `pause_failure_rate` и `pause_degraded_execution_rate` теперь участвуют в release gate;
- устранён gap coverage applicability: effective eligibility теперь считается как `policy ∩ semantic applicability ∩ degraded applicability`, а correct `not_applicable` не штрафуется как missing coverage;
- устранён gap case-vs-set degraded semantics: введён canonical `degraded_fallback_pass(case)` и set-level `hybrid_degraded_fallback_score` больше не используется как псевдо case predicate.

Открытые замечания:
- не блокируют `PR-H14 design`, но важны для implement-фазы:
  - scorer/renderer implementation должен держать discriminator-based parsing без silent fallback;
  - `HybridRuntimeSample` source в коде должен быть injected artifact pipeline, а не ad-hoc чтение из разных логов.

Verdict readiness:
- **Ready for implement** -> документ достаточно точен для staged реализации `PR-H14`, начиная с pause-only local hybrid eval и последующим расширением к live/offloading variants без переоткрытия core contract.

## Definition of Done (design mode)

`PR-H14` считается закрытым в design mode, если:
- есть implement-ready contract для multi-variant hybrid eval;
- hybrid metrics отделены от deterministic core metrics и не маскируют regressions;
- explainability agreement и mobile viability зафиксированы как release-relevant gates;
- ablation matrix достаточно точна для `PR-H05/H09/H11/H12` follow-up runs;
- report template пригоден и для engineering merge decision, и для thesis/demo narrative;
- по документу можно реализовать hybrid eval harness без домысливания о variant ids, bundle extension и compare rules.
