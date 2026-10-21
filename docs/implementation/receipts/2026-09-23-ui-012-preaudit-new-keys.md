# UI-012 — превью-аудит новых ключей локализации (слайсы 2026-09-22)

- Дата: 2026-09-23
- Исполнитель: bounded-агент UI-012 (превью-слайс)
- Ветка: `store`, HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee`
- Строка трекера: `docs/implementation/APP_STORE_RELEASE_TRACKER.md` §12, UI-012 (P0, Depends UI-003…UI-011)

**Статус строки не менялся. Полная строка UI-012 остаётся `TODO`/заблокированной (UI-003/004/005 стоят на CAM-012), Done-критерий «Localization validator passes» на полный каталог не закрыт. Этот документ — превью-аудит только множества ключей, добавленных принятыми UI-слайсами 2026-09-22 (UI-002/006/007/008/011), по критериям UI-012: pluralization, truncation, RU/EN source equality, отсутствие raw technical error в UI.**

## 1. Границы

- Own: аудит + этот receipt; минимальные исправления только найденных дефектов локализации новых ключей.
- Чужие in-flight изменения в рабочем дереве (в т.ч. CAM-002 closed-loop тесты) не тронуты; `docs/admission/` не тронут; commit/push не выполнялись.
- Временные файлы — только `/tmp/ui012-run/`, удалены после работы.

## 2. Как определено множество новых ключей

`git diff HEAD -- shafinMultitool/Resources/Localizable.xcstrings`: ровно **9 добавлений ключей, 0 удалений/модификаций** существующих (144 добавленные строки = 9 ключей × 16 строк). Всего в каталоге теперь 698 ключей (на UI-001 было 689; разница = эти же 9).

| # | Ключ | Источник слайса |
|---|---|---|
| 1–7 | `set.a11y.region.{target,top,middle,bottom,left,centre,right}` | UI-008 (7 ключей, словесная 3×3-альтернатива target-overlay) |
| 8 | `set.library.loading` | UI-011 (G3 skeleton) |
| 9 | `set.library.rename.confirm` | UI-011 (G6 rename-панель) |

Использование в коде прослежено до исчерпываемости (grep по raw-значениям и enum-кейсам `SETLocalization.swift:146-152,588,591`):

- region ×7 → только `CameraOverlayUXPresentation.regionWords(for:locale:)` (`CameraOverlayUXPresentation.swift:208-219`); потребляется **исключительно в VoiceOver-канал**: `.accessibilityValue` (`SETCameraCoachProductionView.swift:896` live-surface, `:2461` pause-маркер) и `targetRegionAccessibilityValue` (`CameraOverlayUXPresentation.swift:201`).
- `set.library.loading` → только `.accessibilityLabel` skeleton'а (`SETLibraryProductionView.swift:1127`); сам skeleton рисует прямоугольники, видимого Text нет.
- `set.library.rename.confirm` → только заголовок `SETDigitalAction` (`SETLibraryProductionView.swift:1732`) → `SETCommandLabel` (`SETComponents.swift`): `lineLimit(2)` + `fixedSize(horizontal: false, vertical: true)` (перенос, не усечение), `minHeight`-frame, фиксированной ширины нет.

Сверка с fixed-метриками UI-007: HUD-хром (timecode/tally/lens, компактный fixed) **не потребляет ни один из 9 ключей** — все точки потребления перечислены выше.

## 3. Аудит по критериям

Длины — символы; значения из текущего `Localizable.xcstrings`, оба языка `state: "translated"`.

| Ключ | en | ru | (a) en+ru непусто | (b) truncation по каналу потребления | (c) pluralization | (d) raw technical | Вердикт |
|---|---|---|---|---|---|---|---|
| `set.a11y.region.target` | Target area (11) | Целевая область (15) | PASS | PASS — только a11y-value, визуального лимита нет; максимум сборки 40 симв. | N/A — числа нет | PASS | OK |
| `set.a11y.region.top` | upper part (10) | верхняя часть (13) | PASS | PASS — a11y-value | N/A | PASS | OK |
| `set.a11y.region.middle` | middle (6) | середина (8) | PASS | PASS — a11y-value | N/A | PASS | OK |
| `set.a11y.region.bottom` | lower part (10) | нижняя часть (12) | PASS | PASS — a11y-value | N/A | PASS | OK |
| `set.a11y.region.left` | on the left (11) | слева (5) | PASS | PASS — a11y-value | N/A | PASS | OK |
| `set.a11y.region.centre` | centred (7) | по центру (9) | PASS | PASS — a11y-value | N/A | PASS | OK |
| `set.a11y.region.right` | on the right (12) | справа (6) | PASS | PASS — a11y-value | N/A | PASS | OK |
| `set.library.loading` | LOADING LIBRARY (15) | ЗАГРУЖАЕМ БИБЛИОТЕКУ (20) | PASS | PASS — a11y-label skeleton'а, видимого текста нет; в HUD-хром не попадает | N/A — числа нет | PASS | OK |
| `set.library.rename.confirm` | SAVE (4) | СОХРАНИТЬ (9) | PASS | PASS — лейбл переносится до 2 строк, фиксированной ширины нет; RU короче уже живущего в том же контроле «ПЕРЕИМЕНОВАТЬ» (13) | N/A — числа нет | PASS | OK |

Пояснения:

- (a) RU/EN source equality: все 9 ключей присутствуют в source-каталоге с `en`+`ru`, `state: "translated"`, значения непустые. Source-`.xcstrings` — источник правды сборки (компилированный бандл держит только per-language `.strings`, см. комментарий в `SubsystemErrorMappingTests`). Runtime-резолв доказан тестами: nine-band тест `CameraCoachAccessibilityPresentationTests` получает точные RU/EN строки через `localizedString(locale:)` → lproj-бандл. Отдельно значимо: фолбэк резолвера — raw key (`SETLibraryLocalizedCopy.string` → `value: key.rawValue`), т.е. отсутствующая запись вышла бы в UI техническим идентификатором; проверка наличия это закрывает.
- (b) Truncation: единственные ключи, попадающие в визуальный UI, — `set.library.rename.confirm` (переносимый лейбл CTA) и `set.library.loading` (только a11y, видимого текста нет). Остальные 7 — только VoiceOver value-канал. Длинные RU в fixed HUD-хром не попадают (сверка в §2).
- (c) Pluralization: ни один из 9 ключей не содержит счётного существительного с числом или формат-спецификатора (`%d`/`%lld`/`%@` отсутствуют; nine-band тест дополнительно ассертит отсутствие цифр в собранной строке). Переформулировка/stringsdict не требуются.
- (d) Raw technical error / debug copy: технических идентификаторов, кодов ошибок и debug-копии в значениях нет (зафиксировано новым тестом, см. §4).

**Дефектов среди 9 новых ключей не найдено — правки значений `Localizable.xcstrings` не потребовались.**

## 4. Что изменено

| Файл | Изменение | Обоснование |
|---|---|---|
| `shafinMultitoolTests/CameraCoachLocalizationAddresseeTests.swift` | +56 строк: новый тест `testUI012PreviewSliceKeysAreLocalizedForRuAndEnWithoutTechnicalCopy` | Gap: 7 region-ключей были покрыты (`testRegionAndConversationAccessibilityKeysExistInCatalogForRuAndEn`, nine-band), а оба библиотечных ключа UI-011 (`set.library.loading`, `set.library.rename.confirm`) не были покрыты ни одним тестом (`grep set.library shafinMultitoolTests` — пусто). Тест закрепляет все 4 критерия аудита на 9 ключах: en+ru `translated` непусто; отсутствие формат-спецификаторов (plural N/A по построению — будущая счётная копия не пройдёт молча); запрет технических фрагментов; бюджет длины ≤32 симв. на значение, обоснованный каналами потребления. |

## 5. Check

Окружение: Xcode 27.0 (27A266a), iOS SDK 27.0, симулятор iPhone 17e `1F680A42-CEB3-43E8-9CED-52F874962A62` (iOS 27.0). Зафиксированный обход канона `-workspace` (Pods пиннят `IPHONEOS_DEPLOYMENT_TARGET` 12.0/14.0 против SDK 27) — без изменения файлов репозитория, как в `2026-09-22-cam-003-calibration-contract.md` / `2026-09-22-ui-011-library-states.md`:

```bash
# 1. Разовый prebuild Pods с command-line override
xcodebuild -workspace shafinMultitool.xcworkspace -scheme Pods-shafinMultitool \
  -sdk iphonesimulator -destination 'id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /tmp/ui012-run/DerivedData \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 build          # BUILD SUCCEEDED

# 2. Focused-батч через -project lane; EXCLUDED_SOURCE_FILE_NAMES не понадобился —
#    чужие untracked a11y/DynamicType тест-файлы сейчас компилируются против текущего API
xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool \
  -sdk iphonesimulator -destination 'id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /tmp/ui012-run/DerivedData \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:shafinMultitoolTests/CameraCoachLocalizationAddresseeTests test
```

Результат:

```text
Test Case '-[shafinMultitoolTests.CameraCoachLocalizationAddresseeTests testUI012PreviewSliceKeysAreLocalizedForRuAndEnWithoutTechnicalCopy]' passed (0.002 seconds)
Test Suite 'CameraCoachLocalizationAddresseeTests' passed
     Executed 16 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **   (exit 0)
```

16/16 — включая новый тест и все 15 существующих тестов класса (изменение чисто аддитивное).

## 6. GAPS (честно; часть ПОЛНОЙ строки UI-012, не этого превью-слайса)

1. **Валидатор полного каталога отсутствует.** Done-критерий UI-012 «Localization validator passes» в полном смысле не закрыт: единого теста «все ~698 ключей существуют en+ru непусто/translated + plural-проверка счётных ключей» нет. Существующие покрытия точечные: `SubsystemErrorMappingTests` (12 error-ключей), `CameraCoachLocalizationAddresseeTests` (camera-префиксы + с этого слайса 9 новых ключей), `CameraCoachAccessibilityPresentationTests` (region + cycle/clarity ключи).
2. **Pre-existing числовые ключи без plural-вариаций (вне моего множества, в каталоге 0 `variations`):** `set.library.count` = «СЦЕН: %d» — для 1–4 русская форма неверна («1 СЦЕН»); `set.generator.beat.status` = «Beat %d/%d · %@». Ключи не добавлялись слайсами 2026-09-22, править их из превью-аудита — выход за границу; полной строке UI-012 нужно решить: stringsdict/plural-варианты или переформулировка без числа.
3. **Наблюдение (не дефект по критериям):** в region-парах смешаны грамматические формы («середина» + «по центру»; в EN так же: «middle» + «on the right») — одинаково в обоих языках, сознательный дизайн VoiceOver-значения, зафиксировано nine-band тестом.
4. Полная строка UI-012 ждёт UI-003/004/005 (CAM-012): аудит ключей будущих слайсов + validator + «no raw technical error in UI» по всем поверхностям.

## 7. Изменённые файлы (только Own)

- `shafinMultitoolTests/CameraCoachLocalizationAddresseeTests.swift` (+56; файл был чистым относительно HEAD, чужих правок в нём нет).
- `docs/implementation/receipts/2026-09-23-ui-012-preaudit-new-keys.md` (этот receipt, новый).

`shafinMultitool/Resources/Localizable.xcstrings` не менялся (дефектов не найдено). Временные артефакты `/tmp/ui012-run/` и `/tmp/ui012_xcstrings.diff` удалены после работы.
