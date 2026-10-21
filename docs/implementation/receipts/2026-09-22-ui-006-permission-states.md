# Receipt — UI-006: camera permission states (zone A Entry/Permission)

Task: `APP_STORE_RELEASE_TRACKER.md` §12, строка UI-006 (`TODO`; статус меняет оркестратор).  
Дата: 2026-09-22 · Baseline: ветка `store`, HEAD `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (без commit/push; изменения в рабочем дереве).  
Вход: `docs/implementation/ui-states-matrix-v1.md` §1 (зона A, A1–A10, UI-001 DONE).  
Границы: Own = `CameraCoachEntryFlowModel.swift`, `CameraCoachEntryView.swift` + их focused-тесты. Чужие параллельные diff (CAM-009 AnalysisPipeline, UI overlay/library/layout, Localizable.xcstrings) не тронуты; `docs/admission/`, `docs/thesis/**` не тронуты.

**Итоговый статус задачи: `PARTIAL`.** Все симуляторно-проверяемые переходы и RU/EN copy подтверждены кодом и тестами; физическая приёмка (реальный Settings round-trip, MDM-restricted, реальное отсутствие камеры) — явный остаток, physical pass НЕ заявляется.

## 1. Матрица «state → переход → RU/EN ключи → тест»

Каталожные ключи из `SETCopyKey` (`SETLocalization.swift`), значения подтверждены парсом `shafinMultitool/Resources/Localizable.xcstrings` (en+ru, все непустые и не равны имени ключа) — см. §2.

| State | Переход (фактический, файл:строка) | RU / EN ключи (каталог) | Тест |
|---|---|---|---|
| A1 `entry.resolving` | `resolveInitialState` (`CameraCoachEntryFlowModel.swift:113-125`) → statusPanel `.entryResolving` (`CameraCoachEntryView.swift:216-223`) | `set.entry.resolving` — RU «ПОДГОТАВЛИВАЮ КАДР…» / EN «PREPARING THE FRAME…» | `CameraCoachEntryFlowModelTests.testCancelledInitialResolutionCannotPublishLateReadyState`; root/ID-тест `testEveryRenderedPhaseHasStableRootAndActionIdentifiers`; UI-каталог `entry.resolving` |
| A2 `entry.intro` | первый запуск (`hasSeenCameraCoachIntro()==false`, `:120-124`) → `openCameraTapped` (`:127-139`) → `.resolving` → свежий snapshot | `set.entry.poster`/`set.entry.body`/`set.action.main`/`set.entry.helper` | `testFirstLaunchShowsIntroRegardlessOfCameraSnapshot`, `testOpenCameraMarksIntroOnceAndMapsFreshSnapshotWithoutRequesting`; UI-тест `CameraCoachEntryFlowUITests` (intro notSeen) |
| A3 `entry.permission` (first-ask context) | snapshot `.notDetermined` → `.permissionContext` (`phase(for:)` `:353-355`) | `set.permission.title` / `set.permission.body` / `set.entry.local_processing` / `set.permission.continue` | `testReturningUserMapsEveryCameraStateWithoutImplicitRequest`; `CameraCoachEntryPresentationTests.testPermissionCopyUsesCameraOnlyCatalogKeys` (body без микрофона/фото/речи); UI-тест permission context |
| A4 `entry.requesting` (системный промпт) | `continuePermissionRequest` (`:141-169`): один `request(.camera)` на тап, повторный тап ждёт тот же task; отмена не публикует late-ready | `set.entry.requesting` — RU «ЗАПРАШИВАЮ ДОСТУП К КАМЕРЕ…» / EN «REQUESTING CAMERA ACCESS…» | `testContinueRequestsCameraExactlyOnceAfterExplicitTap`, `testConcurrentContinueTapsShareOneRequest`, `testCancelledPermissionRequestCannotPublishLateReadyState`, `testEntryFlowNeverRequestsMicrophoneSpeechOrPhotos` |
| A5 `entry.ready` | snapshot `.authorized` → `.ready` → ContentView handoff на live + leader (`ContentView.swift:106-118`) | `set.entry.ready` — RU «КАМЕРА ГОТОВА» / EN «CAMERA READY» | `testReturningUserMapsEveryCameraStateWithoutImplicitRequest`; UI-тест authorized |
| A6 `entry.blocked-denied` | snapshot `.denied` → `.blocked(.denied)` (`:358-359`); primary OPEN SETTINGS (`openSettings` `CameraCoachEntryView.swift:515-525`, `UIApplication.openSettingsURLString`), secondary CHECK AGAIN, footer-fallback при отказе openURL | `set.blocked.denied` RU «ДОСТУП К КАМЕРЕ ВЫКЛЮЧЕН» / EN «CAMERA ACCESS IS OFF»; `set.common.open_settings`, `set.common.check_again`, `set.entry.settings_fallback`, `set.entry.blocked_body`, a11y `set.a11y.open_settings`/`set.a11y.recheck` | `testRecheckReadsSnapshotAndRecoversAfterSettingsWithoutRequest`; `testBlockedReasonsRemainDistinctAndTruthful`; UI-тесты: denied-экран + **foreground Settings return → ready** (`testDeniedStateRechecksOnForegroundAndReachesExistingCameraCoachRoot`), landscape split, XXXL |
| A7 `entry.blocked-restricted` | snapshot `.restricted` → `.blocked(.restricted)` (`:360-361`); единственное действие recheck, Settings НЕ предлагается (`blockedPresentation`, view `:484-492`) | `set.blocked.restricted` RU «КАМЕРА ОГРАНИЧЕНА СИСТЕМОЙ» / EN «CAMERA IS RESTRICTED» | `testReturningUserMapsEveryCameraStateWithoutImplicitRequest`; UI-тест `testRestrictedStateUsesOnlyRecheckRecovery` (одна кнопка recheck) |
| A8 `entry.blocked-unavailable` (нет камеры) | snapshot `availability != .available` → `.blocked(.unavailable)` **до** любых авторизационных веток (`:349-351`), промпт не вызывается | `set.blocked.unavailable` RU «КАМЕРА НЕДОСТУПНА» / EN «CAMERA IS UNAVAILABLE» | `testReturningUserMapsEveryCameraStateWithoutImplicitRequest` (включая новую строку notDetermined+unavailable → unavailable без request); `PermissionFoundationTests.testRequestDoesNotPromptForTerminalOrUnknownStates`; UI-тест `testUnavailableStateShowsTruthfulDeviceRecovery` (launch-arg `-SHAFIN_CAMERA_PERMISSION_STATE unavailable` → `SceneDelegate.swift:397-402`, `.unavailable(.cameraHardware)`) |
| A9 `entry.blocked-unknown` | snapshot `.limited`/`.unknown`/`@unknown default` → `.blocked(.unknown)` (`:362-364`) | `set.blocked.unknown` RU «СТАТУС КАМЕРЫ НЕИЗВЕСТЕН» / EN «CAMERA STATUS IS UNKNOWN» | matrix-тест (включая новую строку `.limited`); UI-тест `testUnknownStateUsesTruthfulRecheckOnlyRecovery` |
| A10 settings-fallback (sub-state) | отказ `openURL`/nil-URL → footer `entrySettingsFallback` (`view:515-525`); **исправлено в этой задаче:** решение вынесено в `CameraCoachSettingsReturn` (`view:68-80`) + сброс футера при уходе с denied-панели (`view:153-159`) | `set.entry.settings_fallback` RU «Откройте Настройки → Конфиденциальность и безопасность → Камера…» / EN «Open Settings → Privacy & Security → Camera…» | **новые** `testSettingsReturnPolicyShowsFallbackForRefusedHandoffOnly`, `testSettingsFallbackFooterIsResetWhenTheDeniedPanelIsLeft` (было: единственное состояние зоны без тестов) |

Ключевые инварианты state-машины (подтверждены): отсутствие prompt loop — request только по явному тапу из `.permissionContext`, на терминальных состояниях клиент не промптит (`SystemPermissionClient.request` guard, `PermissionCoordinatorTests`); foreground-recheck только для blocked (`shouldRecheckOnForeground` `:104-107`; цепочка `SceneDelegate.swift:282` → `CommercialShellViewController.swift:69-71` → `CommercialShellRouteComposition.swift:150-160` → `recheckCameraAccess`); coalesce параллельных recheck/request; `.resolving` как единственный транзит recheck из blocked.

## 2. RU/EN локализация

Метод: парс `Localizable.xcstrings` (698 ключей, sourceLanguage en) по raw-ключам 24 `SETCopyKey`-кейсов зоны A. Результат: **все 24 ключа существуют, en и ru непустые** (полный листинг значений в §1). Против «недостающих ключей не выдумывать»: недостающих нет, новые ключи в этой задаче не добавлялись. Unit-тест `testCameraEntryCopyHasRussianAndEnglishVisibleAndAccessibilityValues` дополнительно сторожит en/ru значения 21 ключа (не изменялся).

## 3. Пробелы → что исправлено (Own, малые и безопасные)

1. **A10 settings-fallback — нулевое покрытие** (зафиксировано UI-001 как «полностью без тестов»). Исправлено поведенчески-сохранной экстракцией `CameraCoachSettingsReturn` (URL=`UIApplication.openSettingsURLString`; fallback только при отказе open) + 2 focused-теста (политика accept/reject/URL + source-биндинг сброса и политики). Поведение вьюхи не изменено.
2. **Stale fallback footer**: `showsSettingsFallback` не сбрасывался — после одного отказанного openURL футер переживал recheck-цикл (denied → resolving → denied) без новой попытки. Исправлено: `.onChange(of: phase)` сбрасывает флаг при уходе с `.blocked(.denied)` (`view:153-159`). UI-тесты denied-панели не затронуты (43/43 зелёные).
3. **Матрица переходов модели**: добавлены 2 строки в `testReturningUserMapsEveryCameraStateWithoutImplicitRequest` — `.limited` → `.blocked(.unknown)` и `notDetermined + unavailable` → `.blocked(.unavailable)` без request (промпт при отсутствии железа).

Крупное в код не выносилось.

## 4. Честные пробелы (не исправлено, отчёт)

1. **Physical-остаток (главный)**: реальный device-цикл first ask → системный промпт → deny → Settings → grant → foreground return; реальный `.restricted` (Screen Time/MDM); реальное отсутствие камеры. Симуляторный `openURL` на Settings всегда успешен, поэтому A10-отказ в ручную невоспроизводим и остаётся defensive-веткой с unit-покрытием политики. Это пересекается с DEV-002 (physical permission receipt) и строкой трекера «physical device» в Check/Done when UI-006.
2. Camera `.limited` теоретически недостижим на iOS (это Photos-only статус) — маппинг в `blocked(.unknown)` честный, отдельного user-visible состояния для него не требуется; тест-строка добавлена для контрактности.
3. UI-тесты зоны (`CameraCoachEntryFlowUITests`) в этой задаче не перезапускались — это отдельный UI-батч; здесь только focused unit-батч по строке задачи. Runtime-покрытие переходов подтверждено существующими UI-тестами (перечислены в §1) без их повторного прогона.

## 5. Check

Среда: Xcode 27.0 (27A266a), iOS SDK 27.0, destination `id=1F680A42-CEB3-43E8-9CED-52F874962A62` (iPhone 17e, booted), serial-режим. Канонический `-workspace` lane падает до компиляции (Pods deployment target pins, известный drift CAM-003); применён задокументированный обход без изменения файлов: prebuild Pods в scratch `IPHONEOS_DEPLOYMENT_TARGET=15.0`, затем `-project` lane.

```bash
xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool \
  -sdk iphonesimulator -destination 'id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /private/tmp/setos-ui006/dd \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -collect-test-diagnostics never \
  -only-testing:shafinMultitoolTests/CameraCoachEntryFlowModelTests \
  -only-testing:shafinMultitoolTests/CameraCoachEntryPresentationTests \
  -only-testing:shafinMultitoolTests/PermissionFoundationTests \
  -only-testing:shafinMultitoolTests/PermissionCoordinatorTests test
```

Результат (exit 0, `** TEST SUCCEEDED **`):

| Suite | Tests | Failures |
|---|---:|---:|
| CameraCoachEntryFlowModelTests | 15 | 0 |
| CameraCoachEntryPresentationTests (10 старых + 2 новых) | 12 | 0 |
| PermissionCoordinatorTests | 6 | 0 |
| PermissionFoundationTests | 10 | 0 |
| **Итого** | **43** | **0** |

## 6. Changes (рабочее дерево, без commit)

- `shafinMultitool/Multitool2Module/EntryFlow/CameraCoachEntryView.swift` (+25/−2): `CameraCoachSettingsReturn`, `openSettings` через политику, сброс `showsSettingsFallback` при смене фазы.
- `shafinMultitoolTests/CameraCoachEntryPresentationTests.swift` (+39, import UIKit): 2 новых теста A10.
- `shafinMultitoolTests/CameraCoachEntryFlowModelTests.swift` (+2): 2 строки матрицы переходов.

Чужие файлы не изменялись; временные артефакты только в `/private/tmp/setos-ui006` (удалены после прогона).
