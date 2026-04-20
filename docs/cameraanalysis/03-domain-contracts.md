# 03. Domain Contracts (PR-002)

Статус: design spec (source-of-truth)

Дата: 2026-04-19

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- [camera-analysis-v1-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-v1-architecture.md)
- [AnalysisPipeline.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift)
- [SuggestionEngine.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Suggestion/SuggestionEngine.swift)

## Цель

Зафиксировать domain contracts для `Camera Analysis v1`, чтобы следующие PR (`feature aggregation`, `scene semantics`, `critique`, `planner`) можно было реализовывать без домысливания.

Ограничения для `v1`:
- не ломаем текущий `live/pause` UI;
- не добавляем LLM как источник истины;
- используем ограниченный cinematic scene catalog;
- deterministic core обязателен даже без heavy reasoning.

## Boundary с текущей системой

Текущий `CoachingFeatures` остается runtime-источником низкоуровневых сигналов в существующем pipeline.

Новые контракты вводятся как отдельный source-of-truth слой:
- `FrameFeatureSnapshot` (агрегированные признаки кадра);
- `SceneSemanticsReport` (семантическая интерпретация);
- `CritiqueReport` (структурированная критика);
- `RecommendationPlan` (приоритизированный план действий).

`SuggestionEngine` остается fallback-веткой, пока новые слои не интегрированы в UI.

## Общие типы и конвенции

### Шкалы и confidence

- Все confidence: `0.0...1.0`.
- Все severity: `0.0...1.0`.
- Координаты регионов: normalized (`0.0...1.0`) в системе камеры.
- Временная метка кадра: `capturedAt` (UTC).

### Mode-aware политика

Каждый отчет знает, для какого режима был собран:
- `live`
- `pause`

Это позволяет разной глубине анализа жить в одном контракте, не ломая совместимость.

### Normalization policy

- Snapshot хранит **normalized/clamped** значения для диапазонных полей.
- Для `horizontalOffset`, `verticalOffset`, `saliency*` применяется `clamp(-1...1)`.
- Для `subjectAreaRatio`, `confidence`, `severity`, `shakeLevel`, `backlightIndex` применяется `clamp(0...1)`.
- Если нужен raw-сигнал, он должен идти отдельным optional-полем `raw*`, а не заменять normalized значение.

### Type Definitions (минимальный source-of-truth)

```text
AnalysisMode
- live
- pause

MotionState
- still
- moving
- panning

FrameVerdict
- good
- mixed
- needs_fix

NormalizedRect
- x: Double (required, 0...1)
- y: Double (required, 0...1)
- width: Double (required, 0...1)
- height: Double (required, 0...1)

FeatureSourceStatus
- vision: SourceState (required)
- horizon: SourceState (required)
- lighting: SourceState (required)
- detr: SourceState (required)
- aesthetic: SourceState (required)

SourceState
- available: Bool (required)
- freshnessMs: Int? (optional)
- confidence: Double? (optional, 0...1)

TechnicalFlag
- low_light
- high_motion
- low_subject_confidence
- low_scene_confidence

SubjectCandidate
- id: String (required)
- kind: SubjectKind (required)
- label: String? (optional)
- region: NormalizedRect? (optional)
- confidence: Double (required, 0...1)

SubjectKind
- face
- person
- object
- group
- unknown

SemanticsAmbiguity
- type: AmbiguityType (required)
- note: String (required)
- candidateIds: [String] (required)

AmbiguityType
- multiple_subjects_similar_confidence
- scene_type_tie
- weak_signal

SemanticsAssumption
- id: String (required)
- text: String (required)
- confidence: Double (required, 0...1)

CritiqueSummary
- id: String (required, stable summary id within frame)
- shortVerdict: String (required)
- whyGood: String? (optional)
- whyProblematic: String? (optional)

EvidenceRef
- source: EvidenceSource (required)
- key: String (required)
- value: String (required)
- confidence: Double? (optional, 0...1)

EvidenceSource
- snapshot
- semantics
- derived_rule

FixTypeV1
- reframing
- lighting_adjustment
- angle_adjustment
- horizon_correction
- leave_frame_as_is

ActionGuardrail
- requiresStillCamera: Bool (required)
- minConfidence: Double (required, 0...1)
- suppressWhenMoving: Bool (required)

OverlayHint
- id: String (required, stable overlay id within frame)
- kind: OverlayKind (required)
- targetRegion: NormalizedRect? (optional)
- direction: OverlayDirection? (optional)

OverlayKind
- arrow
- region_highlight
- horizon_line

OverlayDirection
- left
- right
- up
- down
```

## Contract 1. FrameFeatureSnapshot

`FrameFeatureSnapshot` — детерминированная агрегация измеримых сигналов без semantic-выводов.

```text
FrameFeatureSnapshot
- frameId: String
- mode: AnalysisMode (live|pause)
- capturedAt: Date
- sources: FeatureSourceStatus
- composition: CompositionFeatures
- subjectSignals: SubjectSignals
- horizon: HorizonFeatures
- lighting: LightingFeatures
- motion: MotionFeatures
- aesthetics: AestheticFeatures
- objects: ObjectDetectionsSummary
- technicalFlags: [TechnicalFlag]
```

Подструктуры:

```text
CompositionFeatures
- horizontalOffset: Double        // -1...1
- verticalOffset: Double          // -1...1
- subjectAreaRatio: Double        // 0...1
- saliencyLeftRightBalance: Double // -1...1
- saliencyTopBottomBalance: Double // -1...1

SubjectSignals
- faceDetected: Bool
- personDetected: Bool
- personCount: Int                 // только count людей из VisionTracking
- topObjectLabel: String?
- topObjectConfidence: Double?
- primaryCandidateRegion: NormalizedRect?
- primaryCandidateConfidence: Double?

HorizonFeatures
- angleDegrees: Double
- confidence: Double

LightingFeatures
- exposureBiasHint: Double        // отрицательная: темно, положительная: светло
- backlightIndex: Double          // 0...1
- keyToFillRatio: Double?

MotionFeatures
- state: MotionState (still|moving|panning)
- shakeLevel: Double              // 0...1

AestheticFeatures
- score: Double?
- scoreConfidence: Double?

ObjectDetectionsSummary
- totalCount: Int                  // count всех DETR detections
- topKLabels: [String]
```

### Invariants (`FrameFeatureSnapshot`)

- `frameId` обязателен и уникален в пределах сессии.
- `subjectAreaRatio == 0` допустим при отсутствии надежного субъекта.
- `personCount` и `objects.totalCount` считаются из разных источников и не обязаны совпадать.
- Если `faceDetected == true`, то `personDetected == true`.
- При `motion.state != still` snapshot валиден, но downstream может понижать приоритет рекомендаций.
- Все диапазонные поля хранятся уже `clamped` по правилам normalization policy.
- Отсутствие источника (`DETR`, `aesthetic`) не ломает контракт: отражается в `sources` и optional-полях.

## Contract 2. SceneSemanticsReport

`SceneSemanticsReport` превращает snapshot в сценовый смысл с ограниченным catalog `v1`.

```text
SceneSemanticsReport
- frameId: String
- mode: AnalysisMode
- sceneType: SceneTypeV1
- sceneTypeConfidence: Double
- primarySubject: PrimarySubject
- dominance: VisualDominanceState
- readability: SemanticReadabilityState
- ambiguities: [SemanticsAmbiguity]
- assumptions: [SemanticsAssumption]
```

Catalog `SceneTypeV1` (ограниченный):
- `dialogue_closeup`
- `single_character_medium`
- `two_character_frame`
- `object_insert`
- `establishing_like_frame`
- `moody_backlit_subject`
- `unknown`

Подструктуры:

```text
PrimarySubject
- kind: SubjectKind (face|person|object|group|unknown)
- label: String?
- region: NormalizedRect?
- confidence: Double
- competingCandidates: [SubjectCandidate]

VisualDominanceState
- hasClearFocus: Bool
- focusCompetitionScore: Double   // 0...1
- backgroundClutterScore: Double  // 0...1

SemanticReadabilityState
- subjectReadable: Bool
- lookSpaceAdequate: Bool?
- edgePressureScore: Double        // 0...1
- separationScore: Double          // 0...1
```

### Invariants (`SceneSemanticsReport`)

- `frameId` должен совпадать с snapshot.
- `sceneType == unknown` допускается и считается корректным fallback.
- `primarySubject.kind == unknown` обязателен при очень низкой уверенности.
- Нельзя одновременно иметь `hasClearFocus == true` и `focusCompetitionScore > 0.8`.
- Ambiguity фиксируется явно, если у top-2 кандидатов близкая уверенность.

## Contract 3. CritiqueReport

`CritiqueReport` — единый explainable-диагноз кадра, формируемый из `FrameFeatureSnapshot + SceneSemanticsReport`.

```text
CritiqueReport
- frameId: String
- mode: AnalysisMode
- verdict: FrameVerdict (good|mixed|needs_fix)
- verdictConfidence: Double
- strengths: [FrameStrength]
- issues: [FrameIssue]
- summary: CritiqueSummary
- traceRefs: [String]              // IDs explainability items
- fallbackUsed: Bool
```

`FrameIssue`:

```text
FrameIssue
- id: String
- type: IssueTypeV1
- severity: Double                 // 0...1
- confidence: Double               // 0...1
- rationale: String                // deterministic template ready
- evidence: [EvidenceRef]
- affectedRegion: NormalizedRect?
- suggestedFixTypes: [FixTypeV1]
```

`FrameStrength`:

```text
FrameStrength
- id: String
- type: StrengthTypeV1
- confidence: Double
- rationale: String
- evidence: [EvidenceRef]
- supportingRegion: NormalizedRect?
```

Issue taxonomy (`v1`):
- `subject_too_close_to_edge`
- `subject_not_prominent_enough`
- `background_competes_with_subject`
- `insufficient_look_space`
- `backlight_hides_subject`
- `scene_has_no_clear_focus`
- `frame_visually_overloaded`
- `horizon_distracts`

Strength taxonomy (`v1`):
- `good_subject_isolation`
- `good_light_emphasis`
- `clear_focus_hierarchy`
- `stable_horizon_supports_scene`
- `balanced_composition_for_scene`

### Invariants (`CritiqueReport`)

- `issues` и `strengths` могут сосуществовать в одном кадре.
- `verdict == good` допустим только если нет issue с severity выше порога критичности (`>=0.65`).
- Любой issue обязан иметь минимум один `evidence` элемент.
- `fallbackUsed == true` только если semantics/critique часть деградировала и использованы технические эвристики.
- Текст `rationale` не содержит домыслов вне evidence.
- `summary.id` обязателен и стабилен в рамках `frameId` (используется как trace target `TraceLinkKind.summary`).

## Contract 4. RecommendationPlan

`RecommendationPlan` переводит critique в действия для `live` и `pause` без UI wiring.

```text
RecommendationPlan
- frameId: String
- mode: AnalysisMode
- inputVerdict: FrameVerdict
- primaryAction: RecommendationAction?
- secondaryActions: [RecommendationAction]
- deferredActions: [RecommendationAction]
- noChangeRationale: String?
- planConfidence: Double
```

`RecommendationAction`:

```text
RecommendationAction
- id: String
- actionType: ActionTypeV1
- priority: Int                    // 1 = highest
- targetRegion: NormalizedRect?
- linkedIssueIds: [String]
- expectedOutcome: String
- guardrail: ActionGuardrail
- overlayHint: OverlayHint?
```

Action catalog (`v1`):
- `move_frame_left`
- `move_frame_right`
- `move_frame_up`
- `move_frame_down`
- `increase_subject_size`
- `reduce_background_distractions`
- `change_angle`
- `improve_front_light`
- `level_horizon`
- `leave_frame_as_is`

### Invariants (`RecommendationPlan`)

- В `live` максимум 1 `primaryAction`; secondary допускаются только для pause consumption.
- Если `inputVerdict == good`, то `primaryAction` обычно `leave_frame_as_is` или `nil` с `noChangeRationale`.
- Каждый action (кроме `leave_frame_as_is`) связан минимум с одной issue через `linkedIssueIds`.
- `priority` уникален внутри `primary + secondary`.
- План не должен содержать противоречащих действий (`move_frame_left` и `move_frame_right` одновременно).
- Если у action есть `overlayHint`, то `overlayHint.id` обязателен и уникален в рамках `frameId` (используется как trace target `TraceLinkKind.overlay`).

## Примеры (JSON-like)

Ниже приведены **partial examples** (сфокусированы на смысловых полях).
Для сериализации и contract tests использовать canonical fixtures с полным набором required-полей.

### Example A: Problematic frame (backlit portrait)

```json
{
  "frameFeatureSnapshot": {
    "frameId": "f-1021",
    "mode": "pause",
    "composition": { "horizontalOffset": 0.64, "verticalOffset": -0.05, "subjectAreaRatio": 0.11 },
    "subjectSignals": { "faceDetected": true, "personDetected": true, "personCount": 1 },
    "horizon": { "angleDegrees": 1.2, "confidence": 0.72 },
    "lighting": { "exposureBiasHint": -0.31, "backlightIndex": 0.79 },
    "motion": { "state": "still", "shakeLevel": 0.07 },
    "aesthetics": { "score": 0.44 }
  },
  "sceneSemanticsReport": {
    "frameId": "f-1021",
    "sceneType": "moody_backlit_subject",
    "sceneTypeConfidence": 0.76,
    "primarySubject": { "kind": "face", "confidence": 0.86 },
    "dominance": { "hasClearFocus": true, "focusCompetitionScore": 0.19, "backgroundClutterScore": 0.41 },
    "readability": { "subjectReadable": false, "edgePressureScore": 0.82, "separationScore": 0.28 }
  },
  "critiqueReport": {
    "frameId": "f-1021",
    "verdict": "needs_fix",
    "summary": { "id": "summary_f1021_main", "shortVerdict": "кадру не хватает читаемости главного объекта" },
    "strengths": [{ "id": "s1", "type": "clear_focus_hierarchy", "confidence": 0.74 }],
    "issues": [
      { "id": "i1", "type": "subject_too_close_to_edge", "severity": 0.83, "confidence": 0.81 },
      { "id": "i2", "type": "backlight_hides_subject", "severity": 0.79, "confidence": 0.88 }
    ]
  },
  "recommendationPlan": {
    "frameId": "f-1021",
    "mode": "pause",
    "inputVerdict": "needs_fix",
    "primaryAction": {
      "id": "a1",
      "actionType": "move_frame_left",
      "priority": 1,
      "linkedIssueIds": ["i1"],
      "expectedOutcome": "добавить воздух слева и снизить краевое давление",
      "overlayHint": { "id": "ov_a1_left_arrow", "kind": "arrow", "direction": "left" }
    },
    "secondaryActions": [
      {
        "id": "a2",
        "actionType": "improve_front_light",
        "priority": 2,
        "linkedIssueIds": ["i2"],
        "expectedOutcome": "лучше отделить лицо от контрового фона"
      }
    ],
    "planConfidence": 0.81
  }
}
```

### Example B: Good frame (single character medium)

```json
{
  "frameId": "f-2033",
  "sceneType": "single_character_medium",
  "critiqueReport": {
    "verdict": "good",
    "verdictConfidence": 0.78,
    "summary": { "id": "summary_f2033_main", "shortVerdict": "кадр стабильный и визуально читаемый" },
    "strengths": [
      { "type": "balanced_composition_for_scene", "confidence": 0.82 },
      { "type": "good_light_emphasis", "confidence": 0.75 }
    ],
    "issues": []
  },
  "recommendationPlan": {
    "inputVerdict": "good",
    "primaryAction": { "actionType": "leave_frame_as_is", "priority": 1 },
    "secondaryActions": [],
    "noChangeRationale": "кадр читается, акцент стабилен, критичных дефектов нет"
  }
}
```

## Mapping со старыми структурами

Ближайший mapping для `PR-004`:
- `CoachingFeatures` -> `FrameFeatureSnapshot` (1:1 для горизонта/света/motion/части composition);
- `OverlayState.primaryBoundingBox` -> `subjectSignals.primaryCandidateRegion`;
- `DebugData.detrDetections` -> `objects`/`subjectSignals.topObject*`;
- текущий `SuggestionEngine` используется как fallback, пока `RecommendationPlan` не подается в UI.

## Test Plan (для последующих implement PR)

### Unit tests

- Snapshot normalization:
  - clamp диапазонов (`-1...1`, `0...1`);
  - корректная обработка optional источников (`DETR`/`aesthetic` недоступны).
- Semantics invariants:
  - fallback в `sceneType=unknown` при низкой уверенности;
  - ambiguity при близких subject-кандидатах.
- Critique consistency:
  - `verdict=good` не допускает high-severity issue;
  - каждый issue имеет evidence.
- Recommendation consistency:
  - отсутствуют конфликтующие actions;
  - action всегда ссылается на issue (кроме `leave_frame_as_is`).

### Golden cases

- `single face near right edge + backlight` -> edge + light issues.
- `stable centered subject + clean background` -> good verdict + leave-as-is.
- `no clear subject + clutter` -> focus competition issues + simplify action.
- `tilted horizon in dialogue closeup` -> horizon issue only при достаточной confidence горизонта.

### Contract tests

- JSON serialization round-trip для всех 4 контрактов.
- Backward-compatible добавление полей через optional/default policy.

## Design Verify (2026-04-19)

Источник независимой проверки: субагент-ревьюер (prompt `design verify`, Prompt 1).

Закрытые замечания:
- добавлены минимальные `Type Definitions` для ранее неявных опорных типов;
- устранена неявная зависимость `RecommendationPlan` от внешнего verdict через `inputVerdict`;
- зафиксирована семантика `personCount` vs `objects.totalCount`;
- зафиксировано правило `raw vs clamped` для range-полей;
- примеры помечены как `partial examples`, чтобы не конфликтовать с required-полями.

Открытые замечания (не блокируют `PR-004`):
- междокументный конфликт в старом архитектурном тексте, где `good_*` упомянуты в issue-list.
  Каноническая трактовка для реализации: `good_*` относятся к `Strength taxonomy` этого документа.

Verdict readiness:
- **Ready with conditions** -> после закрытия критичных неоднозначностей документ считается implement-ready для `PR-004...PR-008`.

## Definition of Done (design mode)

Этот design считается готовым, если:
- по нему можно писать `CritiqueEngine` и `RecommendationPlanner` без домысливания структуры;
- границы между snapshot/semantics/critique/plan фиксированы;
- перечислены invariants и примеры;
- есть test plan для следующей implementation-wave;
- ограниченный scene catalog `v1` и deterministic-first policy явно зафиксированы.
