# UI-009 — iPad contract + landscape rotation receipt

Date: 2026-09-22 (log timestamps run past local midnight). HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`).
Status: **PARTIAL** — iPad capability и landscape подтверждены на двух supported iPad-симуляторах с реальными bounds/orientation из логов приложения; физический iPad остаётся открытым (DEV-011). Commit/push не выполнялись; чужие параллельные diff (CAM-009, UI-overlay/library агенты, `docs/admission/`) не затронуты.

## Изменение (Own-зона)

- `shafinMultitool/CommercialShell/CommercialShellViewController.swift` (+44, только `#if DEBUG`): shell теперь пишет в unified log (subsystem `com.vigvamcev-media.shafinMultitool`, category `rotation`) снимок фактической геометрии на `initialLayout`, `routeInstalled`, `viewWillTransition`/`didTransition`: section, `windowScene.interfaceOrientation`, `window.bounds`, target size, `screen.bounds`, `supportedInterfaceOrientations`. Это owner-файл ротации; Release-код не меняется (логгер мёртв без DEBUG). Продуктовые повороты/маски НЕ менялись — код уже соответствовал контракту.

## Сверка контракта с фактом

`docs/implementation/ipad-platform-contract-v1.md` (GOV-003 называет его источником): family `1,2`, все четыре ориентации, минимум 320pt на camera/AR, minOS 17.0 — подтверждено. Единственная расходящаяся строка контракта: **`UIRequiresFullScreen = YES`**. Факт: продукт с 2026-09-16 живёт на **native resizable windows** (`UIRequiresFullScreen = NO`) — это повторное указание владельца, записанное в `diploma.md` (запись 2026-09-16): на iPadOS 26 fullscreen-совместимость системно масштабировала UI (кнопка 44pt измерялась как 39.71pt); «прежняя fullscreen-only конфигурация не описывает текущий продукт»; реализовано в `d4815f3` как master plan §3.8 («resizable Library/Generator/Storyboard» + minimum-window recovery), контракт-тест `iPadPlatformContractTests` в текущих исходниках требует `false` и проходит. По протоколу конфликтов трекера §0 (реальный код + свежий исполнимый тест выше docs) код под устаревшую строку контракта НЕ подгонялся; capability не вырезалась (GOV-003 соблюдён). Строки, требующие сверки владельцем: `ipad-platform-contract-v1.md` (строка `UIRequiresFullScreen = YES`), `windowing-policy-v1.md` (обоснование «recovery string not shipped … with YES»), `ui-states-matrix-v1.md:13` и `CL-CA-049` (фиксируют pre-09-16 состояние YES).

## Таблица: ориентация/устройство → ожидание контракта → факт → исправление

| Ориентация / устройство | Ожидание контракта | Факт | Исправление |
|---|---|---|---|
| Portrait, iPad Pro 11-inch (M5), iOS 27.0 sim | window height > width, io=portrait | лог: `interfaceOrientation=1 window=(0.0,0.0,834.0,1210.0)`; UI-тест: `frame.height > frame.width` | не требуется |
| LandscapeRight, iPad Pro 11-inch (M5), iOS 27.0 sim | window width > height, физический resize | лог: `interfaceOrientation=3 window=(0.0,0.0,1210.0,834.0) screen=(1210.0,834.0)`; UI-тест: `frame.width > frame.height` | не требуется |
| LandscapeLeft, iPad Pro 11-inch (M5), iOS 27.0 sim | то же | лог: `interfaceOrientation=4 window=(0.0,0.0,1210.0,834.0)`; UI-тест прошёл (`width > height`) | не требуется |
| Scene entry (Library route) в landscape, iPad 27.0 sim | route .all, физический landscape | лог: `routeInstalled section=scenes interfaceOrientation=3 window=(0.0,0.0,1210.0,834.0) mask=30`; тест реального пользовательского пути `library_root` → возврат на камеру прошёл | не требуется |
| Rotation portrait↔landscape (survival), iPad 27.0 sim | поверхность живёт, контроли hittable | `testCameraCoachSurfaceSurvivesPortraitLandscapeRotation` passed; лог: пары `didTransition io=1 ↔ io=3/4` | не требуется |
| Contract (shipped Info.plist), Debug build | universal 1+2, 4 ориентации, native resizable, minOS 17.0 | built `Info.plist`: `UIDeviceFamily [1,2]`, все 4 `UISupportedInterfaceOrientations` (ключа `_iPad`-ограничения нет), `UIRequiresFullScreen false`, `MinimumOSVersion 17.0`; `iPadPlatformContractTests` 4/4 на обоих iPad-sim | не требуется (расхождение — в docs, см. выше) |
| PortraitUpsideDown / второй landscape в UI-прогоне | 4/4 объявлены | объявлены и покрыты контрактом plist; UI-прогоном крутились portrait↔landscapeLeft↔landscapeRight; UpsideDown отдельно не крутился | не блокер (объявление проверено, DEV-011 докрывает на устройстве) |
| Физический iPad | реальная приёмка | не выполнялся | остаток UI-009/DEV-011 |

## Лог-факты (из логов приложения, не из скриншотов)

Устройства: `iPad Pro 11-inch (M5)` UDER `DACBF0B6-7CA2-42A4-A2B7-10D7F5E71D5E`, runtime iOS 27.0 (27.0 - 24A434); `SETOS UI preflight iPad 20260916` UDID `AE5076C4-874E-4A9D-85CB-61B2F91B387B`, iOS 26.5 (23F77). Логи: `log show --predicate 'eventMessage CONTAINS "event=initialLayout" OR ... "didTransition"/"routeInstalled"'` по process `shafinMultitool`, category `rotation` (24мм-ном окне вокруг прогонов 23:57:09–00:04:18).

- Portrait: `event=initialLayout section=camera interfaceOrientation=1 window=(0.0, 0.0, 834.0, 1210.0) mask=30`.
- LandscapeRight: `event=didTransition section=camera interfaceOrientation=3 window=(0.0, 0.0, 1210.0, 834.0) target=(1210.0, 834.0)`.
- LandscapeLeft: `event=didTransition section=camera interfaceOrientation=4 window=(0.0, 0.0, 1210.0, 834.0)`.
- Scene entry: `event=routeInstalled section=scenes interfaceOrientation=3 window=(0.0, 0.0, 1210.0, 834.0) mask=30`.
- `mask=30` = `UIInterfaceOrientationMask.all` на всех событиях (shell форвардит активному route: Camera Coach `.all`, Scene nav iPad `.all` / iPhone `.landscape` — задокументированная политика `CommercialShellRouteComposition.swift:288`).
- Геометрия физически меняется (834×1210 ↔ 1210×834) — это не «портрет-как-ландшафт».

## Check (минимальные проверки задачи)

1. Юнит-контракт на обоих iPad-симуляторах: `iPadPlatformContractTests` 4/4 + `CommercialShellLaunchCompositionTests` 14/14 = **18/18, 0 failures** на iOS 27.0 (`/tmp/ui009-unittests.log`, удалён) и 18/18 на iOS 26.5 (`/tmp/ui009-unittests-265.log`, удалён); `-project`-lane, serial.
2. UI-геометрия на iPad 27.0: `CameraCoachLaunchUITests` **5/5 passed** (portrait fullscreen; landscapeLeft/Right physical geometry + readable upright UI; Scene library landscape с реальным переходом и возвратом; portrait↔landscape rotation survival); повтор Scene-теста после добавления route-логгера — passed. Ассерты читают `app.windows.firstMatch.frame` (width>height) и diag-probe `camera_coach_lifecycle_diagnostic`.
3. Полный unit-inventory и остальные ланы не запускались (вне Own-зоны; чужие diff в дереве — CAM-009).

## Метод / окружение

- Сборка Debug в scratch DerivedData `/tmp/ui009-dd` (удалён); Pods prebuild с документированным override `IPHONEOS_DEPLOYMENT_TARGET=15.0` (Xcode 27 SDK отказывает пинам Pods 12.0/14.0; см. `receipts/2026-09-22-cam-003-calibration-contract.md` и `scripts/required_check.sh`; ни один файл репо не менялся).
- Портрет-предположения в Own-зоне (grep `fixedSize`/`frame(height:)`/`portrait`/`UIDevice.orientation`/`supportedInterfaceOrientations` по EntryFlow, ContentView, Overlay pause/live, SceneGenerator views, ScenesOverview, CommercialShell): hardcoded портретных локов нет — только перенос текста (`fixedSize(horizontal: false, vertical: true)`), bounded-метрики канваса (260pt) и size-class адаптации (`SceneInputSheet`, `SETLibraryProductionView`, `LegacySceneGeneratorCameraShell`); контраст: манифест фикстур пинит generator/library/storyboard как `.landscape`, entry/camera/pause — `.adaptive`.
- Параллельные diff не тронуты: `AnalysisPipeline.swift`, `SETCameraCoachProductionView.swift`, `CameraOverlayUXPresentation.swift`, `SETComponents/SETLocalization/SETMetrics`, `SETLibraryProductionView.swift`, `Localizable.xcstrings`, `CameraCoachEntryView.swift`, overlay/pause-файлы и др.

## Gaps / остаток

1. **Физический iPad — явный остаток (DEV-011)**: реальное устройство (touch-поворот, hardware keyboard, split-resize на настоящем multitasking-стеке) не принималось; симуляторные прогоны не заменяют его.
2. Строки docs, зафиксировавшие pre-09-16 `UIRequiresFullScreen = YES`, устарели относительно владельческого решения 2026-09-16 (`diploma.md`) и текущего кода/теста: `ipad-platform-contract-v1.md`, `windowing-policy-v1.md` (вывод про recovery string), `ui-states-matrix-v1.md:13`, claim `CL-CA-049`. Нужна сверка/обновление владельцем (lock-v1 docs вне моей Own-зоны).
3. `PortraitUpsideDown` в UI-прогоне отдельно не крутился (объявление подтверждено built Info.plist + контрактом).
4. Runtime iOS 27.0 sim соответствует поколению физического iPhone14,2 (iOS 27.0 24A435, см. `receipts/2026-09-22-gov-007-storage-audit.md`), но это всё ещё симуляторное доказательство (контракт: simulator evidence only; device windows — M13).

Симуляторы `DACBF0B6…` и `AE5076C4…` после проверок shutdown; временные артефакты (`/tmp/ui009-dd`, `/tmp/ui009-*.log`) удалены.
