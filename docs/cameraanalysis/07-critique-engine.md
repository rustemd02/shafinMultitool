# 07. Critique Engine (PR-007)

Статус: design spec (source-of-truth)

Дата: 2026-04-20

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md)
- [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md)
- [05-feature-snapshot-aggregator.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/05-feature-snapshot-aggregator.md)
- [06-scene-semantics-layer.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/06-scene-semantics-layer.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- [camera-analysis-v1-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-v1-architecture.md)

## Цель

Зафиксировать deterministic дизайн `FrameCritiqueEngine`, который из:
- `FrameFeatureSnapshot`;
- `SceneSemanticsReport`;

воспроизводимо строит `CritiqueReport` с:
- `issues`;
- `strengths`;
- `severity/confidence`;
- traceable rationale для explainability pipeline.

## Scope и ограничения

В scope:
- правила детекции issues;
- правила детекции strengths;
- модель severity/confidence;
- связь с explainability trace;
- golden test matrix.

Вне scope:
- `RecommendationPlanner` (PR-008);
- UI wiring (`live/pause cards/overlay`);
- LLM/provider logic.

Ограничения `v1`:
- LLM не источник истины для issue detection;
- issue taxonomy строго ограничена `IssueTypeV1` из [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md);
- только детерминированные правила и шаблонные rationale.

## Input / Output Contract

## Input

```text
FrameCritiqueInput
- snapshot: FrameFeatureSnapshot
- semantics: SceneSemanticsReport
```

Предусловия:
- `snapshot.frameId == semantics.frameId`;
- `snapshot.mode == semantics.mode`.

## Output

`CritiqueReport` строго по контракту из `PR-002`:
- `frameId`, `mode`, `verdict`, `verdictConfidence`;
- `strengths`, `issues`, `summary`;
- `traceRefs`;
- `fallbackUsed`.

`fallbackUsed` в `v1`:
- `false` в штатном режиме;
- `true`, если включен degraded technical path при слабой семантической опоре (см. Edge cases).

## Детекторы issues (IssueTypeV1)

Каждый детектор возвращает `IssueCandidate?`:
- `type`;
- `rawScore` (0...1);
- `confidence` (0...1);
- `evidence`;
- `affectedRegion`;
- `suggestedFixTypes`;
- `rationaleTemplateKey`.

Порог создания issue:
- `rawScore >= 0.40` и `confidence >= 0.30`.

### 1) `subject_too_close_to_edge`

Rule basis:
- `semantics.readability.edgePressureScore`;
- `snapshot.composition.horizontalOffset`;
- `semantics.primarySubject.region`.

Формула:
- `rawScore = clamp01(0.70 * edgePressureScore + 0.30 * abs(horizontalOffset))`.
- `confidence = clamp01(0.60 * semantics.primarySubject.confidence + 0.40 * (snapshot.sources.vision.confidence ?? 0.0))`.

`affectedRegion`:
- `semantics.primarySubject.region` (если есть), иначе `snapshot.subjectSignals.primaryCandidateRegion`.

`suggestedFixTypes`:
- `reframing`.

### 2) `subject_not_prominent_enough`

Rule basis:
- `snapshot.composition.subjectAreaRatio`;
- `semantics.readability.separationScore`;
- `semantics.primarySubject.confidence`.

Формула:
- `areaPenalty = clamp01((0.10 - subjectAreaRatio) / 0.10)`.
- `sepPenalty = clamp01(1.0 - separationScore)`.
- `rawScore = clamp01(0.45 * areaPenalty + 0.35 * sepPenalty + 0.20 * (1.0 - primarySubjectConfidence))`.
- `confidence = clamp01(0.50 * primarySubjectConfidence + 0.30 * (snapshot.sources.vision.confidence ?? 0.0) + 0.20 * (snapshot.sources.detr.confidence ?? 0.0))`.

`suggestedFixTypes`:
- `reframing`;
- `angle_adjustment`.

### 3) `background_competes_with_subject`

Rule basis:
- `semantics.dominance.focusCompetitionScore`;
- `semantics.dominance.backgroundClutterScore`;
- `semantics.dominance.hasClearFocus`.

Формула:
- `focusPenalty = semantics.dominance.hasClearFocus ? 0.0 : 0.20`.
- `rawScore = clamp01(0.55 * focusCompetitionScore + 0.35 * backgroundClutterScore + 0.10 * focusPenalty)`.
- `confidence = clamp01(0.55 * semantics.sceneTypeConfidence + 0.45 * (snapshot.sources.detr.confidence ?? 0.0))`.

`suggestedFixTypes`:
- `angle_adjustment`;
- `reframing`.

### 4) `insufficient_look_space`

Rule basis:
- `semantics.readability.lookSpaceAdequate`;
- `snapshot.composition.horizontalOffset`;
- `semantics.primarySubject.region`.

Формула:
- если `primarySubject.kind` не входит в `{face, person, group}` -> `rawScore = 0`, `confidence = 0` (detector not applicable).
- если `lookSpaceAdequate == nil` -> `rawScore = 0` (rule not applicable для scene types без look-space семантики).
- если `lookSpaceAdequate == true` -> `rawScore = 0`.
- иначе (`lookSpaceAdequate == false`) -> `rawScore = clamp01(0.60 + 0.40 * abs(horizontalOffset))`.
- `confidence = (lookSpaceAdequate == nil || primarySubject.kind` не входит в `{face, person, group}`) ? 0 : clamp01(0.60 * semantics.primarySubject.confidence + 0.40 * semantics.sceneTypeConfidence)`.

`suggestedFixTypes`:
- `reframing`.

### 5) `backlight_hides_subject`

Rule basis:
- `snapshot.lighting.backlightIndex`;
- `snapshot.lighting.exposureBiasHint`;
- `semantics.readability.separationScore`;
- `semantics.primarySubject.kind`.

Формула:
- `backlightScore = clamp01((backlightIndex - 0.45) / 0.55)`.
- `exposurePenalty = exposureBiasHint < 0 ? clamp01(abs(exposureBiasHint) / 0.40) : 0.0`.
- `sepPenalty = clamp01(1.0 - separationScore)`.
- `personBoost = (primarySubject.kind == face || primarySubject.kind == person) ? 0.08 : 0.0`.
- `rawScore = clamp01(0.45 * backlightScore + 0.30 * exposurePenalty + 0.25 * sepPenalty + personBoost)`.
- `confidence = clamp01(0.65 * (snapshot.sources.lighting.confidence ?? 0.0) + 0.35 * semantics.primarySubject.confidence)`.

`suggestedFixTypes`:
- `lighting_adjustment`;
- `angle_adjustment`.

### 6) `scene_has_no_clear_focus`

Rule basis:
- `semantics.dominance.hasClearFocus`;
- `semantics.dominance.focusCompetitionScore`;
- `semantics.primarySubject.confidence`;
- `semantics.ambiguities`.

Формула:
- если `hasClearFocus == true` -> `rawScore = 0`.
- иначе:
  - `ambiguityBoost = containsAmbiguity(multiple_subjects_similar_confidence) ? 0.15 : 0.0`;
  - `rawScore = clamp01(0.60 * focusCompetitionScore + 0.30 * (1.0 - primarySubjectConfidence) + ambiguityBoost)`.
- `confidence = clamp01(0.55 * semantics.sceneTypeConfidence + 0.45 * primarySubjectConfidence)`.
`ambiguityBoost` — осознанная additive-калибровка: при наличии ambiguity вклад в rawScore ровно `+0.15`.

`suggestedFixTypes`:
- `reframing`;
- `angle_adjustment`.

### 7) `frame_visually_overloaded`

Rule basis:
- `semantics.dominance.backgroundClutterScore`;
- `snapshot.objects.totalCount`;
- `semantics.sceneType`.

Формула:
- `densityScore = clamp01(Double(objects.totalCount) / 8.0)`.
- `clutterCore = clamp01(0.65 * backgroundClutterScore + 0.35 * densityScore)`.
- `scenePenalty = semantics.sceneType == establishing_like_frame ? 0.15 : 0.0`.
- `rawScore = clamp01(clutterCore - scenePenalty)`.
- `confidence = clamp01(0.50 * semantics.sceneTypeConfidence + 0.50 * (snapshot.sources.detr.confidence ?? 0.0))`.

`suggestedFixTypes`:
- `angle_adjustment`;
- `reframing`.

### 8) `horizon_distracts`

Rule basis:
- `snapshot.horizon.angleDegrees`;
- `snapshot.horizon.confidence`;
- `semantics.sceneType`.

Формула:
- `tilt = abs(angleDegrees)`.
- `sceneSensitivity = (sceneType == dialogue_closeup || sceneType == single_character_medium) ? 1.00 : 0.75`.
- `rawScore = clamp01((tilt / 8.0) * sceneSensitivity)`.
- если `snapshot.horizon.confidence < 0.30` -> `rawScore = rawScore * 0.60`.
- `confidence = clamp01(snapshot.horizon.confidence)`.

`suggestedFixTypes`:
- `horizon_correction`;
- `angle_adjustment`.

## Детекторы strengths (StrengthTypeV1)

Порог создания strength:
- `score >= 0.55` и `confidence >= 0.35`.

### 1) `good_subject_isolation`
- `score = clamp01(0.60 * separationScore + 0.40 * (1.0 - backgroundClutterScore))`.
- `confidence = clamp01(0.60 * primarySubjectConfidence + 0.40 * sceneTypeConfidence)`.
- `supportingRegion = primarySubject.region`.

### 2) `good_light_emphasis`
- `score = clamp01(0.55 * (1.0 - backlightIndex) + 0.45 * separationScore)`.
- `confidence = clamp01(0.70 * (snapshot.sources.lighting.confidence ?? 0.0) + 0.30 * sceneTypeConfidence)`.

### 3) `clear_focus_hierarchy`
- `score = clamp01(0.65 * (hasClearFocus ? 1.0 : 0.0) + 0.35 * (1.0 - focusCompetitionScore))`.
- `confidence = clamp01(0.60 * primarySubjectConfidence + 0.40 * sceneTypeConfidence)`.

### 4) `stable_horizon_supports_scene`
- `score = clamp01(1.0 - abs(angleDegrees) / 6.0)`.
- `confidence = clamp01(snapshot.horizon.confidence)`.

### 5) `balanced_composition_for_scene`
- `centerPenalty = abs(snapshot.composition.horizontalOffset)`.
- `sceneTolerance = semantics.sceneType == establishing_like_frame ? 0.35 : 0.20`.
- `score = clamp01(1.0 - max(0.0, centerPenalty - sceneTolerance) / (1.0 - sceneTolerance))`.
- `confidence = clamp01(0.50 * primarySubjectConfidence + 0.50 * sceneTypeConfidence)`.

## Rationale and evidence templates (deterministic catalog)

`FrameCritiqueEngine` обязан собирать `rationale` и `evidence` строго по фиксированным template keys.
Каждый finding берет только свой template и обязательный набор `evidenceKeys`.

### Issues

- `subject_too_close_to_edge`
  - `rationaleTemplateKey = issue.edge_pressure`
  - template: "Главный объект прижат к краю кадра, из-за чего теряется визуальный баланс."
  - required evidence keys:
    - `semantics.readability.edgePressureScore`
    - `snapshot.composition.horizontalOffset`

- `subject_not_prominent_enough`
  - `rationaleTemplateKey = issue.subject_prominence`
  - template: "Главный объект недостаточно выражен относительно фона и масштаба кадра."
  - required evidence keys:
    - `snapshot.composition.subjectAreaRatio`
    - `semantics.readability.separationScore`
    - `semantics.primarySubject.confidence`

- `background_competes_with_subject`
  - `rationaleTemplateKey = issue.background_competition`
  - template: "Фон конкурирует с главным объектом и снижает читаемость акцента."
  - required evidence keys:
    - `semantics.dominance.focusCompetitionScore`
    - `semantics.dominance.backgroundClutterScore`

- `insufficient_look_space`
  - `rationaleTemplateKey = issue.look_space`
  - template: "По направлению взгляда или движения не хватает свободного пространства."
  - required evidence keys:
    - `semantics.readability.lookSpaceAdequate`
    - `snapshot.composition.horizontalOffset`

- `backlight_hides_subject`
  - `rationaleTemplateKey = issue.backlight`
  - template: "Контровой свет снижает читаемость главного объекта."
  - required evidence keys:
    - `snapshot.lighting.backlightIndex`
    - `snapshot.lighting.exposureBiasHint`
    - `semantics.readability.separationScore`

- `scene_has_no_clear_focus`
  - `rationaleTemplateKey = issue.no_clear_focus`
  - template: "В кадре нет устойчивого центра внимания."
  - required evidence keys:
    - `semantics.dominance.hasClearFocus`
    - `semantics.dominance.focusCompetitionScore`
    - `semantics.primarySubject.confidence`

- `frame_visually_overloaded`
  - `rationaleTemplateKey = issue.visual_overload`
  - template: "Кадр визуально перегружен и отвлекает от основного объекта."
  - required evidence keys:
    - `semantics.dominance.backgroundClutterScore`
    - `snapshot.objects.totalCount`
    - `semantics.sceneType`

- `horizon_distracts`
  - `rationaleTemplateKey = issue.horizon_tilt`
  - template: "Наклон горизонта отвлекает от восприятия сцены."
  - required evidence keys:
    - `snapshot.horizon.angleDegrees`
    - `snapshot.horizon.confidence`
    - `semantics.sceneType`

### Strengths

- `good_subject_isolation`
  - `rationaleTemplateKey = strength.subject_isolation`
  - template: "Главный объект хорошо отделен от фона."
  - required evidence keys:
    - `semantics.readability.separationScore`
    - `semantics.dominance.backgroundClutterScore`

- `good_light_emphasis`
  - `rationaleTemplateKey = strength.light_emphasis`
  - template: "Свет поддерживает акцент на главном объекте."
  - required evidence keys:
    - `snapshot.lighting.backlightIndex`
    - `semantics.readability.separationScore`

- `clear_focus_hierarchy`
  - `rationaleTemplateKey = strength.clear_focus`
  - template: "Иерархия внимания в кадре читается ясно."
  - required evidence keys:
    - `semantics.dominance.hasClearFocus`
    - `semantics.dominance.focusCompetitionScore`

- `stable_horizon_supports_scene`
  - `rationaleTemplateKey = strength.stable_horizon`
  - template: "Горизонт стабилен и не отвлекает от сцены."
  - required evidence keys:
    - `snapshot.horizon.angleDegrees`
    - `snapshot.horizon.confidence`

- `balanced_composition_for_scene`
  - `rationaleTemplateKey = strength.balanced_composition`
  - template: "Композиция сбалансирована для текущего типа сцены."
  - required evidence keys:
    - `snapshot.composition.horizontalOffset`
    - `semantics.sceneType`
    - `semantics.sceneTypeConfidence`

## Severity / Confidence Model

## Severity (для issues)

`severity` вычисляется из `rawScore` + mode/context penalty:

```text
baseSeverity = rawScore
modeMultiplier = (mode == pause) ? 1.00 : 0.92
criticalBoost = issueType in {backlight_hides_subject, scene_has_no_clear_focus} ? 0.06 : 0.0
severity = clamp01(baseSeverity * modeMultiplier + criticalBoost)
```

## Confidence (для issues/strengths)

Execution order фиксирован:
1. Вычислить `rawScore/score` и базовый `confidence` детектора.
2. Применить локальные penalties из edge-case правил (например `unknown subject`, `high_motion`).
3. Применить scene-confidence penalties.
4. Применить `clamp01`.
5. Применить creation thresholds (issues/strengths).

`scene-dependent` findings для penalty при `low_scene_confidence` (`* 0.85`):
- issues:
  - `subject_not_prominent_enough`
  - `background_competes_with_subject`
  - `insufficient_look_space`
  - `scene_has_no_clear_focus`
  - `frame_visually_overloaded`
- strengths:
  - `good_subject_isolation`
  - `good_light_emphasis`
  - `clear_focus_hierarchy`
  - `balanced_composition_for_scene`

Creation thresholds применяются после всех penalties:
- issue создается только если `rawScore >= 0.40` и `confidence >= 0.30`;
- strength создается только если `score >= 0.55` и `confidence >= 0.35`.

## Verdict Aggregation

1. `maxIssueSeverity = max(issues.severity)` или `0`, если issues пуст.
2. `highIssueCount = count(issues where severity >= 0.65)`.
3. `strongStrengthCount = count(strengths where confidence >= 0.70)`.
4. Правила:
- `needs_fix`, если `maxIssueSeverity >= 0.72` или `highIssueCount >= 2`.
- `good`, если `issues.isEmpty` или (`maxIssueSeverity < 0.45` и `strongStrengthCount >= 2`).
- иначе `mixed`.
5. `verdictConfidence`:
- `signalSupport = clamp01(0.40 * (snapshot.sources.vision.confidence ?? 0.0) + 0.30 * (snapshot.sources.lighting.confidence ?? 0.0) + 0.30 * semantics.sceneTypeConfidence)`.
- `consistency = clamp01(1.0 - Double(abs(strengths.count - issues.count)) / 6.0)`.
- `verdictConfidence = clamp01(0.65 * signalSupport + 0.35 * consistency)`.
6. Degraded override:
- если `fallbackUsed == true`, то `strengths = []`;
- если после базовой агрегации `verdict == good`, он принудительно понижается до `mixed`;
- `verdictConfidence` дополнительно ограничивается `<= 0.55`.

## Summary builder (deterministic templates)

`CritiqueSummary.shortVerdict` генерируется только из templates:
- `good`: "Кадр читается стабильно, критичных проблем не выявлено."
- `mixed`: "Кадр рабочий, но есть зоны для улучшения композиции и читаемости."
- `needs_fix`: "Главный объект считывается с трудом, сначала исправьте приоритетные дефекты."

`whyGood`:
- top-2 strengths по `confidence`.

`whyProblematic`:
- top-2 issues по `severity`.

`summary.id`:
- `summary_<frameId>_main`.

## Explainability linkage

`FrameCritiqueEngine` не строит финальный `ExplainabilityTraceBundle`, но обязан подготовить его детерминированную основу:

1. Ownership ID generation:
- `FrameCritiqueEngine` владеет `FrameIssue.id`, `FrameStrength.id` и `CritiqueReport.traceRefs`.
- `ExplainabilityTraceAssembler` обязан использовать seed IDs из `traceRefs` как финальные `ExplainabilityTraceItem.id` для interpretation-элементов (без переименования).

2. Порядок генерации фиксирован:
- detect candidates -> apply penalties -> apply thresholds -> sort findings -> assign ids -> emit traceRefs.

3. После сортировки каждый `FrameIssue` и `FrameStrength` получает stable `id`:
- issue: `iss_<frameId>_<nn>` (`nn` начинается с `01`, по итоговому sorted order);
- strength: `str_<frameId>_<nn>` (`nn` начинается с `01`, по итоговому sorted order).

4. Каждый finding содержит `evidence` только из разрешенных источников:
- `snapshot`;
- `semantics`;
- `derived_rule`.

5. `CritiqueReport.traceRefs` заполняется `interpretation`-seed IDs:
- `trc_<frameId>_crit_i<nn>` для issues;
- `trc_<frameId>_crit_s<nn>` для strengths.
- `trc_<frameId>_crit_summary_main` для summary.

6. Explainability assembler обязан:
- создать `TraceStage.interpretation` item на каждый seed;
- поставить `TraceLink(kind: issue|strength, refId: finding.id)`;
- для `trc_<frameId>_crit_summary_main` создать item с `TraceLink(kind: summary, refId: summary.id)`;
- связать `dependsOn` с observation trace items из snapshot/semantics.

Этим обеспечивается требование Prompt 5: все issues/strengths имеют traceable rationale.

## Invariants

1. Детерминизм: идентичные `snapshot+semantics` -> byte-wise одинаковый `CritiqueReport` (при сортировке полей и finding lists).
2. `issues` отсортированы по `severity desc`, затем `type`, затем `id`.
3. `strengths` отсортированы по `confidence desc`, затем `type`, затем `id`.
4. Каждый issue содержит минимум один `EvidenceRef`.
5. `affectedRegion` не выходит за `0...1`; вырожденный region запрещен.
6. `verdict == good` невозможен при наличии issue `severity >= 0.65`.
7. `fallbackUsed == true` только при активированном degraded path.
8. `suggestedFixTypes` не пуст для каждого issue.
9. Если issue и strength ссылаются на один и тот же фактор, формулировки rationale не должны противоречить друг другу.
10. Критика не создает новых taxonomy типов вне контрактов `IssueTypeV1` и `StrengthTypeV1`.
11. В одном `CritiqueReport` допускается не более одного finding на каждый `IssueTypeV1` и на каждый `StrengthTypeV1`.
12. При `fallbackUsed == true` `verdict != good` и `strengths.isEmpty == true`.

## Edge cases и fallback rules

1. Semantics weak-signal degraded mode:
- `SceneSemanticsReport` в `v1` обязателен (см. [06-scene-semantics-layer.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/06-scene-semantics-layer.md):312).
- degraded mode активируется, если `low_scene_confidence` присутствует в `snapshot.technicalFlags`.
- `semantics.sceneType == unknown` и ambiguity `weak_signal` рассматриваются как ожидаемое следствие того же weak-signal состояния, но не отдельный триггер.
- в degraded mode:
  - запускается technical-priority fallback по тем же формулам;
  - разрешены только issues:
    - `horizon_distracts`
    - `backlight_hides_subject`
    - `subject_not_prominent_enough`
  - `fallbackUsed = true`;
  - `strengths = []`;
  - `verdict` минимум `mixed`;
  - `verdictConfidence` ограничить `<= 0.55`.

2. Scene ambiguity (`scene_type_tie`):
- scene-sensitive rules получают confidence penalty `* 0.90`.

3. Unknown primary subject:
- запрещено создавать `insufficient_look_space`;
- понижается confidence для `subject_too_close_to_edge` (`* 0.80`).

4. High motion (`high_motion` flag):
- сохраняем issue detection;
- но severity for composition-related issues (`subject_too_close_to_edge`, `insufficient_look_space`) `* 0.92` для live, чтобы снизить "дерганье" при движении.

5. Invalid external semantics guard:
- комбинация `hasClearFocus == true` и `backgroundClutterScore > 0.55` считается невалидным внешним входом (недостижима при стандартном `PR-006` pipeline).
- перед детекцией issues состояние нормализуется:
  - `hasClearFocus = false`;
  - дальше применяются обычные rules.
- этот guard не является golden-case для штатного пайплайна.

## Test Plan (golden + contract tests)

Минимальный набор для implement-фазы:

1. Golden: `single face near right edge + strong backlight` -> issues `subject_too_close_to_edge`, `backlight_hides_subject`, verdict `needs_fix`.
2. Golden: `centered readable portrait, low clutter` -> strengths `good_subject_isolation`, `clear_focus_hierarchy`, verdict `good`.
3. Golden: `cluttered scene with weak subject` -> issues `background_competes_with_subject`, `scene_has_no_clear_focus`, `frame_visually_overloaded`.
4. Golden: `tilted horizon, dialogue_closeup` -> `horizon_distracts` создается только при `horizon.confidence >= 0.30`.
5. Golden: `establishing_like_frame with many objects` -> `frame_visually_overloaded` не должен срабатывать по penalty, если clutter умеренный.
6. Edge: semantics weak-signal degraded mode -> `fallbackUsed=true`, ограниченный набор issues.
7. Edge: `scene_type_tie` ambiguity -> confidence penalty для scene-dependent findings.
8. Edge: `lookSpaceAdequate=nil` -> `insufficient_look_space` не создается.
9. Edge: unknown subject -> no `insufficient_look_space`.
10. Contract: каждый issue/strength имеет trace seed в `traceRefs`.
11. Contract: есть summary seed `trc_<frameId>_crit_summary_main`, и assembler связывает его с `summary.id`.
12. Contract: `ExplainabilityTraceAssembler` использует seed IDs из `traceRefs` без переименования.
13. Contract: findings unique-by-type для issues и strengths.
14. Contract: `affectedRegion` всегда в `0...1` и не вырожден.
15. Contract: все `suggestedFixTypes` принадлежат `FixTypeV1`.
16. Contract: при `fallbackUsed=true` выполняется `verdict != good` и `strengths.isEmpty`.
17. Contract: сортировка `issues/strengths` стабильна по объявленным правилам.
18. Edge: high-motion в live понижает severity composition-related issues по коэффициенту `0.92`.
19. Determinism: повторный запуск на одном fixture дает идентичный report.
20. Contract: каждый issue имеет минимум один `EvidenceRef` (invariant #4).
21. Contract: при любом issue с `severity >= 0.65` verdict никогда не `good` (invariant #6).
22. Contract: каждый issue имеет непустой `suggestedFixTypes` (invariant #8).
23. Contract: при общем факторе (например, свет) rationale issue/strength не противоречат друг другу (invariant #9).
24. Contract: результаты не содержат finding types вне `IssueTypeV1`/`StrengthTypeV1` (invariant #10).
25. Calibration: при одинаковых входах для `scene_has_no_clear_focus` наличие `multiple_subjects_similar_confidence` увеличивает `rawScore` ровно на `+0.15`.

## Integration note (для PR-007 implement)

1. Реализовать `FrameCritiqueEngine` как отдельный сервис без UI-зависимостей.
2. Вход только `FrameFeatureSnapshot + SceneSemanticsReport`.
3. Отдать `CritiqueReport` в `RecommendationPlanner` и `ExplainabilityTraceAssembler`.
4. Текущий `SuggestionEngine` не менять в PR-007.

## Definition of Done (design mode)

Design считается готовым, если:
- issue/strength rules формализованы и ограничены taxonomy `v1`;
- severity/confidence policy фиксирована;
- trace linkage для explainability определен без двусмысленностей;
- перечислены invariants и edge cases;
- есть implement-ready golden test matrix для `PR-007`.
