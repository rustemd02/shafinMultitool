# Receipt — UI-008: VoiceOver accessibility audit и bounded fixes (Camera Coach / Library)

Status: **PARTIAL** (код+unit-уровень закрыт; физический VoiceOver-journey без зрения не выполнялся и НЕ заявляется как пройденный)  
Дата: 2026-09-22 · Baseline: ветка `store`, HEAD `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee`  
Задача: `APP_STORE_RELEASE_TRACKER.md` §12, строка UI-008 (P0, зависимость UI-001 `DONE`)  
Границы Own: accessibility-атрибуты (labels/hints/traits/actions/live region) в существующих UI-файлах Camera Coach и Scene/Library + их focused-тесты. Без commit/push, без `docs/admission/`, без изменения визуального layout.

## 1. Что сделано

### 1.1 Аудит по коду (зоны A–C приоритет, затем G)

Метод: чтение владельцев из `ui-states-matrix-v1.md` + grep всех `accessibility*` API по файлам зон. Пять критериев UI-008:

| Зона / файл | (a) labels интерактивных элементов | (b) Skip/Repeat как accessibilityActions | (c) live region cadence | (d) target overlay → словами | (e) порядок фокуса |
|---|---|---|---|---|---|
| A `CameraCoachEntryView.swift` | PASS: primary/secondary действия имеют label+hint (`accessibilityOpenCamera/OpenSettings/Recheck/Continue`), footer-fallback имеет label, `:341-374,456-491` | n/a (нет цикла подсказок) | n/a | n/a | PASS: poster → phase column (title→body→action) → privacy; `children: .contain` |
| B live `SETCameraCoachProductionView.swift` + `CameraOverlayUXPresentation.swift` | PASS: close/pause (`:750-774`), pro-toggle (`:306-307`), why/continue (`:1890-1910`), lens status/zoom (`:1665-1674`, `ZoomControlView:38-138`), eco (`:1566`); preview/маркеры hidden (`:202,848,858`) | PASS (было, C07): repeat/skip/pause-resume как `accessibilityAction(named:)` на surface, `:902-912`; не моторные (`CameraCoachCycleControl.isMotorAction == false`) | **GAP → исправлено**: новая подсказка не озвучивалась вовсе; auto-announcement отсутствовал (только ручной repeat) | **GAP → исправлено**: стрелка/underline/outline скрыты от VoiceOver, вербальной альтернативы региона не было | PARTIAL: верхний chrome объявлен после command rail в ZStack (см. Gaps) |
| C pause `SETPauseReviewOverlay` (тот же файл) | PASS: resume-CTA через `SETDigitalAction` + ID `camera_coach_pause_action`; placement-reference маркер имеет label `cameraPlacementObserved` (`:2521-2524`) | n/a | PASS: статусы loading/empty/failure — copy без действий, спама нет | **GAP → исправлено** для success-маркера (см. 1.2) | PASS: header → review band → details; декор cut-mark/tally hidden |
| G `SETLibraryProductionView.swift` | PASS: create/empty-create `accessibilityLibraryCreate` (`:993,1049`), rename/delete с `accessibilityLibraryRenameScene/DeleteScene` (`:1293-1327`), privacy `library_privacy`, метаданные-плейсхолдер `:1392-1394` | n/a | n/a | n/a | PASS: явные `accessibilitySortPriority` 4/3/2/1 на строке (`:1192-1327`) |

Отдельные подтверждения аудита: все decorative-слои скрыты (`GlassMarkGuide:610`, `SETCorrectiveArrowDrawGuide:710`, `SETPauseCutMark:763`, `CameraPreview:202`, `SETLeaderCountdown` hit-testing off, leader-лейбл = слово «Главный кадр»/`accessibilityLeader`); UI-текст везде через `SETCopyKey` (без raw-технических строк; raw-ошибки отсечены fail-closed в `CameraOverlayUXPresentation.make`).

### 1.2 Исправления (bounded, только Own)

1. **Live-region cadence (B, критерий c)** — `CameraOverlayUXPresentation.swift:972-983`: новый pure-gate `CameraCoachHintAnnouncementGate` (одна озвучка на изменённую принятую копию; пустая/повторная копия → false). `SETCameraCoachProductionView.swift:918,929,935-943`: на смену `liveHint.id` Surface вызывает `announceNewHintIfNeeded()` — `UIAccessibility.post(.announcement)` только при работающем VoiceOver, непаузированных подсказках и впервые увиденной копии. Ручной repeat (`announceCurrentHint`) сохранён и гейт обходит сознательно. Спам невозможен: identity-шум с той же копией молчит.
2. **Target overlay → словами (B/C, критерий d)** — `CameraOverlayUXPresentation.swift:198-226`: pure `regionWords(for:locale:)` (вербальная 3×3-позиция «Целевая область: верхняя часть, слева» / «Target area: upper part, on the left», без координат; degenerate → пусто) + `targetRegionAccessibilityValue`. Подключено: live surface `.accessibilityValue` (`SETCameraCoachProductionView.swift:896,945-952`, вместе с verification clarity) и pause success-оверлей `.accessibilityValue` (`:2461-2468`). Скрытые маркеры остаются скрытыми — смысл теперь дублируется словами в value-канале.
3. **Локализация (RU/EN)** — `SETLocalization.swift:143-152`: 7 новых ключей `set.a11y.region.*`; `Resources/Localizable.xcstrings`: те же 7 ключей с непустыми en+ru значениями (689 → 696 с учётом соседних правок; вставка алфавитна, формат файла сохранён). Layout, видимая copy и геометрия не менялись.

### 1.3 Минимальные unit-проверки

Новый `shafinMultitoolTests/CameraCoachAccessibilityPresentationTests.swift` (8 тестов):

- gate: новая копия → true ровно один раз; пустая/whitespace копия не стирает dedupe-окно;
- `regionWords`: все 9 бандов непусты в EN и RU, без цифр; точные строки для верхне-левой и нижне-правой бандов; degenerate → пусто;
- `targetRegionAccessibilityValue` nil ⇔ нет spatial evidence;
- `CameraCoachCycleControl` и `VerificationClarity`: label непуст в en+ru;
- каталог: 13 a11y-ключей (region + hint.repeat/skip/pause/resume + status.comparable/unknown) существуют с непустыми en+ru в `Localizable.xcstrings`;
- представительские проекции (starting/interrupted/failed/lens/pause-loading/keep/seeking): `accessibilityLabel` непуст в en+ru.

## 2. Check (focused-батч, оба — TEST SUCCEEDED)

Каноническая среда: pinned destination `id=1F680A42-…` (iPhone 17e), `-parallel-testing-enabled NO`, `-collect-test-diagnostics never`, DD `/private/tmp/setos-ui008-dd`. Из-за Xcode 27.0 drift использован принятый CAM-003 обход: prebuild Pods с `IPHONEOS_DEPLOYMENT_TARGET=15.0` (CLI-only, `BUILD SUCCEEDED`) + `-project`-lane; ни один tracked-файл окружения не менялся.

1. Финальный прогон (полный test-target compile, без исключений):
   `CameraCoachAccessibilityPresentationTests` 8 passed · `CameraOverlayUXPresentationTests` 29 · `CameraPauseMarkerPresentationTests` 10 · `CameraCoachLocalizationAddresseeTests` 15 → **Executed 62 tests, with 0 failures**, `** TEST SUCCEEDED **`.
2. Смежные presentation-сьюты на общий каталог copy: Entry 5 + Review 6 + IntentClarification 6 + ProControls 39 (+ DecisionTrace 6 в первом прогоне) → **0 failures**, `** TEST SUCCEEDED **`.

Хронология честно: первый прогон упал на compile-error чужого untracked-файла UI-007 (`CameraCoachDynamicTypeLayoutTests.swift`, несуществующий `UIContentSizeCategory.accessibilityExtraSmall`); промежуточный прогон выполнен с CLI-override `EXCLUDED_SOURCE_FILE_NAMES=…` (без изменения файлов) и дал 62/0; после того как владелец UI-007 исправил файл, финальный прогон выполнен без override и повторил 62/0.

## 3. Gaps (честные остатки)

1. **Physical remainder (главный)**: физический VoiceOver-journey без зрения (iPhone, VO-жесты, реальная камера/episode loop) не выполнялся — требуется устройство и владелец. Unit/focused-уровень доказывает copy/gate/словарь, но не тактильный маршрут и не реальное речевое поведение. Закрывается отдельной физической приёмкой (вместе с DEV-002).
2. **Порядок фокуса live-surface (e)**: в runtime ZStack верхний chrome (close/pause) объявлен после command rail; перечисление VoiceOver может начинаться с нижнего rail. Исправление требует реструктуризации ZStack — это риск визуального layout (запрещено границами задачи) → вынесено как отдельный bounded-элемент (кандидат в UI-002/UI-007 follow-up). На Entry и Library порядок подтверждён ( явные sort priority).
3. Автоannouncement не проверяется UI-тестом (нет детерминированного захвата речи в симуляторе); поведение зафиксировано pure-gate тестами.
4. Зоны D/E/F/H в этой задаче не аудировались построчно (приоритет A–C+G по постановке); у consent-sheet уже есть `accessibilityAction(.escape)` (матрица D3), у recording-контролов свои ID — их VoiceOver-проход остаётся в общем физическом остатке.
5. Рабочее дерево содержит чужие параллельные diff (CAM-009; UI-002 токены в `SETCameraCoachProductionView.swift`/`SETComponents.swift`/`SETMetrics.swift`; UI-007 untracked-тест; G6-rename ключи `set.library.loading`/`set.library.rename.confirm` в общих файлах). Мои дельты в общих файлах строго отделены: `SETLocalization.swift` +7 ключей a11y.region; `Localizable.xcstrings` +7 ключей; `SETCameraCoachProductionView.swift` — только accessibility-блоки `:894-952` и `:2455-2468`. Чужие строки не менялись.

## 4. Изменённые файлы (Own + необходимые носители локализации)

- `shafinMultitool/Multitool2Module/UI/Overlay/CameraOverlayUXPresentation.swift` — regionWords, targetRegionAccessibilityValue, announcement gate
- `shafinMultitool/Multitool2Module/UI/Overlay/SETCameraCoachProductionView.swift` — live surface value + cadence, pause overlay value
- `shafinMultitool/Multitool2Module/UI/DesignSystem/SETLocalization.swift` — 7 ключей
- `shafinMultitool/Resources/Localizable.xcstrings` — 7 ключей en+ru
- `shafinMultitoolTests/CameraCoachAccessibilityPresentationTests.swift` — новый, 8 тестов

Временные артефакты только в `/private/tmp/setos-ui008-dd` (удалено после записи receipt).
