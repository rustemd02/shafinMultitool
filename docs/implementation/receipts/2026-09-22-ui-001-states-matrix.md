# UI-001 — User-visible states matrix receipt

Date: 2026-09-22. HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`). Изменения только `docs/`: создан `docs/implementation/ui-states-matrix-v1.md` (deliverable) и этот receipt. Код, локализация, тесты не менялись; чужие незакоммиченные изменения (CAM-009 diff, `docs/admission/`, прочее по `git status`) не затронуты. Commit/push не выполнялись.

Deliverable: `docs/implementation/ui-states-matrix-v1.md` — 91 user-visible state в 8 зонах (A Entry/Permission 10, B Camera live 13, C Pause/Review 5, D Cloud review/consent 11, E Recording/Export 12, F Scene Mode 20, G Library 10, H Privacy 10), каждая строка: Entry, Exit, владелец-символ файл:строка, fixture-классификация, expected screenshot + accessibility (RU/EN, VoiceOver, Dynamic Type, известные ориентации по GOV-003).

## Метод (что просмотрено)

Код читался напрямую (не по памяти); grep-команды, которыми строился индекс:

- `grep -n -E "^(enum|final class|struct)|@Published|case |func " <file>` по: `Multitool2Module/ViewModels/CameraViewModel.swift`, `Multitool2Module/UI/Overlay/SETCameraCoachProductionView.swift`, `SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift`, `ScenesOverviewModule/SETLibraryProductionView.swift`, `Multitool2Module/UI/Overlay/CameraRecordingControlsView.swift`, `SceneGeneratorModule/Views/SceneInputSheet.swift`.
- `grep -rn "enum CameraLifecycleState|CameraOverlayAnalysisStatus|SceneGenerationRequestState|SceneJobStatusValue|CameraManagerError"` — владельцы state-enum'ов.
- `grep -rn "SHAFIN_SET_FIXTURE|SHAFIN_CAMERA_PERMISSION_STATE|SHAFIN_CAMERA_PRODUCTION_FIXTURE|SHAFIN_LIBRARY_PRODUCTION_FIXTURE|SHAFIN_GENERATOR_STORYBOARD_FIXTURE"` — потребители fixture-аргументов.
- `wc -l` по 20 ключевым файлам; `find` по модулям (`Multitool2Module`, `SceneGeneratorModule`, `ScenesOverviewModule`, `Services/Permissions`, `Services/Recording`, `CommercialShell`).

Полностью прочитанные файлы (владельцы состояний):

- `shafinMultitool/Multitool2Module/EntryFlow/CameraCoachEntryFlowModel.swift` (366 строк) — `CameraCoachEntryPhase`/`CameraCoachCameraBlockReason`, transition-машина, foreground recheck.
- `shafinMultitool/Multitool2Module/EntryFlow/CameraCoachEntryView.swift` (573) — copy keys, accessibility IDs, blocked-панели, primary action по фазам, settings fallback.
- `shafinMultitool/Multitool2Module/ContentView.swift` (159) — роутинг entry↔OverlayView, leader handoff.
- `shafinMultitool/Multitool2Module/UI/Overlay/CameraOverlayUXPresentation.swift` (1000 из 1000: строки 1–640) — `CameraOverlayUXPresentation.State` S01…S11/L01/P01…P05, boundary-проекция lifecycle/pause/lens/analysis, episode-проекция, recovery/exit/cycle actions.
- `shafinMultitool/Multitool2Module/UI/Overlay/SETCameraCoachProductionView.swift` (выборочно 1–135, 135–330, 550–730, 1210–1390) — runtime/fixture поверхности, pause routing, fixture semantic states.
- `shafinMultitool/Multitool2Module/Services/Reasoning/CameraCloudReviewState.swift` (27), `Multitool2Module/UI/Overlay/CameraCloudReviewControls.swift` (276) — cloud deep-review состояния и consent sheet.
- `shafinMultitool/Services/Recording/RecorderContracts.swift` (выборочно), `Services/Recording/CameraCoachRecordingCoordinator.swift` (154–209), `Multitool2Module/UI/Overlay/CameraRecordingControlsView.swift` — recording фазы/issues/copy.
- `shafinMultitool/SceneGeneratorModule/Models/SceneExecutionRuntimeContracts.swift` (1–120) — `SceneGenerationRequestState.Phase` + `SceneGenerationFailureKind`.
- `shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift` (выборочно: outline, 171–300, 540–575, 1640–1665, 2800–2860) — workspace modes, validation, error band visibility, remote failure copy.
- `shafinMultitool/SceneGeneratorModule/Views/SceneGeneratorView.swift` (377), `Views/SceneInputSheet.swift` (outline) — error band, leader, clarification, input validation.
- `shafinMultitool/SceneGeneratorModule/Models/SceneBundleContracts.swift` (149) — канонический словарь `SceneJourneyState`.
- `shafinMultitool/ScenesOverviewModule/SETLibraryProductionView.swift` (выборочно: 1–280, 755–1070) — `SETLibraryModel` FlowState/FailureKind, empty state, fixture surface, artifact health.
- `shafinMultitool/Multitool2Module/UI/DesignSystem/SETPrivacyInformationView.swift` (outline), `SceneGeneratorModule/Models/SceneInstallationDeletionState.swift`, `Multitool2Module/UI/DesignSystem/SETInstallationDeletionPresentation.swift` (copy-маппинг) — privacy/deletion.
- `shafinMultitool/Multitool2Module/UI/DesignSystem/SETFixtureCatalog.swift` (181), `UI/DesignSystem/DesignSystemPreviews.swift` (fixture-диспетчер) — fixture-манифест и галерейные экраны.
- `shafinMultitool/Resources/SceneDelegate.swift` (483) — DEBUG-инъекция permissions (`-SHAFIN_CAMERA_PERMISSION_STATE`), роутинг fixture-корней.
- `shafinMultitool/Services/Permissions/PermissionContracts.swift` (37), `Services/Camera/CameraManager.swift` (105–113, 288–299) — permission/lifecycle типы.
- `docs/implementation/ipad-platform-contract-v1.md` — GOV-003: family 1,2, четыре ориентации, `UIRequiresFullScreen`, min 320pt.
- Локализация: `shafinMultitool/Resources/Localizable.xcstrings` — проверено скриптом: локали `en,ru`, 689 ключей.

Fixture/UI-тест-инвентарь: `shafinMultitoolUITests/CameraCoachEntryFlowUITests.swift`, `CameraCoachProductionUITests.swift`, `SETLibraryProductionUITests.swift`, `SETGeneratorProductionUITests.swift`, `SETPrivacyUITests.swift`, `SETDesignSystemGalleryUITests.swift`, `UITests.swift`; unit: `CameraOverlayUXPresentationTests`, `CameraCoachEntryFlowModelTests`, `CameraCoachEntryPresentationTests`, `CameraCloudPauseIntegrationTests`, `CameraCloudTransferConsentTests`, `CameraCoachRecordingCoordinatorTests`, `PendingRecordingJournalTests`, `RecordingRecoveryAndRetentionTests`, `SETLibraryModelTests`, `SETPrivacyInformationTests`, `SETInstallationDeletionPresentationTests`, `SceneGenerationClientTests`, `PermissionFoundationTests` (наличие подтверждено `ls shafinMultitoolTests/`; содержимое директорий тестов не модифицировалось).

## Counts (свод из матрицы §9)

- Всего user-visible состояний: **91**.
- С fixture (каталог-фикстура и/или UI-тест со скриншотом/runtime): **44**.
- Без dedicated fixture: **47** (из них 44 имеют хотя бы unit/интеграционное покрытие; полностью без тестов — A10 settings-fallback; G6 rename — презентация отсутствует как таковая).
- Каталог манифеста: 42 fixture ID (DEBUG), required modes ru/en × default/reduce-motion/reduce-transparency/xxl.
- Наличие тест-файлов владельцев подтверждено `ls`; полнота per-state unit-покрытия по каждой строке не аудировалась.

## Gaps (полный список — матрица §10)

1. `absent (gap)` A10: settings-fallback при отказе `openURL` (`CameraCoachEntryView.swift:494-505`) — без fixture/теста.
2. `absent` (нумерация, не state): S05 отсутствует в `CameraOverlayUXPresentation.State` (`CameraOverlayUXPresentation.swift:86-105`).
3. `absent (gap)`: отдельного offline-state в Camera live нет (локальный продукт); сетевые отказы только в зоне D `failed(.network)` — без скриншот-фикстуры.
4. `absent (gap)`: S10a/S10b без dedicated скриншот-фикстур.
5. `absent (gap)`: скриншот-фикстуры отсутствуют для зон D (cloud review), E (recording/export), H3–H9 (deletion), F5/F11/F12/F16/F17 — есть unit/интеграционное покрытие.
6. `absent (gap)` G6: `renaming/renameDuplicate` — flow-состояния без user-visible презентации (`SETLibraryProductionView.swift:972-976`); словарные ID `library.rename-*` без fixture.
7. `absent (gap)` G3: pre-load blank без loading-индикатора (решение — UI-011).
8. `absent (gap)` G9: missing/corrupt artifact copy есть, dedicated fixture нет.
9. Расхождение catalog↔runtime: generator-фикстуры каталога — статичные галерейные экраны, не runtime-проекция `SceneGeneratorViewModel`; закрывать через UI-012/UI-013.
10. Физическая приёмка (permission на устройстве, VoiceOver-джорни, iPad-ориентации) — вне этого документа: DEV-002, UI-008, UI-009.

## Ограничения

- Инвентаризация статическая (чтение кода на HEAD `f8b6afd`); ни одна fixture поверхностей не запускалась и скриншоты не снимались — это требование выполняет UI-013. Тесты не запускались (запрещено трогать рабочее дерево; минимальный check задачи — сама матрица с file:line ссылками).
- Номера строк привязаны к HEAD `f8b6afd…`; при мерже CAM-009 и других diff'ов сверить смещения перед использованием матрицы как источника для UI-002…UI-009.
