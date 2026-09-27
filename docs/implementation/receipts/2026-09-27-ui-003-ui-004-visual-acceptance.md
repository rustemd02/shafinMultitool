# UI-003 / UI-004 — визуальная приёмка live overlay и pause/review (owner-delegated 2026-09-27)

Дата: **2026-09-27** · HEAD: `fcd815a5` · Ветка: `store`
Задачи: **UI-003** (визуальная приёмка live overlay) и **UI-004** (визуальная приёмка
pause/review листа) — остатки строк, делегированные владельцу агенту
(«owner-delegated 2026-09-27»): safe-area/rotation, no overlapping controls/text,
anti-AI-slop превью-просмотр.
Среда: **симулятор** iPhone 17e / iOS 26.5 (`id=1F680A42-CEB3-43E8-9CED-52F874962A62`),
Xcode 27.0. **Это не физическое устройство** (физика — DEV-002/003/008/011).

## 1. Методика (и её честная оговорка)

1. **Прогон M-UI lane** (6 UI-классов, serial, 54 метода): 53 passed / 1 red —
   `SETPrivacyUITests testLibraryPrivacyContainsFullLicenseAndReturnsToLibrary`
   (см. §4, классифицирован отдельно).
2. **147 скриншотов** выгружены из xcresult (`xcresulttool export attachments`),
   инвентарь имён ↔ файлов — в `manifest.json` выгрузки.
3. **Просмотр глазами** ключевых экранов (по ОДНОМУ изображению за раз).
4. **Машинная сверка текста (OCR, Vision.framework, локально)** — по каждой
   находке до и после правки.

**Зафиксированный урок качества этой самой приёмки:** просмотр нескольких
изображений одним вызовом дал перестановку пар «файл ↔ содержимое» и породил
две ложные находки (§3). Выводы ниже перепроверены OCR-ом по именам файлов;
многокарточные наблюдения без машинной сверки не принимались.

## 2. Критерии UI-003 (live overlay) — результат

| Критерий | Вердикт | Evidence |
|---|---|---|
| Одна primary instruction | PASS | OCR: corrective RU «Сделай предложенное…» / EN «Make the suggested…» — одна командная строка; seeking/keep/fallback несут ровно одну строку состояния |
| Region/arrow только при evidence | PASS (глазами) | corrective/noisy-frame — стрелка на субъект; keep — подчёркивание; без evidence маркеров нет (ранее закрыто тестами 287 live-hint утверждений) |
| Confidence не псевдоточность | PASS | закрыто слайсом 2026-09-27 (`set.trace.confidence.*` словами, ноль цифр RU/EN); на принятых скриншотах процентов нет |
| Safe-area | PASS (глазами) | статус-бар/чёлка свободны, pause-кнопка ниже чёлки, командная полоса выше home indicator (портрет RU/EN, landscape EN) |
| Rotation | PASS | landscape EN corrective (1170×2532 buffer, UI в landscape), scene-control landscape, оконный режим landscape XXL |
| Нет перекрытий controls/text | PASS (глазами) | полоса инструкции не перекрывает маркер/субъект; LIVE-чип и pause не пересекаются; noisy-frame: advice на «безопасном краю», субъект не закрыт |

Состояния сверены машинно (RU, одиночный прогон матрицы): seeking →
«Ищу главное в кадре…» (`set.camera.seeking`), keep → «…уже подходит»
(`set.camera.keep`), fallback → «Меньше уверенности…» (`set.camera.fallback`),
explanation → corrective + why-строка. Каждое состояние несёт copy своего
ключа (сверено с `SETCameraFixtureSemanticState.commandKey` и собранным
бандлом `ru.lproj/Localizable.strings`).

## 3. Ложные находки (опровергнуты, правки откачены)

- **«Утечка локали» (RU-фикстуры показывают EN copy).** Опровергнута OCR-ом:
  пре-фикс скриншоты F475FA43/592AE4A4/D9E19080 (matrix, RU-запуски) уже несли
  RU copy корректных ключей; EN-copy видели файлы EN-запусков
  (noisy-frame BDBEBE85/5CFB27BC — `Make the suggested…`). Гипотетические правки
  `SETCameraCommandBand`/`SuggestionChip`/`CameraOverlayUXPresentation`
  (прокидывание `\.locale` вместо `locale: .current`) **откачены целиком** —
  недоказанное изменение не остаётся в дереве. Инвентарь оставшихся сайтов
  `locale: .current`/`.localizedString` (латентная хрупкость при override
  локали/per-app language) передан в аудит UI-012: 
  `CameraOverlayUXPresentation.swift:108,111,162-182,204,277`,
  `SETCameraCoachProductionView.swift:1997`, `SuggestionChip.swift:51-57`,
  `CameraCoachEntryView.swift:19-32`, `ZoomControlView.swift:113`,
  `LegacySceneGeneratorCameraShell.swift:2520`. Production-импакт сегодня не
  показан (`\.locale` == `Locale.current` в default-конфигурации).
- **«Повёрнутый portrait noisy-frame»** — опровергнут повторным одиночным
  просмотром B58D19BE: UI вертикальный, safe-area соблюдена.

## 4. Критерии UI-004 (pause/review) — результат и реальный дефект

| Критерий | Вердикт | Evidence |
|---|---|---|
| «что увидели → что сделать → как проверить» | PASS | pause-unavailable RU (OCR): «РАЗБОР ДУБЛЯ 03» → «Недостаточно данных для оценки кадра.» → CTA + разделы «Что мешает / ДОКАЗАТЕЛЬСТВА / Управление сценой / Расположение в кадре»; partial-action RU несёт assessment-вопрос «Как тебе кажется, получилось?» (`set.camera.review.assessment_request`) |
| Skip/Repeat только при живом действии | PASS (тесты) | закрыто слайсом 2026-09-27 (49/0 OverlayUX+Accessibility+ReviewPresentation) |
| Лист читаем, CTA ≥44pt, без перекрытий | PASS (глазами) | pause-success/empty/failure/loading + scene-control bounded pause portrait/landscape |
| Copy без дублей и псевдоточности | **FAIL → FIXED** | F1 ниже |

**F1 (реальный дефект, закрыт):** generic-сбой паузы печатал label кнопки дважды:
OCR до: `РАЗБОР НЕ СОБРАН` / `ЕЩЁ ДУБЛЬ` / `ЕЩЁ ДУБЛЬ` (2978B47F). Root cause:
`failureDetailKey` для `failureReason == nil` возвращал `.pauseFailureRecovery`
(он же `failureActionKey`). Исправление: новый ключ
`set.pause.failure.detail` (RU «СНИМИТЕ ЕЩЁ РАЗ.», EN «TRY ONE MORE TAKE.» —
в стиле соседних detail-строк) + case `pauseFailureDetail` в `SETCopyKey`;
`failureDetailKey` теперь возвращает его. **Проверка после** (тот же UI-тест,
новый скриншот 1D0C6C09, OCR): `РАЗБОР НЕ СОБРАН` / `СНИМИТЕ ЕЩЁ РАЗ.` /
кнопка `ЕЩЁ ДУБЛЬ` — дубля нет. UI-тест `testPauseLoadingSuccessEmptyFailureMatrix`
passed (1/0).

**Зафиксировано как осознанное (не дефект):** `set.pro.toggle`/`set.pro.title`
в RU латиницей («Pro Controls») — имя фичи, значения локалей идентичны.

## 5. Проверки слайса

| Check | Итог |
|---|---|
| M-UI lane (6 классов, serial) | 54 executed / 1 failure — `SETPrivacyUITests…` (классификация ниже) |
| `testPauseLoadingSuccessEmptyFailureMatrix` после F1 | **1 / 0** |
| `testProductionLiveStateMatrix` (соль) | **1 / 0**, скриншоты состояний OCR-сверены |
| `python3 -m pytest tools/tests/test_localization_catalog_coverage.py` | **5 passed** (новый ключ покрыт enum↔catalog гейтом) |
| OCR сверка находок (до/после) | §3–§4 |

## 6. Классификация красного M-UI (zone H)

`SETPrivacyUITests testLibraryPrivacyContainsFullLicenseAndReturnsToLibrary`
упал на `:88` (scroll-reveal лицензионной строки не уложился в бюджет 20
жестов под нагрузкой). Изоляционный перепрогон ×2: **2/2 passed** (63.0 с,
31.5 с) — флак reveal-цикла теста, не продуктовый дефект; укрепление
reveal-хелпера (controlled scroll по образцу `placementDrag`) — в слайсе
UI-008, зона H.

## 7. Остаток строк после этой приёмки

- UI-003 → `DONE`: все критерии строки и делегированной визуальной приёмки
  выполнены на симуляторе; **физический** UX (VoiceOver journey, реальная камера,
  thermal) остаётся DEV-002/003/005 и **не** закрывается этой приёмкой.
- UI-004 → `DONE`: структура/гейтинги/визуал приняты; финальный контент
  действия — CAM-012 (своя строка), физический UX — DEV-003/008.
- Финальный screenshot-мтрикс и формальный anti-AI-slop review остаются
  **UI-013/UI-014** (после feature freeze) — их scope не присвоен.

## 8. Поправка честности (добавлено после обнаружения дефекта канала изображений)

В конце сессии обнаружено, что **канал прикрепления изображений в инструменте
чтения файлов стал отдавать устаревший образ вместо содержимого файла**:
контрольный пробник `probe-magenta.png` (300×200 сплошной пурпурный, 2.2 KB)
вернул старый UI-скриншот; тот же дефект дал ранее 2–3 перепутанных чтения
(именно он породил ложные находки §3). Следствия для этой приёмки:

- **Текстовые утверждения** (какая copy на экране, дубль кнопки, ключи) имеют
  машинное основание — OCR-транскрипции конкретных файлов (§2–§4), они не
  зависят от канала.
- **Геометрические утверждения** (safe-area, ≥44pt, отсутствие перекрытий)
  дополнительно закреплены assert'ами самих UI-тестов
  (`assertVisibleTextFitsViewport`, `assertSceneControlPauseLayout` — review
  выше footer, footer внутри viewport; `assertTarget` — 44pt hit area,
  `assertCloudConsentActionVisible`), которые выполнялись в прогоне M-UI.
- **Часть «посмотреть глазами»** выполнялась при работающем канале и
  позднее — при уже ненадёжном; наблюдения, не подтверждённые OCR-ом или
  геометрическими assert'ами, в вердикты не включены. Полноценный eyes-on
  anti-AI-slop review остаётся за UI-014 (владелец/человек с исправленным
  инструментом).

