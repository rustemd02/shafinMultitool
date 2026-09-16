# 03. Domain Contracts (PR-002)

Статус: design spec (source-of-truth)

Дата: 2026-04-19

Дополнение 2026-09-11: [следующий контракт Camera Coach](#camera-coach-domain-v3--проект-контракта-для-фото-и-видео) описан в конце этого документа по каталогу из 68 сценариев. Версия `camera-coach.domain.v3-draft.1` — спецификация для реализации; она ещё не декодируется приложением. Исторические PR-002 разделы выше дополнения и действующие Swift/ML v1/v2 контракты автоматически не заменяются.

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
- neural_evidence

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

## Camera Coach Domain v3 — проект контракта для фото и видео

Дата: 2026-09-11. Версия спецификации: `camera-coach.domain.v3-draft.1`. Статус: `design_spec`; реализация, машинная схема, runtime-conformance и release qualification отсутствуют. Пользователь поручил спроектировать контракт после [каталога требований §23](camera-analysis-requirements-draft.md#23-camera-coach-для-фото-и-видео-каталог-сценариев-следующего-контракта). Термин v3 выбран, поскольку `CameraCoachContractV2` уже занят; это не версия нейросети.

### N1. Область, решения и существующие владельцы

Research continuation (2026-09-11): [Polza probe и ограниченный DEBUG ingress](eval/POLZA_RESEARCH_PROBE.md). Двухпредметный observation-only профиль не реализует весь s2/v3 и не подключён к production camera/planner; результаты probe не являются conformance-тестом этого Swift профиля.

Спецификация охватывает все 68 случаев как целевой продуктовый домен. Рекомендованная первая реализация — полный эпизод с несколькими предметами; временные видеосценарии используют тот же домен и отдельные требования к evidence. Возможность выразить кейс не означает его квалификацию для выпуска.

Принятые для проектирования значения: базовый live-путь локальный; подробный облачный анализ опционален и требует явного запроса; во время записи допустимы только ненавязчивые локальные подсказки; импорт выбранного фото/фрагмента представим, но не создаёт автоматического доступа к медиатеке. Эти решения конкретизируют контракт и не разрешают deployment, camera egress или изменение App Store 1.0 scope.

Сравнены три подхода: расширить 26 старых action strings (недостаточно для независимых объектов и времени); передать VLM свободное создание советов (нет проверяемой семантики действий); расширить существующий evidence → planner → verifier типизированными сущностями, операциями и целями (выбранный вариант). Второй planner, отдельная база графов сцены и новая ML-голова на каждый сценарий не нужны.

| Ответственность | Текущий владелец/источник | Изменение следующего контракта |
|---|---|---|
| Кадр, геометрия | `AcceptedFrameEnvelope`, `CameraCoordinateSpaceV2`, geometry в `CameraAnalysisDomainContracts.swift` | Явная привязка каждого региона к кадру и преобразованию |
| Главная цель и tracking | `SubjectResolver`, `SubjectTracker`, `SubjectTrackIdentity`, `SubjectResolutionContracts.swift` | Несколько независимых предметов и группы; одна authority идентичности |
| Evidence | `FrameFeatureSnapshot`, `SceneSemanticsReport`, `AnalysisPipeline`, VLM contracts `25` | Наблюдения и отношения с несколькими концами; временной scope |
| Допуск и выбор | `CameraAdviceSafetyGate`, `CameraBoundedActionPlanner`, `AdviceStabilizer` | Допуск проверяется для каждого кандидата, одно активное действие |
| Текст и overlay | `SemanticTipPlanner`, существующие presentation/trace owners | Проекция принятого решения, без второго независимого ранжирования |
| Эпизод и результат | `CoachingEpisodeCoordinator`, `UserMovementObserver`, `ActionVerifier` | Привязка к изменяемому предмету и защищаемой цели; action-specific сравнимость |
| Нейросеть | `ml/camera_coach/contracts/set_composition_net_v1.json` | Остаётся отдельным числовым evidence-контрактом; tensor order не менять |

Baseline: HEAD `0733df2cb83c8e3687c31251e11e5d0747052602`, `store`, с незакоммиченными research/docs предыдущих этапов. Главная release-authority — [master plan v2](../aegis/work/2026-09-03-gpt-5-6-pro-guidance/SET_OS_APP_STORE_1_0_CODEX_MASTER_PLAN_v2.md), §§3.1, 6.3, 7, 9. Исторические каталоги `03/24/25/26` не выше этой authority.

### N2. Конвенции типов и единиц

Далее описан нормативный логический формат draft, а не готовые Swift structs. Поля без `?` обязательны; optional-поле отсутствует, когда неизвестно, а не заполняется нулём/пустым ID. Для явно неизвестных результатов используется `status=unknown` с причиной. Списки могут быть пустыми только по указанным правилам. Неизвестные enum, поля и неподдерживаемая точная версия отвергаются на границе draft; расширение требует новой версии и явного допуска consumer.

- `ID`: непустой непрозрачный локальный идентификатор, уникальный внутри соответствующего envelope/session; без имён людей, путей, email и внешних URL.
- Числа конечны. Confidence находится в `[0,1]`, но score поставщика не означает калиброванную вероятность. Некорректные внешние значения отвергаются; clamping не превращает плохой payload в правильный.
- `Rect`: `{x,y,width,height}`, начало сверху слева, X вправо, Y вниз; `width,height>0`, весь прямоугольник внутри `[0,1]²`. Неизвестный/полностью невидимый объект не получает нулевой Rect.
- `Region`: `{frameRef, space:oriented_frame|preview|output, transformRef, rect}`. `oriented_frame` — полный ориентированный растр источника с явно указанной зеркальностью. `preview` и `output` имеют отдельные crop/transform; sensor/Vision/model coordinates сначала конвертируются владельцем геометрии.
- `Transform`: `{id, sourceFrameRef, destinationSpace, sourcePixelSize, destinationPixelSize, matrix3x3, orientation, mirrored, validSourceRect, preprocessingVersion}`. Матрица переводит нормализованные координаты исходного ориентированного растра в указанное пространство; finite, invertible для используемой области. Обрезанный/невидимый target блокируется, а не прижимается к краю. `matrix3x3` не является оценкой глубины.
- `MediaTime`: `{value,timescale}` — целые значения по семантике CMTime, `timescale>0`; сериализация `value` как десятичной строки Int64 без потери точности. В live порядок задаёт PTS одной session, в файле — timeline одного asset. UTC используется для журнала, не для упорядочения кадров.
- `Measure`: `{metricID, value, unit, policyVersion}`. Происхождение задаёт содержащая запись Evidence; measurement не ссылается на самого себя. Единица фиксирована registry: `normalized_ratio`, `degrees`, `seconds`, `pixels`, `ev`, `kelvin`, `meters` или `boolean`; value — конечное число, а для boolean — Bool, не число 0/1. Порог/направление улучшения берётся из квалифицированной политики данной метрики, не из ответа VLM.

### N3. Envelope и цель пользователя

```text
CameraCoachAnalysis
  schemaVersion = camera-coach.domain.v3-draft.1
  catalogVersion: ID
  policyVersion: ID
  analysisID: ID
  context: AnalysisContext
  intent: CaptureIntent
  entities: Entity[]
  evidence: Evidence[]
  relations: Relation[]
  findings: Finding[]
  decision: CoachDecision
  review: ReviewReport?
```

| Тип | Обязательное содержание и инварианты |
|---|---|
| `AnalysisContext` | `sessionID`, `generation`, `sceneID`, `intentRevision`, `mediaKind:photo\|video`, `phase:setup\|preview\|recording\|review`, `sourceKind:live_capture\|selected_asset`, `frames:FrameRef[]`, `anchorFrameRef`, `transforms:Transform[]`, `coverage:Coverage`. Для selected_asset обязателен `assetID`; live не содержит assetID. `generation` меняется на смене камеры/линзы/orientation/route; frame list непустой |
| `FrameRef` | `id`, `pixelSize`, `orientation`, `mirrored`, `contentRevision`; `pts:MediaTime` обязателен для video/live, отсутствует у отдельного фото; `captureMetadataRef?` указывает на M-evidence этого кадра. `contentRevision` связывает конкретную обработанную версию пикселей, а не только имя файла |
| `Coverage` | `kind:single_frame\|sampled_frames\|continuous_interval`, `frameRefs`, `examinedInterval?`, `maxSampleGap?`, `sourceDuration?`. Для video-интервала начало/конец включают все frameRefs на одной timeline; max gap измерен из PTS. `continuous_interval` означает coverage квалифицированного временного extractor, а не гарантию, что сеть посмотрела каждый пиксель всех кадров. Общий вывод не распространяется на непроверенные интервалы |
| `CaptureIntent` | `selection:unknown\|automatic\|user\|group`, `subjectRefs:ID[]`, `styles:(natural\|silhouette\|low_key\|symmetry\|negative_space\|dutch_angle\|intentional_motion_blur\|handheld)[]`, `constraints:UserConstraint[]`, `output:OutputIntent?`. Пустой styles означает неизвестное намерение; несколько явно выбранных стилей сохраняются вместе. При unknown subjects пусты; group содержит не менее двух членов. Смена выбора/стиля/ограничений увеличивает intentRevision |
| `UserConstraint` | `kind:do_not_move\|do_not_remove\|preserve_light\|preserve_region\|unavailable_resource`, `entityRef?`, `region?`, `resourceID?`; ровно тот target, который нужен kind. Именованный ресурс — только `additional_light\|tripod\|reflector`. Ограничение устанавливает пользователь, VLM не может снять его |
| `OutputIntent` | `aspectRatio`, `crop:Region`, `reservedRegions:Region[]`; `crop.space=oriented_frame` задаёт конечную область исходного кадра, reservedRegions находятся в output coordinates. Всё относится к одной версии output transform; смена output увеличивает intentRevision |

Для выбора предпочтительной стороны упаковки или стилевого нюанса вне enum пользователь указывает защищаемую область/субъект; расширение стилей не выполняется произвольной строкой VLM. Формат, стиль и физическая перестановка могут быть неизвестны: это ограничивает советы, но не блокирует независимые локальные проверки.

Все frameRefs внутри analysis резолвятся в context.frames; coverage.frameRefs — уникальное подмножество этих кадров в PTS-порядке, anchor входит в него. Жёсткие пределы размеров коллекций и текста задаёт обязательный локальный policyVersion; payload сверх лимита отвергается до планирования, а не обрезается с потерей ссылок. У group subjectRefs перечисляют членов; Entity kind=group может использоваться как агрегатный target, но не подменяет список защищаемых членов.

### N4. Сущности: наблюдение отдельно от идентичности

```text
Entity
  entityID: ID
  kind: person | face | object | group | background_region | light_region | unknown
  roles: (primary_subject | secondary_subject | prop | foreground | background | light_source)[]
  observations: {frameRef, region, visibility:visible|partial, evidenceRefs}[]
  track: {trackID, generation, firstFrameRef, status:active|ambiguous|lost}?
  display: {labelID, vocabularyVersion, evidenceRefs}
  groupMemberRefs: ID[]?
  manipulation: unknown | user_allowed | user_forbidden
```

`entityID` действует внутри analysis; `trackID` выдаётся только локальным владельцем tracking и живёт в пределах session/generation. Ссылки действия резолвятся к entityID, эпизод замораживает соответствующий track tuple. Детектор и VLM не назначают устойчивый trackID. Для независимых stills наличие одинаковой подписи «лампа» не устанавливает одну физическую лампу.

Наблюдения visible/partial содержат положительную валидную область на конкретном кадре. У lost track текущая область отсутствует; прошлые observations не становятся текущими. Group имеет groupMemberRefs, остальные kinds — нет; граф членства без циклов. Face связывается с person через `part_of`; лицо не считается вторым независимым участником группы.

Label допускается только из versioned safe vocabulary. Начальный предметный словарь переиспользует `24`: цветок, ваза, книга, чашка, бутылка, лампа, стул, телефон; остальные — generic labels с подсвеченной областью. Новые слова добавляются в словарь с evidence, а не становятся новыми действиями. Различие «левая/правая» формируется по показанному кадру; при перестановке местами trackID сохраняет объект, а не координату. Reflection — relation, не автоматически физически перемещаемая сущность.

`user_allowed` разрешает рассматривать перестановку, но не удостоверяет электрическую/температурную безопасность предмета или свободное место назначения. При unknown допустим вопрос/условное предложение в review; активная физическая перестановка требует подтверждения применимости. Экранное reframe этого разрешения не требует.

### N5. Evidence, отношения и выводы

| Тип | Содержание |
|---|---|
| `Evidence` | `id`, `kind:G\|A\|T\|M\|D\|U`, `source:vision\|geometry\|local_model\|vlm\|camera_metadata\|user`, `producerVersion`, `frameRefs`, `entityRefs`, `status:observed\|hypothesis\|unknown`, `reasonCode?`, `measurements:Measure[]`, `providerConfidence?`, `calibrationRef?`, `requestID?`. Unknown требует reasonCode и пустые measurements; calibratedRef — локальная policy, не заверение поставщика. User evidence допускает отсутствие frameRefs только для session-intent |
| `Relation` | `id`, `type`, `sourceEntityRef`, `targetEntityRef`, `frameRefs`, `evidenceRefs`, `status:observed\|hypothesis`. Оба конца обязательны, различны и существуют. Фон с отношениями представлен отдельной областью, а не nil с неизвестным смыслом |
| `Finding` | `id`, `polarity:issue\|strength\|uncertain`, `caseRefs:CC-*[]`, `entityRefs`, `relationRefs`, `evidenceRefs`, `severity:low\|medium\|high`, `interpretation:observed\|hypothesis`, `protectedByIntent:boolean`. CaseRefs не заменяют evidence; uncertain не превращается в strength |

Закрытые relation types draft: `overlaps_2d`, `contour_tangent_2d`, `occludes_visible_region`, `competes_for_attention`, `separated_2d`, `in_front_of_3d`, `behind_3d`, `illuminates`, `reflects`, `part_of`, `same_subject_across_media`.

2D overlap прямоугольников не доказывает occlusion контуров: `occludes_visible_region` требует соответствующего визуального evidence. `in_front_of_3d/behind_3d` требуют D; `illuminates` без подтверждения остаётся гипотезой. `same_subject_across_media` требует подтверждённого сопоставления и не является биометрической идентификацией; неизвестность запрещает автоматический до/после verdict.

Measure.metricID приходит из локального registry. Начальный набор для расширения: `target_distance`, `edge_clearance`, `subject_area_ratio`, `contour_gap`, `visible_fraction`, `horizon_error`, `subject_readability`, `subject_clipped_ratio`, `hotspot_ratio`, `focus_readability`, `motion_shake`, `tracking_zone_error`, `motion_jerk`, `flicker_amplitude`, `exposure_variation`, `white_balance_variation`, `endpoint_hold_duration`, `reserved_region_overlap`, `human_preference`. Где существуют текущие аналогичные метрики, использовать их владельца и явно сопоставить единицы. `human_preference` никогда не измеряется VLM.

Не создаётся универсальный числовой «процент красоты». Порог, минимальная длина окна и допустимый gap каждой T-метрики фиксируются в versioned policy при её квалификации; до этого соответствующий T-case не даёт production-совет. Разреженные ключевые кадры могут подтвердить положение объекта в этих кадрах, но не отсутствие мерцания/рывков между ними.

M-evidence может дополнительно содержать `capture:CaptureMetadata`: `deviceLensID`, `zoomFactor`, `exposureBiasEV`, `exposureSettled`, `focusSettled`, `whiteBalanceKelvin`, `shutterSeconds`, `supportedParameters`, `availableLensIDs`, `parameterRanges` — каждое значение optional, кроме реально проверенных списков возможностей, которые могут быть пустыми. В M с unknown status capture отсутствует. Диапазоны содержат parameter/min/max/unit; единицы совпадают с N6.1. Наличие поля «не поддерживается» отличается от отсутствия сведений. D-evidence для measured spatial guidance включает измеренную `distance_meters`/`relative_depth_meters` и систему отсчёта, внесённые в тот же qualified registry. User evidence отсылается к CaptureIntent/constraints этой intentRevision; поставщик не объявляет своё предположение пользовательским выбором.

### N6. Решение, действие и цель

```text
CoachDecision
  state: KEEP | CORRECT | SELECT_SUBJECT | WAIT | ABSTAIN
  anchorFrameRef: ID
  reasonCodes: ReasonCode[]
  findingRefs: ID[]
  activeAction: Action?
  selectionCandidates: ID[]

Action
  actionID: ID
  operation: Operation
  executor: camera_operator | subject_participant | scene_arranger
  targetRefs: ID[]
  protectedRefs: ID[]
  findingRefs: ID[]
  evidenceRefs: ID[]
  payload: operation-specific typed value
  effectGoal: EffectGoal
  qualificationRef: ID
  scope: now | next_capture
  baseline: {analysisID, sessionID, generation, sceneID, intentRevision, frameRef, trackBindings}
  verification: VerificationSpec
  presentation: {templateID, targetLabelRefs, highlightRegions, goalRegion?}
```

CORRECT содержит ровно одно activeAction; остальные состояния — ни одного. SELECT_SUBJECT имеет непустые реальные selectionCandidates, прочие состояния — пустой список. Если цель не найдена, сообщать ABSTAIN/no_subject, не показывать пустой выбор. KEEP требует положительных evidence по выбранной цели и отсутствия активного запрещающего условия. WAIT применяется только к временно устранимому ожиданию, ABSTAIN — к неподдержанному/недостаточному сигналу. Закрытые ReasonCode: `ready`, `correction_available`, `ambiguous_subject`, `no_subject`, `acquiring`, `unstable`, `stale`, `identity_lost`, `unsupported_case`, `unqualified`, `missing_evidence`, `conflicting_evidence`, `protected_intent`, `infeasible`, `network_unavailable`, `quota_exhausted`, `invalid_payload`, `scope_changed`.

EffectGoal — наблюдаемая цель: `{metricID, targetEntityRefs, relationRef?, desired:increase|decrease|inside_region|preserve, targetRegion?, policyRef}`. Для inside_region targetRegion обязателен, иначе отсутствует. EffectGoal не кодирует физическую причину и не даёт permission. Цель «увеличить зазор между лампой и головой» не равна «увеличить confidence модели».

#### N6.1. Закрытые операции draft и payload

Операции — параметризованные смысловые семейства. Это проект нового каталога, без автоматического добавления значений в существующий `SemanticActionType`.

| Operation | Payload и цель | Исполнитель / допустимый режим |
|---|---|---|
| `reframe_subject` | `{targetRegion:Region}` для selected subject/group; экранная цель, без направления перемещения камеры | camera_operator; setup/preview, review→next_capture |
| `change_subject_scale` | `{method:camera_distance\|zoom, desired:larger\|smaller, targetAreaRatio}`; ratio `(0,1]`, метод известен; M для zoom | camera_operator; setup/preview, review→next_capture |
| `level_frame` | `{rotation:clockwise\|counterclockwise, targetHorizonDegrees}` относительно preview, с horizon evidence | camera_operator; setup/preview, review→next_capture |
| `reposition_entity` | `{destination:screen_goal\|relative_depth, region?, relationRef?}`; screen_goal требует region и фиксированной камеры; relative_depth требует D relationRef и определённой точки отсчёта | scene_arranger для object, subject_participant для person; setup/стабильный preview, review→next_capture |
| `rotate_entity` | `{towardEntityRef?, revealRegion?, turn:small_probe\|measured, angleDegrees?}`; ровно один toward/reveal; measured требует D+angle, small_probe запрещает число | scene_arranger/subject_participant; setup/стабильный preview, review→next_capture |
| `exclude_entity` | `{fromRegion:Region}`; физически убрать только выбранный доступный предмет, не генеративное удаление | scene_arranger; setup/стабильный preview, review→next_capture |
| `reposition_camera` | `{change:raise\|lower\|lateral_probe, lateralDirection:left\|right?, goalRegion:Region, step:small_probe}`; lateralDirection обязателен только для lateral_probe и означает физическое перемещение в системе камеры. Он требует квалифицированной пространственной геометрии; одной экранной цели недостаточно для выбора физической стороны | camera_operator; setup/стабильный preview, review→next_capture |
| `adjust_light` | `{change:dim\|brighten\|switch_off\|add_fill\|add_background, sourceEntityRef?, receiverEntityRef}`; dim/brighten/switch_off требуют sourceRef, add требует подтверждённого ресурса | scene_arranger; setup/стабильный preview, review→next_capture |
| `adjust_exposure` | `{change:increase\|decrease, parameter:exposure_bias, suggestedEV?}`; число только из доступного диапазона M и qualified policy | camera_operator; setup/preview, review→next_capture |
| `refocus_subject` | `{focusRegion:Region}` на selected subject; M/focus evidence | camera_operator; setup/preview, review→next_capture |
| `hold_steady` | `{windowPolicyRef}`; уменьшить непреднамеренное движение в измеренном окне | camera_operator; setup/preview/recording, review→next_capture |
| `set_capture_parameter` | `{parameter:exposure_lock\|focus_lock\|white_balance_lock\|white_balance_kelvin\|shutter_seconds, value:boolean\|number}`; boolean только locks; иначе положительное число в M диапазоне, предикат определяет единицу | camera_operator; setup/preview, review→next_capture |
| `change_lens` | `{deviceLensID}` из фактически discovered hardware; смена линзы завершает эпизод как incomparable | camera_operator; setup/preview, review→next_capture |
| `reserve_output_region` | `{region:Region}` в output space по выбранному шаблону, связанная экранная цель для субъекта | camera_operator; setup/preview, review→next_capture |
| `wait_for_clearance` | `{region:Region, blockerRefs:ID[]}`; цель/блокер различны, T для освобождения | camera_operator; setup/preview, review→next_capture |
| `select_capture_moment` | `{frameRef}` из просмотренной серии; предложение выбрать/переснять момент, без автоспуска | camera_operator; review; отдельный выбранный снимок, не смена текущей live-сцены |
| `maintain_subject_zone` | `{region:Region, windowPolicyRef}`; неизменная целевая зона на интервале | camera_operator; video preview/recording, review→next_capture |
| `smooth_camera_motion` | `{windowPolicyRef}`; уменьшить рывки, сохранив выбранное движение | camera_operator; video preview/recording, review→next_capture |
| `plan_motion_endpoints` | `{startFrameRef, endFrameRef, holdPolicyRef}` из реальной репетиции/выбора; не создаёт невидимый маршрут | camera_operator; video setup, review→next_capture |
| `clear_lens_obstruction` | `{obstructionRegion:Region}` для подтверждённого пальца/чехла у объектива; только освободить оптический путь, без диагноза загрязнения и команды чистить линзу | camera_operator; setup/preview, review→next_capture |

targetRefs для single-object операций содержит ровно один object/person; для reframe/group/maintain допускается выбранная группа. Frame-global level/hold/clear_lens_obstruction могут иметь пустой targetRefs, но тогда обязателен непустой findingRefs с frame evidence. `protectedRefs` фиксирует главного субъекта и важные второстепенные цели, даже если двигать надо лампу. Все payload entity/frame/region references резолвятся в baseline context; ресурс/функция устройства проверяется отдельно.

`qualificationRef` ссылается на локально установленную policy допуска именно operation × case × mode × device/evidence profile. Она содержит калибровку, prerequisites, обязательные измерения, guardrails, registry templates и поддерживаемый verifier. Запись research/unqualified может существовать для анализа, но не порождает production CORRECT. VLM не выдаёт qualificationRef.

Для физической перестановки предусловие feasibility включает доступность предмета и допустимость места назначения на подтверждённой поверхности. Свободный прямоугольник в изображении не доказывает наличие опоры или свободного прохода; в таком случае нужен ввод пользователя/дополнительный сигнал, либо review proposal без исполнительной стрелки. Точный пространственный совет никогда не выводится только из label предмета.

#### N6.2. Review, альтернативы и сборка текста

`ReviewReport` содержит `coverage`, `findingRefs`, `suggestions:ActionProposal[0...3]`, `comparisons:MediaComparison[]`. Это разбор выбранного материала; он не открывает live-эпизод. `ActionProposal` сохраняет поля Action, кроме baseline; добавляет `admissibility:qualified|needs_user_input|unsupported`, `reasonCodes`, `alternativeGroupID?`. qualificationRef обязателен только при qualified; у остальных отсутствует. scope=next_capture, кроме select_capture_moment, у которого scope=now означает выбор просмотренного снимка. До допуска это гипотеза с условным текстом без исполнительной стрелки. В future live проецируется только qualified proposal после повторного анализа актуального кадра. Если context.phase=review, decision.activeAction отсутствует: findings/suggestions/comparisons находятся в ReviewReport, state=KEEP при положительном подтверждении, иначе ABSTAIN с соответствующей причиной; review не маскируется под live CORRECT.

Несовместимые предложения получают один `alternativeGroupID?`; альтернативы не выводятся как последовательные шаги. Упорядоченный список — план обсуждения, не очередь автодействий: после любого действия новый анализ. В setup/preview подробный список показывается только при явном открытии разбора неподвижного кадра; в recording review не перекрывает запись.

`MediaComparison` содержит `sourceAnalysisRefs`, `findingRefs`, `subjectMapping:Relation[]`, `preference:first|second|equal|undetermined`, `basis:technical|human`, `evidenceRefs`, `coverage`. `sourceAnalysisRefs` ссылаются на отдельные доступные analyses; их ID/frames не смешиваются с локальными. Technical preference относится только к названным метрикам; эстетическое «лучше» требует human basis. Different scene без сопоставимого намерения → undetermined.

Текст и VoiceOver строятся по локальному templateID и безопасным меткам того же Action. Overlay указывает изменяемый предмет и цель, а protectedRefs объясняют, ради чего изменение. В запись не добавляются голосовые команды по умолчанию. «Почему?» содержит finding → observation/relation → evidence, краткую причину и границы уверенности; сырой prompt/free prose не заменяет эту цепочку.

### N7. Эпизод и честная проверка результата

Существующие этапы coordinator сохраняются: `idle → awaiting_movement → collecting_stable_after_frames → ready_for_verification`, с `cancelled/expired`. Расширение наблюдения допускает `action_relevant_change` параметра/света или освобождение области вместо обязательной физической трансляции; этот event принадлежит UserMovementObserver, не сообщению «готово» от пользователя. Для удержания движения оценивается временное окно, для review-only select_capture_moment live-эпизод не создаётся.

```text
VerificationSpec
  kind: objective | user_assessed
  metricIDs: ID[]
  policyRef: ID
  protectedEntityRefs: ID[]
  requiredTrackBindings: {entityRef, trackID, generation}[]
  comparability: same_capture | matched_media
  expectedAbsenceRefs: ID[]
  allowedChanges: (target_position | target_rotation | camera_pose | zoom |
                   exposure_bias | light_state | focus | capture_parameter)[]

VerificationResult
  actionID: ID
  outcome: improved | unchanged | worse | incomparable
  reasonCode: verified | no_effect | regression | missing_evidence | identity_changed |
              scene_changed | context_changed | metric_unqualified | unsupported_verifier
  beforeAnalysisRef: ID
  afterAnalysisRef: ID
  measurements: {metricID, before, after, unit, policyRef}[]
  assessmentSource: local_verifier | user
  goalSatisfied: boolean?
```

Политика сравнения по порядку:

1. Проверить scope/time/generation, identity выбранной цели **и изменяемого предмета**, необходимый sampling, качество signals и версии метрик. Для exclude_entity только перечисленные expectedAbsenceRefs могут отсутствовать в after-frame по специальному правилу ниже; у остальных операций этот список пуст. Нарушение → incomparable, даже если скаляр вырос. Дубликат after-frame не новое наблюдение.
2. Убедиться, что не изменились intent/output, запрещённые settings, не возник scene cut. `allowedChanges` разрешает только изменения, которые конкретный verifier умеет учитывать; список не отключает provenance guards. Zoom/camera pose/свет сравниваются только специальным qualified verifier, а не обходом старого transform-equality guard.
3. Если сравнимость установлена и нарушен protected guardrail → worse. Увеличение зазора не улучшение, если лицо обрезалось. При отсутствующем guardrail evidence → incomparable, не success.
4. При положительном изменении выше квалифицированного deadband → improved; отрицательном → worse; иначе unchanged. `goalSatisfied` отвечает, достигнут ли критерий, отдельно от наличия частичного улучшения. При incomparable поле отсутствует.
5. `user_assessed` сохраняет явно введённую оценку с assessmentSource=user. Она не становится объективной автоматической проверкой, калибровкой или human-gold голосом. Если автоматического verifier нет, показывается запрос оценки в review, а не автоматическое «стало лучше».

`same_capture` требует стабильной session/generation/intent, согласованных преобразований и track bindings. `matched_media` доступен только в review с явным mapping выбранных материалов; это не основание продолжать live-эпизод после потери tracking. Смена линзы/orientation/route/background отменяет текущий эпизод; следующий начинается с новой baseline. Для exclude_entity expectedAbsenceRefs равны targetRefs: baseline track должен существовать и быть наблюдён до выхода из нужной области, protected tracks сохраняются, свободная область подтверждена после движения и нет необъяснённой потери ассоциации. Просто ненайденный детектором предмет не считается удалённым. Без этого специального evidence результат incomparable.

SceneID обозначает устойчивый контекст сцены, а не hash пикселей или геометрии всех предметов. Ожидаемое перемещение лампы не должно автоматически считаться scene cut; неизвестная непрерывность не должна автоматически считаться той же сценой. Это обязательная точка интеграции с текущим sceneSignature/coordinator, а не разрешение ослабить существующие guards.

### N8. Provider contract: VLM предлагает evidence, приложение принимает решение

Следующий wire revision называется `camera-coach.vlm-evidence.s2-draft.1`; s1 остаётся неизменным. Полная исходная роль provider описана в [25](25-vlm-visual-semantic-evidence-contract.md); ниже delta.

Request содержит точные `schemaVersion, requestID, analysisID, sessionID, generation, sceneID, intentRevision, anchorFrameRef, catalogVersion, policyVersion, coverage`, deadline и допустимые каталоги. Visual attachments — только связанные с frameRef обработанные версии изображений с transform/coverage; opaque attachmentRef выдан транспортом, не URL модели. Policy определяет лимиты bytes/pixels/frames/entities/observations/relations/output tokens и время; запрос без обязательных лимитов не отправляется.

Response содержит тот же correlation tuple, `status:completed|refused|unavailable`, `entityProposals`, `evidenceProposals`, `relationProposals`, `actionProposals`, `uncertaintyReasons`. Ни final decision, ни activeAction, ни trackID, ни qualificationRef, ни verification outcome провайдер не возвращает. При refused/unavailable все proposals пусты, причина обязательна. Completed с пустыми proposals допустим как «не нашёл», но не как KEEP.

`entityProposal` содержит response-local proposalID, kind, labelCandidate из vocabulary, frameRef, Region и confidence/uncertainty. Relation/action proposal ссылается либо на существующий request entityRef, либо на proposalID с явным тегом пространства ссылки. Validator сначала проверяет геометрию и корреляцию; локальный grounding owner принимает/отклоняет proposal и выдаёт entityID. Только после этого зависимые proposals могут перейти в локальное evidence. Совпадение confidence двух моделей само по себе не доказывает grounding; policy должна квалифицировать метод допуска. Не принятый endpoint удаляет все зависимые предложения.

Provider не может вернуть произвольный физический маршрут, значение камеры вне M, имя человека, новую operation, scalar threshold или исполняемый predicate. `structured_only` разрешает анализ только переданных фактов, без новых «увиденных» сущностей; redacted input не обосновывает выводы о скрытой области. Отсутствие нужной информации ведёт к abstention/условному review, не к снятию редактирования. Images и надписи внутри них — данные, не инструкции для planner/transport.

Для initial s2 transport поддерживается один ключевой кадр по явному запросу. Multi-frame video attachments требуют отдельно квалифицированного capability profile; неподдержанный clip не превращается в скрытую серию платных вызовов. Старый/повторный/отменённый ответ не влияет на текущий decision. На сервере identity/idempotency/quota проверяются до платного вызова; таймаут клиента не считается доказательством отмены/неоплаты вызова у провайдера.

Новый домен не разрешает сеть автоматически. Release camera egress остаётся закрытым до отдельного обновления master-plan/privacy/provider-контракта. Конкретный поставщик не зашит в schema; это не обязанность писать несколько provider adapters.

### N9. Покрытие 68 сценариев: действие и критерий

Здесь `selection`, `evidence_only`, `review_compare`, `feedback`, `state_only` — поведение домена, а не Operation. Если prerequisites отсутствуют, действует N6, а не обязательная коррекция. Полные ограничения каждого случая сохраняются в требованиях §23.4.

| Case | Основная операция/поведение | Основной predicate/результат |
|---|---|---|
| CC-I01 | selection | user intent и стабильная цель |
| CC-I02 | reframe_subject | group visible_fraction + edge_clearance всех членов |
| CC-I03 | evidence_only | роль подтверждена, манипуляция соответствует роли |
| CC-I04 | reframe_subject / wait_for_clearance | UserConstraint соблюдён |
| CC-I05 | state_only | protected_intent, сохранён стиль |
| CC-I06 | selection / state_only | safe label и валидный регион либо ABSTAIN |
| CC-C01 | reframe_subject | edge_clearance |
| CC-C02 | change_subject_scale | subject_area_ratio |
| CC-C03 | reframe_subject | target_distance к зоне с пространством взгляда/движения |
| CC-C04 | reframe_subject | target_distance; human_preference при субъективном акценте |
| CC-C05 | reframe_subject | target_distance к выбранной симметрии |
| CC-C06 | level_frame | horizon_error |
| CC-C07 | reposition_camera | visible_fraction выбранной поверхности |
| CC-C08 | reposition_camera / change_subject_scale | human_preference + сохранение цели |
| CC-O01 | reposition_entity | contour_gap до защищённого лица |
| CC-O02 | reposition_entity | отдельный contour_gap/goal для каждого шага |
| CC-O03 | reposition_entity / reposition_camera | contour_gap |
| CC-O04 | exclude_entity | visible_fraction отвлекающего объекта и сохранность целей |
| CC-O05 | reposition_entity | contour_gap + visible_fraction обоих предметов |
| CC-O06 | reposition_entity | target_distance + human_preference |
| CC-O07 | reposition_entity / reposition_camera | subject_readability |
| CC-O08 | reposition_entity | subject_readability + подтверждённая depth relation |
| CC-L01 | rotate_entity / adjust_light | subject_readability + clipped guard |
| CC-L02 | adjust_light | hotspot_ratio + readability guard |
| CC-L03 | adjust_exposure | subject_clipped_ratio + readability guard |
| CC-L04 | reposition_entity / adjust_light | subject_readability + intent |
| CC-L05 | rotate_entity | hotspot_ratio в защищённой области |
| CC-L06 | reposition_entity | subject_readability после пробного изменения света |
| CC-L07 | adjust_light / set_capture_parameter | human_preference по выбранному цветовому ориентиру |
| CC-L08 | adjust_light | subject_readability + human_preference |
| CC-P01 | reposition_entity | visible_fraction всех выбранных лиц |
| CC-P02 | rotate_entity | visible_fraction нужной области + intent |
| CC-P03 | reposition_entity | visible_fraction лица/действия |
| CC-P04 | reposition_entity / adjust_light | subject_readability всей группы |
| CC-P05 | select_capture_moment | visible_fraction глаз; единичное фото только review finding о закрытых глазах |
| CC-P06 | reframe_subject | selected regions + human_preference |
| CC-S01 | rotate_entity | visible_fraction выбранной стороны |
| CC-S02 | reposition_camera | visible_fraction деталей + intent |
| CC-S03 | reposition_camera | contour_gap + protected geometry |
| CC-S04 | reframe_subject | visible_fraction выбранного переднего плана |
| CC-S05 | reframe_subject | edge_clearance верха здания |
| CC-S06 | wait_for_clearance | visible_fraction цели после ухода blocker |
| CC-S07 | reframe_subject / exclude_entity | edge_clearance / contour_gap, по одному шагу |
| CC-S08 | change_subject_scale | subject_area_ratio и корректный mirrored transform |
| CC-T01 | refocus_subject | focus_readability |
| CC-T02 | hold_steady | motion_shake + focus_readability |
| CC-T03 | adjust_light | subject_readability при сопоставимых настройках |
| CC-T04 | change_subject_scale / change_lens | readability; lens switch → incomparable live, новый baseline |
| CC-T05 | adjust_light / set_capture_parameter | flicker_amplitude на T-интервале |
| CC-T06 | clear_lens_obstruction | visible_fraction перекрытия/цели; без диагноза грязи |
| CC-V01 | maintain_subject_zone | tracking_zone_error |
| CC-V02 | smooth_camera_motion | motion_jerk + protected intent |
| CC-V03 | hold_steady | motion_shake на интервале |
| CC-V04 | set_capture_parameter | exposure/white_balance_variation или focus_readability |
| CC-V05 | plan_motion_endpoints | endpoint_hold_duration + target framing |
| CC-V06 | plan_motion_endpoints / reposition_camera | subject_readability/visible_fraction на повторной репетиции |
| CC-V07 | review_compare | relations между реальными выбранными планами, intent |
| CC-V08 | evidence_only | явный временной scope finding |
| CC-F01 | reframe_subject | target_distance внутри output crop |
| CC-F02 | reserve_output_region | reserved_region_overlap |
| CC-F03 | квалифицированная операция для обнаруженной проблемы | next_capture scope, исходный файл не изменён |
| CC-F04 | review_compare | сопоставимые intent/цели и technical/human basis |
| CC-R01 | state_only | положительные qualified evidence → KEEP |
| CC-R02 | state_only | WAIT/SELECT_SUBJECT/ABSTAIN и удаление stale overlay |
| CC-R03 | state_only | veto конфликтующего action до ранжирования |
| CC-R04 | feedback | VerificationResult с provenance и goalSatisfied |
| CC-R05 | feedback | UserConstraint + новая intentRevision |
| CC-R06 | state_only | локальный доступный decision, отдельный статус cloud request |

CC-T06 отделён от exclude_entity: освобождение объектива относится к оператору и оптическому пути, а не к перестановке реквизита. Неподтверждённая «грязная линза» не допускается ни этой операцией, ни generic cleanup. Конкретный экспертный совет без готового qualified predicate остаётся review proposal, не production CORRECT.

### N10. Разобранные примеры и негативные ветви

Ниже смысловые проекции записей, не полный wire JSON и не тестовые fixtures.

**Две лампы.** analysis `a1`, session `s1`, generation `1`, intentRevision `1`: entity `person1`, `lampA`, `lampB`; track bindings соответственно `tp`, `ta`, `tb`. Finding `f1` связывает relation `contour_tangent_2d(lampA,person1)` с подтверждёнными областями. Action `moveA`: `reposition_entity`, executor `scene_arranger`, targetRefs `[lampA]`, protectedRefs `[person1,lampB]`, destination `screen_goal` справа от текущей lampA, EffectGoal `contour_gap/increase`, objective verification с фиксированной камерой. Presentation выделяет lampA; entityID главного человека не подменяет target действия.

После пользовательского подтверждения применимости и квалифицированного допуска activeAction замораживается. Observer подтверждает изменение именно track `ta`; after-analysis `a2` содержит те же tracks. Если зазор вырос и guardrails соблюдены, improved; если цель достигнута, goalSatisfied=true. Следующий совет lampB формируется по `a2`, с новым actionID и baseline. При движении только `tb` первый шаг не завершается. При обмене trackID, смене crop, переносе телефона без допустимой компенсации или неоднозначной ассоциации → incomparable.

**Хороший силуэт.** intent.styles содержит silhouette; darkness finding защищён intent. KEEP возможен только при других достаточных положительных проверках, иначе ABSTAIN/protected_intent. Автоматическое add_fill запрещено.

**Проводка видео.** coverage содержит квалифицированное временное окно с реальными PTS. `maintain_subject_zone` сохраняет одну цель, preview transform и track; completion оценивает tracking_zone_error на окне. Один кадр внутри зоны не завершает эпизод. Scene cut/track loss отменяет текущую подсказку; облачный ответ на старый кадр не восстанавливает её.

**Блик на стекле.** observed hotspot + hypothesis о направлении света → review proposal rotate_entity/small_probe; нет exact angle. При qualified predicate и подтверждённой применимости можно активировать ограниченное действие; verifier сравнивает hotspot в защищённой области, а не уверенность того же VLM в своём совете.

**Граница inputs.** Неизвестная operation, NaN, Region с отрицательной шириной, ссылка на несуществующий endpoint или response другой intentRevision отвергаются. Ответ valid JSON без qualifiers не доходит до CORRECT. Внешний payload никогда не изменяет текущий subject selection или ограничения пользователя.

### N11. Совместимость и обязательные интеграционные решения

| Текущая поверхность | Правило перехода |
|---|---|
| `KEEP/CORRECT/SELECT_SUBJECT/WAIT/ABSTAIN` | Сохраняются значения; новая структура действия требует отдельного decoder/version, не подставляется в v2 payload |
| `place_subject_*` из master plan | Проектируются в reframe_subject с вычисленной экранной целью; физическое направление камеры из строки не выводится |
| 26 utility labels в SETCompositionNet | Индексы/имена/hash неизменны. Допускается только явное сопоставление evidence с новым кандидатом при наличии targets, calibrated policy и verifier. `move_object_*` logit без region/track не создаёт предмет |
| `shift_frame_*`, `step_*`, `move_object_*`, `change_camera_angle` в старой runtime taxonomy | Не переименовывать массово. Каждый переход проверяет смысл и координаты; vague angle/simplify без цели отклоняется. Старый raw string недостаточен для v3 Action |
| `targetEntityRef` s1 frame-local | Привязывается к entityID конкретного analysis; никогда не становится trackID без tracking evidence |
| M2 geometry vs ML preprocessing | `CameraCoordinateSpaceV2.modelInput` описан как aspect-fill, ML v1 preprocessing — independent scale. Нельзя молча использовать одно преобразование для обоих; соответствие доказывается по actual tensor recipe/crop/orientation, иначе geometry-dependent результат отклоняется |
| Existing ActionVerifier | Текущие сравнимость/transform/calibration guards остаются; новые операции требуют поддержанного verifier. Неизвестная operation → incomparable/unsupported_verifier |
| Existing planner и SemanticTipPlanner | Финальный decision один. Presentation не выбирает второе действие из сырого VLM/legacy score; новые targets не теряются при проекции |
| Current Stage-2 artifact | Research-only, три обученные головы. Не объявлять v3 моделью и не использовать untrained good/risk/abstention для допуска |
| Current recording/Photo/media | Новые сообщения не меняют capture/recording/persistence lifecycle. Анализ selected_asset не перезаписывает медиа и не запускает импорт всей библиотеки |

Особо проверить при реализации: `CameraCoachContractV2.production.approvedActionIDs` сейчас перечисляет все SemanticActionType, а master plan задаёт другой bounded operational catalog; это различие authority/representation требует явного mapping и аудита фактического пути допуска. Эта спецификация не исправляет код и не утверждает, что enum сам по себе открывает все действия в UI.

Version policy: draft меняется с увеличением suffix; stable v3 объявляется только после schema/Swift/Python conformance и конкретного action registry. Новая операция/поле/единица требует нового согласованного каталога или schema version; unknown version не downgrade-ится посредством угадывания. Документы `03` (домен), `24` (presentation), `25` (provider), `26` (fusion) сохраняют свои роли; существующие v1/v2 данные остаются читаемыми своими decoder. Автоматической миграции checkpoint/голов или старых gold-labels нет.

### N12. Готовность к реализации и проверка

Завершён текущий шаг: определены предметные типы, действия/цели, режимы, provenance, жизненный цикл, mapping всех 68 требований и совместимость. Это design deliverable, а не проверенная реализация схемы. Отсутствующие calibrated thresholds и provider qualification не заменяются числами из примеров.

Порядок дальнейших изменений: (1) машинная schema и типы для базового entity/action/evidence эпизода, (2) локальная identity/geometry и planner projection с двумя предметами, (3) episode/verifier, (4) VLM s2 только в разрешённом исследовательском режиме, (5) временные и review profiles. Расширять существующих владельцев; перед кодом согласовать qualified action registry и отдельно production границу облака. Изменение scope App Store 1.0 должно быть явным, а не побочным эффектом нового enum.

Самая узкая последующая conformance-проверка должна покрыть: отличимые две лампы и одинаковые labels; неверный endpoint; отрицательный/NaN region; portrait/landscape/mirroring/output crop; same-label track swap; неизвестную operation; stale response/intentRevision; qualified/unknown evidence; неизменившийся/ухудшившийся результат; защита лица при улучшенном зазоре; sampled-still без T; неизменность записи; research artifact без release admission. Это требования к будущей проверке, не созданные в этой задаче тесты.

Для полного релиза остаются human-gold данные/оценка полезности, калибровка, action-specific physical/runtime qualification и существующие M3/M4 gates. Смена контракта не закрывает их и не требует переобучать текущий Stage 2 до решения о новой модели.
