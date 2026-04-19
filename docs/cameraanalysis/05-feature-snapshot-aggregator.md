# 05. Feature Snapshot Aggregator (PR-004)

Статус: design spec + design verify (ready for implement)

Дата: 2026-04-19

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- [camera-analysis-v1-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-v1-architecture.md)
- [AnalysisPipeline.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift)
- [VisionTracking.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Models/Vision/VisionTracking.swift)
- [HorizonEstimator.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Models/Vision/HorizonEstimator.swift)
- [LightingEstimator.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Models/Lighting/LightingEstimator.swift)
- [AestheticScorer.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Models/CoreMLWrappers/AestheticScorer.swift)

## Цель

Спроектировать детерминированный `Feature Snapshot Aggregator`, который собирает текущие fast signals в единый `FrameFeatureSnapshot` без semantic-интерпретации.

## Scope и ограничения

В scope:
- сбор и нормализация low-level сигналов;
- source priorities, defaults, freshness, confidence behavior;
- единые правила merge без дублирования logic по слоям;
- test plan для unit tests реализации.

Вне scope:
- scene semantics;
- critique/recommendation logic;
- UI wiring;
- LLM/provider integration.

## Роль в pipeline

`Feature Snapshot Aggregator` запускается после execution policy и до `PrimarySubjectResolver`/`FrameCritiqueEngine`.

Гарантия слоя:
- одинаковый набор входных сигналов -> одинаковый snapshot;
- missing/late источники не ломают контракт;
- snapshot остается пригодным для downstream даже при partial data.

## Input Surface

Агрегатор принимает один входной пакет (runtime-only), который собирается из текущих модулей:

```text
FeatureAggregationInput
- frameId: String
- mode: AnalysisMode
- capturedAt: Date
- motionState: CameraAnalysisMotionState
- shakeLevel: CGFloat
- vision: VisionSample?
- horizon: HorizonSample?
- lighting: LightingSample?
- detr: DetrSample?
- aesthetic: AestheticSample?
```

Где каждый `*Sample` содержит:
- `value` (payload);
- `measuredAt` (`Date`);
- `baseConfidence` (`Double?`, 0...1, до учета freshness).

### Source Adapter Contract (обязательный для implement)

Перед `FeatureSnapshotAggregator` вводится adapter-слой, который переводит runtime-данные (`features`, `debugData`, callbacks модулей) в `FeatureAggregationInput`.

Обязательные правила:
- каждый `*Sample` обязан иметь `measuredAt`;
- `baseConfidence` может быть `nil`, если модуль confidence не дает;
- stale-eviction: если `freshnessMs > 3 * budgetMs`, sample считается недоступным (`available=false`, payload не используется);
- сбор `FeatureAggregationInput` выполняется атомарно из одного `featureQueue` snapshot, чтобы исключить смешивание разных update-циклов.

## Mapping в `FrameFeatureSnapshot`

### 1) `sources: FeatureSourceStatus`

Для каждого источника:
- `available = sample != nil` и sample не прошел stale-eviction;
- `freshnessMs = max(0, floor((capturedAt - measuredAt) * 1000))` в миллисекундах (если sample есть);
- `confidence = effectiveSourceConfidence(sample)` после freshness penalty.

Freshness budget (`v1`):
- `vision`: 250 ms
- `horizon`: 250 ms
- `lighting`: 700 ms
- `detr`: 1200 ms
- `aesthetic`: 3000 ms

Confidence formula (`deterministic`):
- `freshnessRatio = clamp01(1 - freshnessMs / (2 * budgetMs))`
- `effectiveConfidence = clamp01(baseConfidence * freshnessRatio)`

Если `baseConfidence == nil`, но источник есть:
- `effectiveConfidence` тоже `nil` (не подменяем synthetic числом).

### 2) `composition`

Приоритет источника центра кадра:
1. `primaryCandidateRegion` (см. subject merge ниже)
2. `vision.saliencyCenter`
3. default center `(0.5, 0.5)`

Расчет:
- `horizontalOffset = clamp11((centerX - 0.5) / 0.5)`
- `verticalOffset = clamp11((centerY - 0.333) / 0.333)`
- `subjectAreaRatio = area(primaryCandidateRegion)`, иначе `0`
- `saliencyLeftRightBalance = clamp11((saliencyX - 0.5) * 2)` при наличии saliency, иначе `horizontalOffset`
- `saliencyTopBottomBalance = clamp11((saliencyY - 0.5) * 2)` при наличии saliency, иначе `0`

### 3) `subjectSignals`

Детерминированный merge кандидатов:

1. Кандидаты от Vision: `TrackedSubject` (faces + humans), сортировка:
   - `rawConfidence desc`
   - `area desc`
   - `isFace desc` (face при равенстве имеет приоритет)
   - `midX asc`
   - `midY asc`
2. Кандидат от DETR: top-1 detection со stable sorting:
   - `rawConfidence desc`
   - `area desc`
   - `label asc`
   - `midX asc`
   - `midY asc`
3. Для каждого кандидата вычисляется `effectiveCandidateConfidence`:
   - Vision: `clamp01(rawConfidence * (sources.vision.confidence ?? 1.0))`
   - DETR: `clamp01(rawConfidence * (sources.detr.confidence ?? 1.0))`
4. Выбор primary candidate:
   - рассматриваются только кандидаты с `effectiveCandidateConfidence >= 0.20`;
   - выбирается кандидат с максимальным `effectiveCandidateConfidence`;
   - при равенстве (`abs(delta) < 0.01`) приоритет у Vision-кандидата;
   - если eligible-кандидатов нет: `primaryCandidateRegion=nil`, `primaryCandidateConfidence=nil`.
5. Нормализация региона:
   - перед записью в snapshot region приводится к `NormalizedRect` (`clamp` каждого поля в `0...1`);
   - если после нормализации регион вырожден (`width == 0` или `height == 0`), он отбрасывается (`nil`).

Поля:
- `faceDetected = vision.faceCount > 0`
- `personDetected = (vision.personCount > 0) || (vision.faceCount > 0)` (enforce invariants `faceDetected => personDetected`)
- `personCount = vision.personCount` (если нет vision -> `0`; DETR никогда не влияет на это поле)
- `topObjectLabel = detr.top1.label`
- `topObjectConfidence = detr.top1.confidence`
- `primaryCandidateRegion = selected.region`
- `primaryCandidateConfidence = selected.effectiveCandidateConfidence`

### 4) `horizon`

- если есть sample: `angleDegrees` и `confidence` из `HorizonEstimator`;
- иначе defaults: `angleDegrees = 0`, `confidence = 0`.

### 5) `lighting`

- если есть sample: прямой mapping `exposureBiasHint`, `backlightIndex`, `keyToFillRatio`;
- иначе defaults:
  - `exposureBiasHint = 0`
  - `backlightIndex = 0`
  - `keyToFillRatio = nil`

### 6) `motion`

- `state = motionState` (`still|moving|panning`);
- `shakeLevel = clamp01(shakeLevel)`.

### 7) `aesthetics`

- если score есть: `score = clamp01(score10 / 10.0)` (текущий `AestheticScorer` возвращает `0...10`);
- иначе `score=nil`;
- `scoreConfidence = effectiveSourceConfidence(aestheticSample)`.

### 8) `objects`

- `totalCount = detr.detections.count` (если нет detr -> `0`);
- `topKLabels = первые 3 label в порядке confidence`.

### 9) `technicalFlags`

Правила (`v1`):
- `low_light`, если `lighting.exposureBiasHint <= -0.35` или `lighting.backlightIndex >= 0.65`
- `high_motion`, если `motion.state != still` или `motion.shakeLevel >= 0.65`
- `low_subject_confidence`, если `primaryCandidateConfidence == nil` или `< 0.35`
- `low_scene_confidence`, если одновременно:
  - `sources.horizon.confidence ?? 0 < 0.20`
  - `sources.vision.confidence ?? 0 < 0.20`
  - `sources.detr.confidence ?? 0 < 0.20`

`technicalFlags` всегда вычисляются по правилам выше (не берутся из defaults-блока).
Флаги сортируются по `rawValue` для стабильной сериализации.

## Defaults Policy (единственная точка правды)

Если источник отсутствует, агрегатор всегда использует эти defaults:

```text
composition: horizontalOffset=0, verticalOffset=0, subjectAreaRatio=0, saliencyLeftRightBalance=0, saliencyTopBottomBalance=0
subjectSignals: faceDetected=false, personDetected=false, personCount=0, topObject*=nil, primaryCandidate*=nil
horizon: angleDegrees=0, confidence=0
lighting: exposureBiasHint=0, backlightIndex=0, keyToFillRatio=nil
motion: state=.still (adapter fallback), shakeLevel=0
aesthetics: score=nil, scoreConfidence=nil
objects: totalCount=0, topKLabels=[]
```

Примечание: при полностью пустых источниках `technicalFlags` вычисляются как минимум в
`[low_scene_confidence, low_subject_confidence]`.

## Anti-Duplication Rules

Чтобы избежать повторения логики в разных слоях:
- только агрегатор отвечает за source merge и fallback rules;
- semantics/critique используют уже собранный snapshot и не пересчитывают центры/area/freshness;
- `AnalysisPipeline` не должен иметь отдельные branch-правила для тех же вычислений после внедрения агрегатора;
- `SuggestionEngine` остается fallback-путем, но не source-of-truth для новых contract слоев.

## Integration Points (короткий note)

1. Добавить новый сервис `FeatureSnapshotAggregator` в `Multitool2Module/Services/Pipeline`.
2. Добавить adapter `PipelineFeatureSnapshotAdapter`, который формирует `FeatureAggregationInput` из `features + debugData + runtime callbacks` с `measuredAt/baseConfidence` per-source.
3. Adapter должен читать данные атомарно на `featureQueue` и не смешивать состояния разных frame-циклов.
4. `subjectSignals.personCount` всегда берется только из `VisionSample.personCount`.
5. Передавать snapshot в будущие `PrimarySubjectResolver` и `FrameCritiqueEngine` без дополнительной нормализации.
6. Текущий `currentSuggestion` path не менять в PR-004.

## Test Plan (для implement-фазы)

Набор обязательных unit tests:

1. Determinism:
- один и тот же `FeatureAggregationInput` дважды -> полностью равный snapshot.

2. Source priority:
- если Vision и DETR оба есть, primary candidate выбирается по `effectiveCandidateConfidence`.
- при равенстве scores срабатывает deterministic tie-break (Vision-first).
- DETR top-1 стабилен при равных confidence за счет полного tie-break порядка.

3. Fallbacks:
- без Vision/DETR center берется из saliency или defaults;
- при полностью пустых источниках snapshot валиден и соответствует defaults policy.

4. Freshness/confidence:
- `effectiveConfidence` монотонно падает с ростом `freshnessMs`;
- при просрочке `> 2*budget` confidence становится `0`.
- при `freshnessMs < 0` после нормализации используется `0`.
- при `freshnessMs > 3*budget` sample участвует как unavailable (stale-eviction).

5. Normalization:
- clamp для `[-1...1]` и `[0...1]` полей;
- эстетический score корректно нормализуется `0...10 -> 0...1`.
- вырожденный `NormalizedRect` отбрасывается (`nil`).

6. Technical flags:
- каждый flag имеет отдельный positive и negative case;
- список флагов стабильно отсортирован.

7. Contract invariants:
- `faceDetected => personDetected`;
- `personCount >= 0`, `objects.totalCount >= 0`;
- `personCount` зависит только от Vision source;
- сериализация `Codable` round-trip без потери данных.

## Definition of Done (`design`)

- rules merge/default/confidence полностью определены и не требуют домысливания при реализации;
- есть явные integration points для `AnalysisPipeline`;
- test plan покрывает deterministic behavior и edge cases;
- документ подключен к индексу `cameraanalysis` и backlog PR-004.

## Design Verify Outcome (2026-04-19)

Проверка выполнена через reviewer subagent и локальный review.

Закрытые пробелы:
- устранен конфликт `technicalFlags` defaults vs rules;
- зафиксирован обязательный source adapter contract (`measuredAt/baseConfidence`, stale-eviction, atomic read);
- добавлен детерминированный DETR tie-break;
- закреплено source ownership для `personCount` (только Vision);
- исправлен диапазон `AestheticScorer` до `0...10`;
- выбор primary candidate переведен на `effectiveCandidateConfidence`;
- формализована нормализация и отбрасывание вырожденных `NormalizedRect`;
- уточнен расчет `freshnessMs` (clamp + rounding policy).

Verdict: `Ready for implement` для `PR-004` в рамках текущего contract scope.
