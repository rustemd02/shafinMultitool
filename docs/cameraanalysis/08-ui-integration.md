# 08. UI Integration (PR-009/PR-010/PR-011)

Статус: design spec + design verify addendum for `PR-S05` (source-of-truth)

Дата: 2026-04-20

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)
- [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md)
- [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md)
- [07-critique-engine.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/07-critique-engine.md)
- [camera-analysis-requirements-draft.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-requirements-draft.md)
- [camera-analysis-v1-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-v1-architecture.md)
- [CameraViewModel.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/ViewModels/CameraViewModel.swift)
- [AnalysisPipeline.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift)
- [OverlayView.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/UI/Overlay/OverlayView.swift)
- [SuggestionEngine.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/Multitool2Module/Services/Suggestion/SuggestionEngine.swift)

## Цель

Встроить новый critique/recommendation contract в `live` и `pause` UI так, чтобы:
- текущий camera flow не ломался;
- `SuggestionEngine` оставался рабочим fallback;
- UI не мерцал и не перегружал экран;
- переход от legacy `Suggestion` к structured `RecommendationPlan` происходил поэтапно.

Данный документ покрывает design scope для:
- `PR-009 Live Hint Adapter`;
- `PR-010 Pause Critique Card`;
- `PR-011 Overlay Annotations`.

## Текущее состояние (baseline)

Сейчас UI путь полностью legacy:
- `AnalysisPipeline` публикует `currentSuggestion: Suggestion?` и `overlayState`;
- `CameraViewModel` пробрасывает `suggestion` и `previewSuggestions`;
- `OverlayView` рендерит `SuggestionChipView`, `SuggestionListView`, `DirectionArrows` по `SuggestionType`;
- режим паузы показывает список эвристических советов, без `CritiqueReport/RecommendationPlan`.

Новые контракты (`CritiqueReport`, `RecommendationPlan`, `OverlayHint`) уже доступны в модели, но в UI path еще не подключены.

## Scope и ограничения

В scope:
- адаптация `AnalysisPipeline`/`CameraViewModel` для выдачи presentation-ready состояния;
- live hint на основе `RecommendationPlan.primaryAction`;
- expanded pause card на основе `CritiqueReport + RecommendationPlan`;
- overlay annotations из `RecommendationAction.overlayHint` и `targetRegion`;
- fallback на legacy suggestions.

Вне scope:
- перепроектирование domain contracts (`PR-002`);
- изменение critique taxonomy/rules (`PR-007`);
- LLM/provider слой (`PR-012/PR-013`);
- полный редизайн camera UI.

Ограничения:
- не ломать `start/stop`, pause toggle и current capture flow;
- минимизировать write scope за пределами `Multitool2Module` camera UI path;
- сохранить offline-first baseline.

## Target Presentation Model

UI не должен напрямую зависеть от internal rule keys. Нужен отдельный presentation слой:

```text
LiveHintPresentation
- id: String                         // stable id for anti-flicker transitions
- frameId: String
- text: String
- confidence: Double
- actionType: ActionTypeV1?
- actionId: String?                  // RecommendationAction.id (без remap)
- linkedIssueIds: [String]           // RecommendationAction.linkedIssueIds
- summaryId: String?                 // CritiqueSummary.id (для summary trace linkage)
- traceRootIds: [String]             // ExplainabilityTraceBundle.rootSummaryIds subset для live
- targetRegion: NormalizedRect?
- overlayHint: OverlayHint?
- isFallback: Bool

PauseCritiquePresentation
- frameId: String
- verdict: FrameVerdict
- summaryId: String                  // CritiqueSummary.id (без remap)
- shortVerdict: String
- whyGood: String?
- whyProblematic: String?
- strengths: [PauseStrengthRow]      // top 3
- issues: [PauseIssueRow]            // top 3 by severity
- actions: [PauseActionRow]          // 0...3; primary optional для good/no-action path
- noChangeRationale: String?
- assumptions: [String]              // semantics assumptions, compact form
- traceRootIds: [String]             // ExplainabilityTraceBundle.rootSummaryIds для pause drill-down
- fallbackUsed: Bool                 // degraded structured path marker; не означает hard legacy-only fallback

PauseStrengthRow
- strengthId: String                 // FrameStrength.id (без remap)
- type: StrengthTypeV1
- rationale: String
- confidence: Double
- supportingRegion: NormalizedRect?
- traceRefId: String?                // interpretation trace id, если доступен

PauseIssueRow
- issueId: String                    // FrameIssue.id (без remap)
- type: IssueTypeV1
- severity: Double
- confidence: Double
- rationale: String
- affectedRegion: NormalizedRect?
- suggestedFixTypes: [FixTypeV1]
- traceRefId: String?                // interpretation trace id, если доступен

PauseActionRow
- actionId: String                   // RecommendationAction.id (без remap)
- actionType: ActionTypeV1
- priority: Int
- linkedIssueIds: [String]
- expectedOutcome: String
- targetRegion: NormalizedRect?
- overlayHintId: String?             // OverlayHint.id для TraceLink(kind: overlay)
- traceRefId: String?                // recommendation trace id, если доступен

OverlayAnnotationPresentation
- id: String
- kind: OverlayKind
- direction: OverlayDirection?
- targetRegion: NormalizedRect?
- emphasis: Double                   // derived from confidence/severity
```

Annotation ID policy (обязательная):
- `OverlayAnnotationPresentation.id` всегда детерминирован и никогда не генерируется через UUID/random;
- `id` для `mode == live` не должен включать `frameId`;
- `id` для `mode == pause` может включать `frameId` (freeze-frame контекст);
- structured path (`mode == live`): `id = "ov_live_\(kind.rawValue)_\(direction?.rawValue ?? "none")_\(targetRegionQuantizedKey ?? "screen")_\(actionSemanticKey)"`;
- structured path (`mode == pause`): если есть валидный `overlayHint.id`, то `id = overlayHint.id`, иначе `id = "ov_pause_\(frameId)_\(actionId ?? "na")_\(kind.rawValue)_\(direction?.rawValue ?? "none")_\(targetRegionQuantizedKey ?? "screen")"`;
- legacy fallback path (`mode == live`): `id = "ov_live_legacy_\(kind.rawValue)_\(direction?.rawValue ?? "none")_\(targetRegionQuantizedKey ?? "screen")"`;
- legacy fallback path (`mode == pause`): `id = "ov_pause_legacy_\(frameId)_\(legacySuggestion.type.rawValue)_\(legacyOrdinalKey)_\(kind.rawValue)_\(direction?.rawValue ?? "none")_\(targetRegionQuantizedKey ?? "screen")"`;
- `targetRegionQuantizedKey` строится детерминированно (округление `x/y/w/h` до шага `0.02`) для устойчивости между соседними кадрами;
- `actionSemanticKey`/`legacyOrdinalKey` обязаны быть детерминированными внутри payload кадра (без UUID/random), чтобы избежать коллизий при одинаковых `kind/direction`;
- для `mode == live`: одинаковый semantic input обязан давать одинаковый annotation id на соседних кадрах;
- для `mode == pause`: cross-frame стабильность не требуется (pause id может включать `frameId` и трактуется как freeze-frame identity).

Live hint ID policy (обязательная):
- `LiveHintPresentation.id` всегда детерминирован и никогда не генерируется через UUID/random;
- `id` для live hint не должен включать `frameId`;
- нельзя строить `id` из runtime IDs, которые могут включать `frameId` (`summaryId`, `issueId`, `actionId`, `traceRefId`);
- structured path с action: `id = "lh_live_action_\(actionType.rawValue)_\(issueTypeSignatureKey ?? "none")_\(targetRegionQuantizedKey ?? "screen")"`;
- structured path без action (good/no-action): `id = "lh_live_summary_\(shortVerdictKey)_\(strengthTypeSignatureKey ?? "none")"`;
- legacy fallback path: `id = "lh_live_legacy_\(legacySuggestion.type.rawValue)"`;
- одинаковый semantic input обязан давать одинаковый live hint id на соседних кадрах.
- `issueTypeSignatureKey`: сортированный и склеенный список `IssueTypeV1` для linked issues (без runtime IDs);
- `strengthTypeSignatureKey`: сортированный и склеенный список top strengths `StrengthTypeV1` (без runtime IDs);
- `shortVerdictKey`: нормализованный `summary.shortVerdict` (trim + lowercase + collapse spaces), без использования `summaryId`.

Trace linkage policy (обязательная):
- presentation слой сохраняет исходные ID из domain contracts (`summaryId`, `issueId`, `strengthId`, `actionId`, `overlayHintId`) без переименования;
- `TraceLink.refId` в UI-режиме должен резолвиться к этим runtime IDs в рамках `frameId + mode`;
- если trace bundle временно недоступен, UI не удаляет ID-поля и не заменяет их surrogate-идентификаторами.

## Интеграционные точки

### 1. AnalysisPipeline

Добавить dual-path выходы:
- `currentLiveHint: LiveHintPresentation?`;
- `currentPauseCritique: PauseCritiquePresentation?`;
- `currentOverlayAnnotations: [OverlayAnnotationPresentation]`;
- `currentLegacySuggestion: Suggestion?` (или сохранить существующий `currentSuggestion` как legacy channel).

Policy:
- сначала пытаемся собрать structured output (`snapshot -> semantics -> critique -> plan -> presentation mapping`);
- если structured output недоступен/невалиден, активируем hard fallback (legacy-only);
- если structured output доступен, но `fallbackUsed == true`, остаемся в structured UI с degraded note и legacy backup;
- live и pause используют один и тот же source frame id, чтобы trace/overlay были согласованы.

### 2. CameraViewModel

Расширить state без удаления legacy сразу:
- `@Published var liveHint: LiveHintPresentation?`;
- `@Published var pauseCritique: PauseCritiquePresentation?`;
- `@Published var overlayAnnotations: [OverlayAnnotationPresentation] = []`;
- `@Published var legacySuggestion: Suggestion?` (bridge до полного удаления legacy path).

Правило совместимости:
- `suggestion` и `previewSuggestions` остаются на переходный период;
- новый UI читает сначала `liveHint/pauseCritique`, затем fallback на legacy поля.

### 3. OverlayView и связанные UI-файлы

`OverlayView` получает приоритеты отрисовки:
1. camera preview;
2. thirds/debug overlays;
3. primary subject bbox (если есть);
4. structured overlay annotations;
5. live hint chip;
6. pause critique card/sheet.

На pause:
- вместо legacy `SuggestionListView` показывать expanded card;
- если structured path доступен и `fallbackUsed == true`, card показывает мягкий технический fallback-баннер и legacy list как backup-блок.

## Fallback Strategy (обязательная)

Режимы fallback:
- hard fallback: structured path недоступен, UI уходит в legacy-only;
- degraded structured path: structured path доступен, но `fallbackUsed == true` (показываем structured UI + fallback note).

Structured path считается недоступным, если выполняется хотя бы одно условие:
- `plan.frameId` не совпадает с `critique.frameId`;
- `planConfidence < 0.45` или `critique.verdictConfidence < 0.40`;
- отсутствуют обязательные поля для UI:
  - всегда: `summary.shortVerdict`;
  - только при наличии `primaryAction`: `action.expectedOutcome`;
- для `mode == pause`: если `critique.verdict == good && primaryAction == nil`, то `noChangeRationale` обязателен и непуст;
- `mode == live && liveActionUsable == false` (даже при `fallbackUsed == false`).
- для `mode == pause` этот триггер не применяется.

Deterministic rule-set для `liveActionUsable` (обязательный):
- вычислять только в `mode == live`;
- если `primaryAction == nil`:
  - `liveActionUsable = (inputVerdict == good && noChangeRationale непустой)`;
- если `primaryAction` существует:
  - action проходит contract-check (`actionType`, `guardrail`);
  - для corrective action (`actionType != leave_frame_as_is`):
    - `linkedIssueIds` непустой;
    - `guardrail.minConfidence <= planConfidence`;
    - если `guardrail.requiresStillCamera == true`, то `motion.state == still`;
    - если `guardrail.suppressWhenMoving == true`, то `motion.state == still`;
  - для non-corrective action (`actionType == leave_frame_as_is`):
    - `inputVerdict == good`;
    - `noChangeRationale` или `primaryAction.expectedOutcome` непустой;
- если любое из правил выше нарушено, `liveActionUsable = false` и включается legacy fallback.

Поведение hard fallback:
- `live`: показываем `SuggestionEngine.nextSuggestion(...)` с текущими TTL/cooldown;
- `pause`: показываем `rankedSuggestions(...)`, плюс компактный текст "расширенный анализ недоступен";
- overlay: в fallback режиме допускаются только безопасные `DirectionArrows` из legacy mapping (`left/right/up/down`), без `region_highlight` и `horizon_line`.

Поведение degraded structured path (`fallbackUsed == true`, но structured path доступен):
- `live`: structured hint/overlay остаются активными, при необходимости показывается fallback note;
- `pause`: expanded card остается основным UI, показывается fallback-баннер + legacy backup-блок.

## Anti-Flicker и стабильность

Для нового live hint фиксируются правила:
- минимальное время удержания active hint: `minHoldMs = 1200`;
- смена hint разрешена только если новый кандидат лучше текущего на `confidenceDelta >= 0.12` или текущий истек;
- при одинаковом `actionType` и близком confidence (< 0.08) обновлять только текст, без полной re-mount анимации;
- при `motion.state != still` live hint скрывать, как и в legacy path;
- overlay annotations обновлять не чаще `8 Hz`, coalesce по `id`.

Для pause:
- expanded card не должен пересобираться чаще одного раза на кадр (`frameId` как ключ состояния);
- исключение для `PR-013` reasoning refine: допускается ровно одно `in-place` обновление текстовых полей на том же `frameId` без full re-mount card;
- reasoning refine не должен сбрасывать layout/scroll/анимационный baseline card и не должен перезапускать pause-entry animation;
- при повторном заходе в pause на том же frameId не дергать анимации "с нуля".

Owner и конкурентный доступ:
- owner anti-flicker/throttle политики: `AnalysisPipeline` (single source of truth для live hint/annotations publish);
- `CameraViewModel` только подписывается и не содержит альтернативной логики стабилизации;
- `OverlayView` и дочерние views только рендерят готовое состояние;
- hysteresis/coalesce применяются до публикации `@Published` полей pipeline на `MainActor`, чтобы исключить race между high/medium/low stream updates.

## Overlay Mapping Rules (`RecommendationAction` -> UI)

Primary mapping:
- `overlayHint.kind == arrow` -> directional arrow layer;
- `overlayHint.kind == region_highlight` -> `BBoxOverlay`-style highlight;
- `overlayHint.kind == horizon_line` -> `HorizonOverlay`.

Action fallback mapping (если `overlayHint` отсутствует или неполный):
- `leave_frame_as_is` -> overlay не рисуется (`kind/direction/targetRegion = nil`), даже если во входе случайно пришли `overlayHint` или `targetRegion`;
- `move_frame_left` -> `kind = arrow`, `direction = left`;
- `move_frame_right` -> `kind = arrow`, `direction = right`;
- `move_frame_up` -> `kind = arrow`, `direction = up`;
- `move_frame_down` -> `kind = arrow`, `direction = down`;
- `level_horizon` -> `kind = horizon_line`, `direction = nil`;
- прочие corrective action types (кроме `leave_frame_as_is`): без принудительной стрелки (или `region_highlight`, если есть валидный `targetRegion`).

Region mapping:
- `action.targetRegion` приоритетнее;
- если region нет, берется `issue.affectedRegion` первого linked issue;
- если region недоступен, overlay рисуется как screen-level hint без region anchor.

## Pause Card Contract (expanded)

Pause card должна иметь фиксированные блоки:
1. Verdict:
- `shortVerdict` + confidence badge.
2. Почему кадр работает:
- до 2 strengths (`type + rationale`).
3. Что мешает:
- до 3 issues, сортировка по severity desc.
4. Что делать:
- если `primaryAction` существует: показывать primary action + до 2 secondary actions.
- если `primaryAction == nil` и `verdict == good`: actions-блок не показывать, вместо этого использовать `noChangeRationale` (обязательно непустой).
5. Служебные пометки:
- assumptions (если есть);
- fallback/degraded note (если `fallbackUsed == true`).

UI-ограничения:
- без "сырого debug output";
- один экран, без вложенных сложных аккордеонов в `v1`;
- нейтральный тон формулировок.

## UI State Notes

Состояния VM/UI:
- `liveActive`: `isPaused = false`, показываются `liveHint + annotations` или legacy fallback.
- `pauseLoading`: `isPaused = true`, идет вычисление expanded critique, показывается loader skeleton.
- `pauseReady`: есть `pauseCritique`; card доступна сразу, overlay закреплен на freeze-frame (при `fallbackUsed == true` показывается degraded banner).
- `pauseReadyRefined`: применен валидный reasoning text patch к текущему `pauseCritique` без structural changes и без re-mount card.
- `pauseFallback`: structured output недоступен (hard fallback), показываются legacy preview suggestions.

Переходы:
- `liveActive -> pauseLoading`: пользователь нажал pause, камера остановлена, фиксируется последний кадр.
- `pauseLoading -> pauseReady`: построены `critique + plan + presentation`.
- `pauseReady -> pauseReadyRefined`: пришел валидный reasoning patch для того же `frameId`, обновлены только текстовые поля.
- `pauseLoading -> pauseFallback`: сработал hard fallback policy.
- `pauseReady|pauseReadyRefined|pauseFallback -> liveActive`: пользователь возобновил камеру, временные pause-state очищены.

Инварианты:
- `togglePause()` не меняет логику старта/остановки камеры;
- ошибки structured path не блокируют возвращение в live;
- UI не должен держать "застывший" hint после resume.

## PR Decomposition и write scope

Dependency gate (обязательный для всех трех UI PR):
- `PR-009`, `PR-010`, `PR-011` стартуют только после доступного результата `PR-008 RecommendationPlanner` (валидный `RecommendationPlan` в runtime path).

### PR-010 (Pause Critique Card)

Write scope:
- `CameraViewModel.swift`;
- `OverlayView.swift`;
- новые pause UI компоненты (например, `UI/Overlay/PauseCritiqueCardView.swift`);
- presentation mappers для pause (новый файл в `Multitool2Module`).

Результат:
- structured pause card;
- fallback блок на legacy preview suggestions;
- smoke verification для pause transitions.

### PR-009 (Live Hint Adapter)

Write scope:
- `AnalysisPipeline.swift`;
- `CameraViewModel.swift`;
- `SuggestionChip.swift` (или новый `LiveHintChipView.swift`);
- bridge-файл legacy fallback mapping.

Результат:
- live hint из `RecommendationPlan.primaryAction`;
- anti-flicker/hysteresis;
- dual-path fallback.

### PR-011 (Overlay Annotations)

Write scope:
- `OverlayView.swift`;
- `DirectionArrows.swift` (или новый structured overlay layer);
- новые overlay annotation views/models;
- минимальные правки VM/Pipeline для annotation payload.

Результат:
- `arrow/region/horizon` annotations, привязанные к action/issue;
- безопасный fallback на legacy arrows.

## Verification Steps (implement phase)

Manual smoke:
1. Live, стабильная сцена: hint не дергается, обновляется плавно.
2. Live, движение камеры: hint скрывается, после стабилизации возвращается.
3. Pause good frame: card показывает strengths + (`leave_frame_as_is` или `noChangeRationale` при `primaryAction == nil`).
4. Pause problematic frame: card показывает issues/actions и overlay target.
5. Structured degradation: fallback на legacy suggestions работает без blank state.
6. Resume из pause: камера возобновляется, pause state очищается.

UI acceptance:
- нет мерцания текста/overlay при малых колебаниях;
- интерфейс не перекрывает критическую часть кадра;
- expanded card читаема на small-screen iPhone.

Automated checks (минимум):
- mapper tests: `CritiqueReport + RecommendationPlan -> LiveHintPresentation/PauseCritiquePresentation`;
- fallback policy tests (отдельно: hard fallback vs degraded structured path);
- state transition tests для `CameraViewModel.togglePause()`;
- determinism test для stable hint id/ordering (включая соседние кадры с тем же semantic input);
- determinism test для `LiveHintPresentation.id` (structured action, structured good/no-action, legacy fallback) + инвариант: смена только `frameId` не меняет `id`;
- good no-action test: при `inputVerdict == good && primaryAction == nil` pause card рендерит strengths + `noChangeRationale` без actions-блока;
- pause fallback gate test: при `mode == pause && verdict == good && primaryAction == nil && noChangeRationale пустой` включается hard fallback;
- threshold test: `minHoldMs = 1200` (до порога переключение hint запрещено, после порога разрешено по policy);
- threshold test: `confidenceDelta = 0.12` (при delta `< 0.12` hint не переключается, при delta `>= 0.12` переключается);
- throttle/coalesce test: overlay updates ограничены `<= 8 Hz`, coalesce выполняется по детерминированному `OverlayAnnotationPresentation.id`, а одинаковый live semantic input сохраняет один и тот же id между соседними кадрами.
- collision test для pause overlay ids: в одном `frameId` два overlay с одинаковыми `kind/direction`, но разными `actionId` или `targetRegion`, обязаны иметь разные `id`.

## Residual Risks и mitigation

Риски:
- пересечение write scope между `PR-009/010/011`;
- визуальный шум при одновременном рендере bbox + annotations + chip;
- race conditions между async pipeline обновлениями и pause transitions.

Mitigation:
- порядок интеграции: `PR-010 -> PR-009 -> PR-011`;
- перед стартом каждого из них подтвердить dependency gate на `PR-008`;
- держать dual-path до завершения smoke checks;
- использовать `frameId` как единый synchronization key для pause payload.

## Definition of Done (design mode)

Design считается готовым, если:
- описан implement-ready state model для live/pause UI;
- зафиксированы integration points для `AnalysisPipeline`, `CameraViewModel`, `OverlayView`;
- fallback path на legacy suggestions формализован правилами;
- anti-flicker policy задана конкретными условиями переключения;
- определен mapping `RecommendationAction/OverlayHint -> overlay UI`;
- перечислены verification steps и UI state notes для implement-фазы.

## PR-S05 Design Verify Addendum

Дата проверки: 2026-05-05

Проверка выполнена против:
- Prompt 23 в [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/12-agent-prompts.md);
- semantic tip contracts в [24-semantic-tip-taxonomy-and-action-catalog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/24-semantic-tip-taxonomy-and-action-catalog.md);
- planner/fusion policy в [26-semantic-tip-fusion-and-planner.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/26-semantic-tip-fusion-and-planner.md);
- текущей runtime wiring в `AnalysisPipeline.swift`, `CameraViewModel.swift`, `OverlayView.swift`, `SuggestionChip.swift`, `SuggestionListView.swift`.

### Что было подтверждено

- `live` и `pause` уже сидят на одном structured source path (`LiveHintPresentation`, `PauseCritiquePresentation`, `OverlayAnnotationPresentation`) с сохраненным legacy fallback;
- tap-to-expand для live tip не требует прямого вызова `VLM` и использует уже собранный presentation payload;
- structured overlay annotations и legacy arrows разведены так, чтобы fallback не ломал текущий camera flow;
- entity-aware copy приходит в UI через `SemanticTipCandidate.liveText/pauseText`, а не через сырые internal ids.

### Исправленные расхождения

- anti-flicker text-only refresh теперь сохраняет стабильный `liveHint.id`, но обновляет актуальные `actionId`, `linkedIssueIds`, `targetRegion`, `overlayHint` и trace payload текущего кадра;
- pause card в degraded structured path теперь показывает fallback banner и legacy backup block, как требуется этим документом и Prompt 23;
- pause UI теперь может показывать semantic tips в reason/action форме поверх существующего critique payload, без переписывания pipeline contracts;
- live/pause tips получили базовые accessibility labels/hints вместо немаркированного интерактивного текста.

### Residual risks

- качество object-aware копии в `live` все еще зависит от устойчивости grounding upstream; при низкой confidence корректная деградация уже есть, но copy richness будет ограниченной;
- скриншоты и device-level visual QA остаются обязательными для проверки плотности overlay на small-screen iPhone;
- если будущий reasoning refine начнет менять не только текст, а и target geometry, нужно отдельно проверить, что pause card и overlay не расходятся по `frameId`.

### Readiness verdict

`PR-S05` готов к implement/verify циклу без blocking contradictions.
Оставшиеся риски относятся к визуальной доводке и manual QA, а не к отсутствующим контрактным решениям.
