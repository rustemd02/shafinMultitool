# UI-011 — Library empty state, finalization recovery, missing asset receipt

Date: 2026-09-22. HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`).

Задача (трекер §12, P1): «Упростить Library empty state, recording finalization recovery и missing asset presentation. Done when: No dead CTA; interrupted artifact has deterministic recovery/discard.» Зависимость UI-001 закрыта (`docs/implementation/ui-states-matrix-v1.md`, зона G).

## Найдено и исправлено по G-состояниям

Аудит вёлся по коду `SETLibraryProductionView.swift` против матрицы §7 (G1–G10).

- **G1 `load failure`** — без изменений. Recovery-hero рендерится при `flow == .failure(.load)` даже поверх старых строк; пустой герой не подменяет отказ (уже покрыто `testTypedLoadFailureIsNotPresentedAsEmptyLibrary`).
- **G2 `empty`** — без изменений в коде; добавлен тест. CTA `library_empty_create` существует тогда же, когда и рендерится (`shouldShowEmptyState` требует `hasLoadedSuccessfully && scenes.isEmpty && flow == .idle`), т.е. dead-CTA нет. Новое: `testEmptyStateCTAExistsOnlyForSuccessfulZeroProjectLoad`.
- **G3 `pre-load blank`** — ИСПРАВЛЕНО. Было: до первой успешной загрузки рендерился `Color.clear` без какого-либо индикации ожидания. Стало: ветка `!hasLoadedSuccessfully` рендерит `SETLibraryLoadingState` — статический (без анимации, детерминированный для fixture/Reduce Motion) skeleton из трёх строк-заглушек с hairline-рамкой, a11y-элемент `library_loading` с новой локализованной подписью `set.library.loading` (RU «ЗАГРУЖАЕМ БИБЛИОТЕКУ» / EN «LOADING LIBRARY»). Пост-загрузочный `scenes.isEmpty` при активном flow (например create поверх нуля строк) по-прежнему честная пустая поверхность — empty hero зарезервирован за нулевым результатом успешной загрузки.
- **G4 `creating` / G5 `duplicate` / G7 `deleting` / G8 `flow failure`** — без изменений. Панели существуют, retry детерминирован через `pendingRetry` (покрыто существующими тестами).
- **G6 `renaming` / `renameDuplicate`** — ИСПРАВЛЕНО (это и был главный dead CTA).
  - **Продуктовое решение:** выбрана минимальная рабочая презентация переименования (не скрытие CTA). Обоснование: модель переименования уже была полностью реализована и протестирована (`beginRename/confirmRename/cancelRename/performRename`, retry, `SETLibraryFixtureProvider.libraryRenameSceneResult`), кнопка `library_scene_rename` в строке рендерится и вызывает `beginRename`, а контракт `SceneJourneyState` содержит `library.rename-name`/`library.rename-duplicate-name`. Скрывать живую кнопку значило бы вырезать существующую проверенную функциональность; вместо этого состояние получило честную поверхность.
  - Было: `flowPanel` рендерил `EmptyView()` для `.renaming`/`.renameDuplicate` — пользователь, нажав RENAME, попадал в тупик: нет поля, нет confirm/cancel, create-CTA задизейблен (`flow != .idle`), select/beginDelete/beginRename заблокированы guard'ами.
  - Стало: `SETLibraryRenamePanel` (зеркало create-панели): заголовок `set.library.rename`, поле на `renameDraft` (`library_rename_field`), confirm `set.library.rename.confirm` (RU «СОХРАНИТЬ» / EN «SAVE», id `library_rename_confirm`), cancel `set.library.cancel` (id `library_rename_cancel`), в duplicate-состоянии — заголовок `set.library.duplicate.title` + деталь `set.library.duplicate.detail` с конфликтующим именем (id `library_rename_duplicate_notice`).
  - **Сопутствующий фикс модели (иначе панель имела бы свой dead confirm):** `confirmRename()` гвардился `case .renaming` и из `.renameDuplicate` был no-op. Добавлен приватный `renameTargetID` (ставится в `beginRename`, чистится в `cancelRename`/успешном `performRename`, восстанавливается в retry `.rename`), `renameFlowTargetID` возвращает id для обоих состояний. Публичный словарь `FlowState` не менялся (существующие тесты и `SceneJourneyContractTests` не затронуты).
  - Добавлены DEBUG fixture-роуты `library.rename-name` и `library.rename-duplicate-name` в `driveFixtureInitialState` (имена совпадают с `SceneJourneyState`), чтобы UI-тест-слой мог покрыть G6 без изменений контракта.
- **G9 `artifact health` / missing asset** — детерминированный discard подтверждён и сделан тестируемым.
  - Логика постер-кадра (`loadPosterFrame`) раньше держала guard «файл существует и не пуст» приватно. Извлечён внутренний `SETLibraryPosterArtifactGuard.resolvableMediaURL(for:store:)`: ссылка с отсутствующим файлом, не-regular-файлом или нулевым размером детерминированно возвращает `nil` → рендер honest metadata-placeholder (никакой синтетической картинки из повреждённого артефакта).
  - `SETLibraryLocalizedCopy.previewStatus/artifactStatus` стали internal — тесты пиннингуют словарь `libraryArtifact*` (none/healthy/missing/corrupt/unavailable) и placeholder-фолбэк без UI-harness.
  - Row-презентация отсутствующего медиа: локализованное состояние в `accessibilityValue` («МЕДИА НЕ НАЙДЕНО»/«MEDIA MISSING» и т.д.) + honest metadata-placeholder — битой плитки нет.
- **G10 `privacy entry`** — без изменений.
- **Interrupted recording finalization (граница зон):** recovery/discard самого незавершённого артефакта записи (`recordingPromoting`, `pendingRecordingArtifacts`, журнал `PendingRecordingJournal`) — владелец `RecordingArtifactStore`/recording-контур (DEV-008/010, трогать запрещено). Зона G отвечает за презентацию: interrupted/missing артефакт детерминированно показывается как localized `artifactHealth` + metadata-placeholder; доказано тестами ниже. Продуктового dead-end в Library нет: строка с отсутствующим медиа остаётся открываемой/удаляемой.

## Изменённые файлы (только Own)

- `shafinMultitool/ScenesOverviewModule/SETLibraryProductionView.swift` — G3 skeleton, G6 rename-панель + flowPanel-роутинг, фикс `confirmRename` из `.renameDuplicate` (`renameTargetID`), fixture-роуты rename, accessibility IDs (`library_loading`, `library_rename_field/confirm/cancel/duplicate_notice`), извлечение `SETLibraryPosterArtifactGuard`, internal copy-маппинги.
- `shafinMultitool/Multitool2Module/UI/DesignSystem/SETLocalization.swift` — 2 аддитивных ключа: `libraryLoading = "set.library.loading"`, `libraryRenameConfirm = "set.library.rename.confirm"`.
- `shafinMultitool/Resources/Localizable.xcstrings` — 2 аддитивных записи `set.library.loading` (RU/EN), `set.library.rename.confirm` (RU/EN), state `translated`. Каталог валиден (JSON-парс + `xcstringstool compile` прошли в сборке).
- `shafinMultitoolTests/SETLibraryModelTests.swift` — 7 новых focused-тестов (список ниже).

Чужие изменения в рабочем дереве (CAM-009 diff: `CameraOverlayUXPresentation.swift`, `SETCameraCoachProductionView.swift`, `SETComponents.swift`, `SETMetrics.swift`, `CameraConfidenceCalibrator.swift`, `AnalysisPipeline.swift`, `docs/`, `tools/`, `.github/` и др.) не затронуты. `docs/admission/` не открывался и не менялся. Capture/recording-код не менялся. Commit/push не выполнялись.

## Новые focused-тесты (все зелёные)

1. `testEmptyStateCTAExistsOnlyForSuccessfulZeroProjectLoad` — G2/G3: empty-герой и его CTA существуют только после успешной нулевой загрузки; CTA действие существует (beginCreate достижим из idle).
2. `testLibraryCTAsAreInertOutsideIdleFlowAndCancelAlwaysEscapes` — UI-011 инвариант «CTA активен, только когда действие существует»: во время flow все конкурирующие входы (select/beginCreate/beginDelete/beginRename) инертны; cancel всегда возвращает в idle и чистит draft.
3. `testRenameDuplicatePanelStateEditsOrCancelsDeterministically` — G6: поле открывается с текущим именем; локальный конфликт не доходит до persistence; отредактированный draft коммитится из `.renameDuplicate` (раньше confirm там был no-op).
4. `testMissingAssetRowProjectsHonestHealthAndLocalizedCopy` — G9: строка с dangling recording-ссылкой и `artifactHealth == .missing` не маскируется под empty; health-стейт сохраняется; `.missing` → `libraryArtifactMissing`.
5. `testArtifactHealthCopyMappingCoversEveryState` — G9: все 5 health-состояний пиннингуются к своим ключам; preview без owned reference → `libraryPreviewMetadataPlaceholder`.
6. `testMissingRecordingArtifactDeterministicallyDiscardsPosterURL` — G9 missing-file path: hermetic `RecordingArtifactStore` во временном каталоге — отсутствующий файл → `nil`; zero-byte файл → `nil` (damaged, не presentable); присутствующий не-empty файл → URL. (Ссылки в формате `Recordings/Projects/...`, как в production `relativePath(for:)`.)
7. `testFixtureProviderRenameStaysDeterministicForPresentation` — fixture-провайдер отдаёт typed успех и typed `.duplicateName(conflictingID:)` для rename-роутов.

## Check (команды и результат)

Окружение: Xcode 27.0 (27A266a), iOS SDK 27.0 — с последнего baseline (Xcode 26.6) каноническая `-workspace` lane падает ДО компиляции: checked-in Pods пиннят `IPHONEOS_DEPLOYMENT_TARGET` 12.0/14.0, SDK 27 поддерживает 15.0–27.0.x. Использован зафиксированный в `2026-09-22-cam-003-calibration-contract.md` обход без изменения файлов репозитория:

```bash
# 1. Разовый prebuild Pods с command-line override (никакие файлы не менялись)
xcodebuild -workspace shafinMultitool.xcworkspace -scheme Pods-shafinMultitool \
  -sdk iphonesimulator -destination 'id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /tmp/ui011-run/DerivedData \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 build          # BUILD SUCCEEDED

# 2. Focused-батч через -project lane (как CAM-003/CAM-009), app/test цели собираются со своими 17.0
xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool \
  -sdk iphonesimulator -destination 'id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /tmp/ui011-run/DerivedData \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  EXCLUDED_SOURCE_FILE_NAMES='CameraCoachAccessibilityPresentationTests.swift CameraCoachDynamicTypeLayoutTests.swift' \
  -only-testing:shafinMultitoolTests/SETLibraryModelTests \
  -only-testing:shafinMultitoolTests/SETLibraryInteractorOutcomeTests \
  test
```

Результат (финальный прогон на актуальном дереве):

```text
Test Suite 'SETLibraryInteractorOutcomeTests' passed — Executed 2 tests, with 0 failures
Test Suite 'SETLibraryModelTests' passed           — Executed 26 tests, with 0 failures
Executed 28 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **   (exit 0)
```

26 = 19 существующих + 7 новых тестов `SETLibraryModelTests`. Полный suite не запускался (по условию задачи). Промежуточный красный прогон того же батча поймал реальный баг в моём же тесте (неверный относительный путь `Projects/...` вместо `Recordings/Projects/...`) — исправлен в тесте, не в production-коде.

## Ограничения / что это НЕ доказывает

- **Чужие два несобираемых untracked файла CAM-009.** Во время работы в дерево параллельно легли `shafinMultitoolTests/CameraCoachAccessibilityPresentationTests.swift` и `CameraCoachDynamicTypeLayoutTests.swift` (оба `??`, не компилируются против текущего API: `.switching`/`.loading(snapshotID:)`/`.accessibilityExtraSmall`). Они блокировали компиляцию всего тест-таргета. Я их НЕ правил и НЕ перемещал; для прогонов исключил их command-line-настройкой `EXCLUDED_SOURCE_FILE_NAMES=...` (только на время запуска, на диске ничего не менялось, хэши до/после работы не проверялись на идентичность мной — файлы не мои). Владельцу CAM-009 нужно их починить, иначе любой `xcodebuild test` таргета красный по компиляции.
- **Toolchain drift** (Xcode 27.0 / SDK 27.0 против записанных 26.6/26.5) — это build-input change; зафиксировано здесь и в CAM-003, решение за владельцем.
- **G6 без screenshot/UI-покрытия.** Fixture-роуты `library.rename-name`/`library.rename-duplicate-name` добавлены, но UI-тесты/скриншоты (RU/EN, landscape, XXL, Reduce Motion) не запускались — это fixture-snapshot lane, отдельная задача; в матрице G6 у трёх состояний fixture остаётся «absent (gap)» до того прогоне. Model-контракт покрыт unit-тестами.
- **Interrupted finalization recovery на стороне записи** (retry promotion, журнал pending-артефактов, discard на устройстве) — вне зоны UI-011 (DEV-008/010); здесь доказан только детерминированный discard/presentation в Library. «Recording/export/Library recovery проверены на физических устройствах» остаётся в Release DoD.
- **G8 failure-панель без отдельного dismiss:** выход только через рабочий retry (`pendingRetry`); «Retry/закрытие» из матрицы реализовано наполовину (закрытия нет). Оставлено как есть — не dead CTA (действие существует и работает), расширение панели счёл за рамками UI-011.
- **Stale `artifactHealth` при удалённом вне приложения файле** не перевычисляется в Library: презентация честно деградирует в metadata-placeholder, но переклейку health на `.missing` делает persistence-владелец при следующей загрузке (вне Own).

## Временные файлы

`/tmp/ui011-run/` (логи прогонов + scratch DerivedData) удалены после работы; в репозитории и `~/Library` новых артефактов не оставлено.
