# 06. Scene Semantics Layer (PR-005 + PR-006)

Статус: design spec + design verify (ready for implement)

Дата: 2026-04-20

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md)
- [05-feature-snapshot-aggregator.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/05-feature-snapshot-aggregator.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- [camera-analysis-v1-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-v1-architecture.md)
- [AnalysisPipeline.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift)
- [VisionTracking.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Models/Vision/VisionTracking.swift)
- [DETRDetector.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Models/CoreMLWrappers/DETRDetector.swift)

## Цель

Зафиксировать deterministic `Scene Semantics` слой `v1`, который из `FrameFeatureSnapshot` стабильно строит `SceneSemanticsReport` через:
- `PrimarySubjectResolver`;
- `SceneTypeClassifier`;
- `VisualDominanceAnalyzer`;
- `SemanticReadabilityAnalyzer`.

## Scope и ограничения

В scope:
- правила выбора primary subject;
- ограниченный cinematic scene catalog;
- confidence/ambiguity/fallback policy;
- golden-case test plan.

Вне scope:
- UI wiring;
- `FrameCritiqueEngine`;
- `RecommendationPlanner`;
- LLM/provider logic.

Ограничения `v1`:
- deterministic behavior first;
- scene catalog только из `SceneTypeV1`;
- при слабом сигнале корректный `unknown`/ambiguity, а не "угадывание".

## Input / Output слоя

### Input

Базовый вход:
- `FrameFeatureSnapshot` (source-of-truth).

Опциональный debug-вход (не влияет на `SceneSemanticsReport`):
- `SceneSemanticsAuxInput` из уже собранных runtime outputs:
  - top-3 vision candidates (`bbox`, `confidence`, `isFace`);
  - top-3 detr detections (`bbox`, `label`, `confidence`).

Ограничение для `v1`:
- `SceneSemanticsAuxInput` разрешен только для debug-логов/трейса и исключен из report-assembly;
- все поля `SceneSemanticsReport` вычисляются только из `FrameFeatureSnapshot`.

### Output

`SceneSemanticsReport` из [CameraAnalysisDomainContracts.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift):
- `sceneType`, `sceneTypeConfidence`;
- `primarySubject`;
- `dominance`;
- `readability`;
- `ambiguities`;
- `assumptions`.

## Supported Scene Types (`v1`)

Строго поддерживаются:
1. `dialogue_closeup`
2. `single_character_medium`
3. `two_character_frame`
4. `object_insert`
5. `establishing_like_frame`
6. `moody_backlit_subject`
7. `unknown` (обязательный fallback)

## 1) PrimarySubjectResolver

## Задача

Выдать:
- `primarySubject.kind`;
- `primarySubject.label`;
- `primarySubject.region`;
- `primarySubject.confidence`;
- `primarySubject.competingCandidates`.

## Candidate pool

Core candidate pool (обязательный, snapshot-only):
- кандидат #1: snapshot primary candidate (`region`, `confidence`);
- кандидат #2 (optional): `topObjectLabel/topObjectConfidence` как object candidate без region.
- если `snapshot.subjectSignals.personCount >= 2` и нет валидного region-кандидата, разрешен synthetic candidate `kind=group`, `confidence=clamp01(0.35 + 0.15 * min(3, personCount-1))`.

Debug enrichment pool (опциональный):
- aux-кандидаты используются только в отладочном trace и не попадают в `SceneSemanticsReport`.

## Candidate normalization

Для каждого кандидата:
- `kind = face/person/object/group` по источнику;
- `confidence = clamp01(rawConfidence)`;
- `region` нормализуется в `NormalizedRect`, вырожденные регионы отбрасываются;
- стабильный `id` формата `"<source>-<index>"`.

## Candidate scoring (deterministic)

`subjectScore = clamp01(baseConfidence * sourceReliability * kindWeight * regionWeight)`

Где:
- `baseConfidence = candidate.confidence`.
- `sourceReliability`:
  - vision: `snapshot.sources.vision.confidence ?? 0.55`
  - detr: `snapshot.sources.detr.confidence ?? 0.50`
  - snapshot-only fallback candidate: `max(snapshot.subjectSignals.primaryCandidateConfidence ?? 0, 0.25)`
- `kindWeight`:
  - `face = 1.00`
  - `person = 0.92`
  - `group = 0.90`
  - `object = 0.88`
  - `unknown = 0.70`
- `regionWeight`:
  - `1.0` если region есть и `area >= 0.02`;
  - `0.85` если region отсутствует;
  - `0.75` если region есть, но `area < 0.02`.

## Selection and ambiguity rules

1. Отсекаем кандидатов с `subjectScore < 0.20`.
2. Выбираем max `subjectScore`.
3. Tie-break при `abs(delta) < 0.03`:
- face > person > group > object > unknown;
- затем больше area;
- затем лексикографически меньший `id`.
4. Если есть второй кандидат с `abs(delta) < 0.07`, добавляем ambiguity:
- `type = multiple_subjects_similar_confidence`
- `candidateIds = [winnerId, secondId]`.
5. Если после фильтра нет кандидатов:
- `primarySubject.kind = .unknown`
- `confidence = 0`
- `region = nil`
- ambiguity `weak_signal`.

## Output mapping

- `primarySubject.confidence = winnerScore`.
- `primarySubject.label`:
  - для object: `topObjectLabel`/label кандидата;
  - для face/person: `nil` (в `v1` не распознаем identity).
- `primarySubject.competingCandidates`: максимум 2 ближайших по score конкурента из core candidate pool.

## 2) SceneTypeClassifier

## Задача

По snapshot + primary subject выбрать `sceneType` из фиксированного каталога.

## Rule scores

Для каждого `SceneTypeV1` считаем `ruleScore` (`0...1`) и берем max.

Определения общих подскоров (используются во всех правилах):
- `subjectPresence = primarySubject.kind == .unknown ? 0.0 : primarySubject.confidence`
- `areaScore = clamp01((snapshot.composition.subjectAreaRatio - 0.08) / 0.22)`
- `lowClutterScore = clamp01(1 - Double(snapshot.objects.totalCount) / 5.0)`
- `personSignal = snapshot.subjectSignals.personDetected ? 1.0 : 0.0`
- `mediumAreaScore = max(0.0, 1.0 - abs(snapshot.composition.subjectAreaRatio - 0.18) / 0.10)`
- `focusScore = dominance.hasClearFocus ? 1.0 : clamp01(1 - dominance.focusCompetitionScore)`
- `multiPersonScore = clamp01(Double(snapshot.subjectSignals.personCount) / 2.0)`
- `balanceScore = clamp01(1.0 - abs(snapshot.composition.horizontalOffset))`
- `objectConfidenceScore = clamp01(snapshot.subjectSignals.topObjectConfidence ?? 0.0)`
- `isolationScore = clamp01(1.0 - Double(snapshot.subjectSignals.personCount > 0 ? 1 : 0) - Double(snapshot.objects.totalCount > 4 ? 0.3 : 0.0))`
- `lowPersonScore = snapshot.subjectSignals.personDetected ? 0.0 : 1.0`
- `wideCompositionScore = clamp01(1.0 - snapshot.composition.subjectAreaRatio / 0.10)`
- `multiObjectScore = clamp01(Double(snapshot.objects.totalCount) / 6.0)`
- `lowPrimaryDominance = clamp01(1.0 - primarySubject.confidence)`
- `backlightScore = clamp01((snapshot.lighting.backlightIndex - 0.45) / 0.35)`
- `separationProxy = clamp01(0.50 * subjectPresence + 0.30 * (1 - dominance.backgroundClutterScore) + 0.20 * (1 - snapshot.lighting.backlightIndex))`
- `readabilityPenaltyInversion = clamp01(1.0 - separationProxy)`

### `dialogue_closeup`
- базовые признаки:
  - `primary.kind in {face, person}`
  - `subjectAreaRatio >= 0.22`
  - `objects.totalCount <= 3`
- формула:
  - `0.45 * subjectPresence + 0.35 * areaScore + 0.20 * lowClutterScore`

### `single_character_medium`
- признаки:
  - `personDetected = true`
  - `subjectAreaRatio in [0.08, 0.28]`
- формула:
  - `0.50 * personSignal + 0.30 * mediumAreaScore + 0.20 * focusScore`

### `two_character_frame`
- признаки:
  - `personCount >= 2`
- формула:
  - `0.60 * multiPersonScore + 0.20 * balanceScore + 0.20 * focusScore`

### `object_insert`
- признаки:
  - primary `kind == object`
  - `topObjectConfidence >= 0.45`
  - `personDetected == false`
- формула:
  - `0.60 * objectConfidenceScore + 0.25 * isolationScore + 0.15 * lowPersonScore`

### `establishing_like_frame`
- признаки:
  - `subjectAreaRatio <= 0.08`
  - `objects.totalCount >= 3` или `personDetected == false`
- формула:
  - `0.45 * wideCompositionScore + 0.35 * multiObjectScore + 0.20 * lowPrimaryDominance`

### `moody_backlit_subject`
- признаки:
  - `personDetected == true`
  - `lighting.backlightIndex >= 0.62`
  - `lighting.exposureBiasHint <= 0.05`
- формула:
  - `0.45 * backlightScore + 0.35 * subjectPresence + 0.20 * readabilityPenaltyInversion`

## Selection and confidence rules

1. Считаем `ruleScore` для всех типов кроме `unknown`.
2. Выбираем `bestType` и `bestScore`.
3. `runnerUpScore` = второй по величине.
4. `margin = bestScore - runnerUpScore`.
5. `sourceHealth = clamp01(0.5 * (snapshot.sources.vision.confidence ?? 0) + 0.5 * (snapshot.sources.detr.confidence ?? 0))`.
6. `sceneTypeConfidence = clamp01(bestScore * (0.65 + 0.35 * sourceHealth) * (margin >= 0.10 ? 1.0 : 0.85))`.
7. Если `low_scene_confidence` присутствует в `technicalFlags`, применяем штраф:
- `sceneTypeConfidence = sceneTypeConfidence * 0.85`.
8. Если `bestScore < 0.40` или `sceneTypeConfidence < 0.35`:
- `sceneType = .unknown`.
9. Если `margin < 0.08` и оба top-типа `>= 0.45`:
- добавить ambiguity `scene_type_tie`.

Примечание:
- unknown-check выполняется после всех penalty, включая `low_scene_confidence`.

## 3) VisualDominanceAnalyzer

## Output

`VisualDominanceState`:
- `hasClearFocus`
- `focusCompetitionScore`
- `backgroundClutterScore`

## Rules

- `focusCompetitionScore = clamp01(0.50 * (1 - primarySubject.confidence) + 0.30 * objectDensity + 0.20 * saliencyConflict)`.
- `backgroundClutterScore = clamp01(0.65 * objectDensity + 0.35 * saliencySpread)`.

Вспомогательные величины:
- `objectDensity = clamp01(Double(objects.totalCount) / 6.0)`.
- `saliencyConflict = abs(snapshot.composition.horizontalOffset - snapshot.composition.saliencyLeftRightBalance)`.
- `saliencySpread = abs(snapshot.composition.saliencyLeftRightBalance) * 0.5 + abs(snapshot.composition.saliencyTopBottomBalance) * 0.5`.

`hasClearFocus = true`, если одновременно:
- `primarySubject.confidence >= 0.55`;
- `focusCompetitionScore <= 0.45`;
- `backgroundClutterScore <= 0.55`.

## 4) SemanticReadabilityAnalyzer

## Output

`SemanticReadabilityState`:
- `subjectReadable`
- `lookSpaceAdequate`
- `edgePressureScore`
- `separationScore`

## Rules

1. `edgePressureScore`:
- если нет region: `0.50`;
- иначе минимум расстояний до 4 краев:
  - `minEdgeDistance = min(x, y, 1-(x+width), 1-(y+height))`
  - `edgePressureScore = clamp01(1 - minEdgeDistance / 0.10)`.

2. `separationScore`:
- `clamp01(0.45 * primarySubject.confidence + 0.35 * (1 - dominance.backgroundClutterScore) + 0.20 * (1 - lighting.backlightIndex))`.

3. `lookSpaceAdequate`:
- `nil` для `object_insert` и `establishing_like_frame`;
- для персонажных сцен:
  - `false`, если `edgePressureScore >= 0.75` и `abs(composition.horizontalOffset) >= 0.65`;
  - иначе `true`.

4. `subjectReadable = true`, если:
- `primarySubject.kind != .unknown`;
- `separationScore >= 0.45`;
- `edgePressureScore <= 0.80`.

## Execution order (обязательный)

Порядок вычисления фиксирован и не должен меняться в implement-фазе:
1. `PrimarySubjectResolver` (snapshot-only core selection)
2. `VisualDominanceAnalyzer`
3. `SceneTypeClassifier`
4. `SemanticReadabilityAnalyzer`
5. Finalize ambiguities/assumptions/sorting

## Confidence and fallback policy (общая)

- Все значения строго `clamp` в контрактные диапазоны.
- При `low_scene_confidence` в `technicalFlags`:
  - scene confidence дополнительно умножается на `0.85`;
  - обязательно добавляется ambiguity `weak_signal`.
- При `high_motion`:
  - `subjectReadable` может стать `false` только если `separationScore < 0.40` (защита от агрессивных false negatives).
- Пустые источники не ломают report:
  - обязательный fallback:
    - `sceneType=.unknown`, `sceneTypeConfidence=0`;
    - `primarySubject.kind=.unknown`, `primarySubject.confidence=0`, `region=nil`, `competingCandidates=[]`;
    - `dominance = { hasClearFocus=false, focusCompetitionScore=0.75, backgroundClutterScore=0.65 }`;
    - `readability = { subjectReadable=false, lookSpaceAdequate=nil, edgePressureScore=0.50, separationScore=0.20 }`;
    - `ambiguities` содержит `weak_signal`;
    - `assumptions=[]`.

## Error handling

Слой не бросает ошибки наружу; ошибки нормализуются в валидный fallback-report.

Сценарии:
1. `frameId` пустой:
- `frameId = "unknown-frame"` и полный weak-signal fallback.
2. Некорректный region во входе (NaN/inf/вырожденный):
- region отбрасывается (`nil`), добавляется ambiguity `weak_signal`.
3. Некорректный aux payload:
- aux полностью игнорируется; core report считается по snapshot-only.
4. Missing snapshot fields из-за несовместимой версии:
- report в unknown-fallback и assumption `"contract_version_mismatch"`.

## Determinism rules

- deterministic replay определяется только по `FrameFeatureSnapshot` входу; `SceneSemanticsAuxInput` не должен менять `SceneSemanticsReport`.
- `ambiguities` сортируются по `(type.rawValue, note)` перед записью в report.
- `assumptions` сортируются по `id`.
- `competingCandidates` сортируются по `confidence desc`, затем `id asc`.
- Все текстовые `note` для ambiguities фиксированные (без runtime-шаблонизации), чтобы golden-тесты были стабильны.

## Integration points (implement)

1. Добавить `SceneSemanticsInput` + adapter рядом с `FeatureSnapshotAggregator` в `Multitool2Module/Services/Pipeline`.
2. Реализовать сервисы:
- `PrimarySubjectResolver`;
- `SceneTypeClassifier`;
- `VisualDominanceAnalyzer`;
- `SemanticReadabilityAnalyzer`;
- фасад `SceneSemanticsAnalyzer`.
3. `AnalysisPipeline` пока только собирает report и логирует/debug-export; UI path не трогать.
4. Downstream (`FrameCritiqueEngine`) должен получать уже готовый `SceneSemanticsReport`.

## Golden cases test plan (обязательный минимум)

1. `dialogue_closeup`: крупный face/person, низкий clutter -> scene type + clear focus.
2. `single_character_medium`: один персонаж среднего масштаба -> корректный type и adequate look space.
3. `two_character_frame`: два кандидата похожей силы -> type `two_character_frame` + ambiguity `multiple_subjects_similar_confidence`.
4. `object_insert`: сильный object без людей -> object type, `lookSpaceAdequate=nil`.
5. `establishing_like_frame`: маленький субъект + многоплановая сцена -> establishing type.
6. `moody_backlit_subject`: высокий backlight при наличии персонажа -> moody type и сниженный readability.
7. tie case: близкие rule scores двух scene types -> ambiguity `scene_type_tie`.
8. weak signal fallback: отсутствуют vision/detr -> `unknown` + ambiguity `weak_signal`.
9. deterministic replay: одинаковый input дважды -> byte-identical report.
10. invariants: `primarySubject.confidence < 0.2` приводит к `kind=unknown`, `hasClearFocus` не конфликтует с `focusCompetitionScore`.

## Design Verify Outcome (2026-04-20)

Проверка выполнена локально и через reviewer subagent.

Закрытые пробелы:
- устранен конфликт input-contract: core semantics теперь строго `snapshot-only`, aux переведен в debug enrichment;
- устранена зависимость classifier от post-step readability (введен `separationProxy`);
- добавлена policy для `SubjectKind.group` в `v1`;
- зафиксирован порядок вычисления анализаторов (execution order);
- уточнен decision flow для `low_scene_confidence` (penalty перед final unknown-check);
- добавлена секция `Error handling` с обязательными fallback outcomes.

Verdict: `Ready for implement` для `PR-005/PR-006` в рамках текущего contract scope.

Повторная проверка (reviewer subagent, 2026-04-20):
- `aux` полностью исключен из `SceneSemanticsReport` и оставлен только для debug trace;
- synthetic `group` перенесен в core candidate policy с однозначным участием в resolver rules;
- устранена двусмысленность `two_character_frame` (только snapshot-based `personCount >= 2`);
- deterministic replay явно зафиксирован как snapshot-only.

## Definition of Done (`design`)

- deterministic правила `PrimarySubjectResolver` и `SceneTypeClassifier` зафиксированы численно;
- confidence/ambiguity/fallback rules явно определены;
- список supported scene types `v1` зафиксирован;
- test plan покрывает golden и edge cases;
- документ связан с backlog (`PR-005`, `PR-006`) и индексом `cameraanalysis`.
