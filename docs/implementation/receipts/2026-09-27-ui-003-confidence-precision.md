# UI-003 — «спокойный» live overlay: аудит и закрытие псевдоточности confidence

Дата: **2026-09-27** · HEAD: `9c43f408` · Ветка: `store`
Задача: **UI-003** (bounded slice; строка → `PARTIAL`: визуальная приёмка «no overlapping
controls/text» + safe-area/rotation fixtures отходит к UI-013/014 после feature freeze)
Зона Own: `SETCameraCoachProductionView.swift` и существующие overlay-компоненты.

## 1. Аудит требований строки (что уже выполнено прежними слайсами)

| Требование UI-003 | Фактическое состояние | Evidence |
|---|---|---|
| Одна primary instruction | Выполнено: `SETCameraCoachRailContent` рендерит ровно одну инструкцию (`actionInstruction`) и только в состояниях corrective/explanation; в seeking/keep/fallback инструкция отсутствует; explanation — только после раскрытия «why»; observation — контекст, не команда. | `SETCameraCoachProductionView.swift` (`commandRailContent`), `CameraOverlayUXPresentation.visibleCopy` |
| Region/arrow только при evidence | Выполнено: overlay-хинт требует spatial evidence (`requiresSpatialEvidence`), стрелка — только при `overlayHint.kind == .arrow`; для VoiceOver регион — словами (UI-008). | `SETCameraCoachProductionView.swift`, `CameraOverlayUXPresentation.regionWords` |
| Stale instruction expires | Выполнено: stale-кадры гасят хинт (`testTechnicalLiveHintsSuppressMovingStaleAndUnqualifiedFrames` и др., 287 live-hint утверждений в тестах); временной expiry — `liveHintDuration`/`minLiveHintHold`/`liveHintMotionHideGrace`. | `AnalysisPipelinePresentationTests`, `AnalysisPipeline.swift:11046-11119` |
| Safe-area/rotation | Частично покрыто прежними слайсами: Dynamic Type XS→AX5 (UI-007), iPad portrait↔landscape реальной геометрией (UI-009). Визуальные фикстуры — UI-013/014. | `receipts/2026-09-22-ui-007-dynamic-type.md`, `…ui-009-ipad-rotation.md` |
| Confidence не показывать как псевдоточность | **НАРУШЕНО — исправлено этим слайсом (§2).** | ниже |

## 2. Реальный дефект и исправление

Аудит всех user-visible поверхностей нашёл **численный процент уверенности
(«74%») в трёх местах** и нелокализованные русские слова тона:

1. `DecisionTraceView` — визуальная строка `«… · 74%»` и метадата severity;
2. `DecisionTraceView` — accessibility-строка «Уверенность … , 74 процентов»;
3. `SuggestionListView` → `ConfidenceBadgeView(showsPercent: true)` ×3 — бейдж
   `«высокая · 74%»` (русское слово захардкожено — EN-пользователь видел бы русский).

Исправление (product-решение — строка UI-003 в каноническом трекере):

- `ConfidencePresentation` больше не рендерит процент в ни одном канале:
  `label(locale:)`/`accessibilityText(locale:)` отдают только **локализованное
  слово тона** через существующие ключи `set.trace.confidence.high/medium/low`
  (RU «ВЫСОКАЯ/СРЕДНЯЯ/МАЛАЯ УВЕРЕННОСТЬ», EN «HIGH/MEDIUM/LOW CONFIDENCE»);
  поле `percent` сохранено как модельная деталь (пороги/тесты) и не показывается;
- `DecisionTraceConfidenceText` и severity-метадата используют тот же источник;
- `ConfidenceBadgeView` упрощён (`showsPercent` удалён — опция псевдоточности
  больше не существует), 3 call-сайта обновлены.

## 3. Проверки

| Check | Результат |
|---|---|
| `AnalysisPipelinePresentationTests/testConfidencePresentationMapsUserFacingBands` (оракл обновлён под product-решение UI-003: tone-бэнды + percent как модель) | passed |
| **Новый** `…/testConfidenceUserFacingTextHidesNumericPrecisionInRuAndEn` — ни одна цифра/% в label/spoken для 3 бэндов × RU/EN; слово локализовано (RU≠EN) | passed |
| `DecisionTracePresentationTests` + `DecisionTraceFixtureContractTests` (5 + контракт фикстур) | 9/0, 0 failures |
| M0 smoke lane после изменений (blocking-минимум) | **133 / 0** |
| Сборка app-таргета | BUILD SUCCEEDED |

Всё — симулятор iPhone 17e/iOS 26.5 (не физическое устройство).

## 4. Честные границы / остаток строки

- **Визуальная приёмка** («no overlapping controls/text», фактические safe-area/
  rotation фикстуры, плотность/иерархия) — это UI-013/014 после feature freeze;
  слайс не заявляет визуальную приёмку.
- Временной expiry (`liveHintDuration`) напрямую тестами не закреплён (stale-evidence
  suppression закреплён); добавить time-based тест можно только с инжекцией часов —
  отдельным bounded-слайсом при необходимости.
- `DecisionTraceView` живёт также в legacy Scene-shell (`LegacySceneGeneratorCameraShell`);
  слайс меняет общий компонент, но Scene-путь не прогонялся (Scene/backend на паузе GOV-002).
- SuggestionListView визуально не проверялся (snapshot-lane для него отсутствует —
  известный пробел UI-011/UI-013).
