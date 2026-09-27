# ui-states-matrix-v1 — инвентаризация user-visible состояний (UI-001)

Status: **inventory snapshot v1 (UI-001)**  
Дата: 2026-09-22 · Baseline: ветка `store`, HEAD `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee`  
Задача-владелец: `APP_STORE_RELEASE_TRACKER.md` §12, строка UI-001 (`TODO` → результат инвентаризации; статус меняет оркестратор)  
Receipt: `docs/implementation/receipts/2026-09-22-ui-001-states-matrix.md`

## 0. Метод и границы

- Инвентаризация **только из кода** (state-машины, `@Published`, view-роутинг, fixture-каталоги, UI-тесты). Никакой код/локализация/тесты этим документом не меняются.
- Скриншоты здесь — **expected behavior** (что обязан показать state и что обязан предоставить VoiceOver/Dynamic Type). Финальная device/language/orientation матрица скриншотов — отдельная строка UI-013; этот документ — её вход.
- Fixture-классификация: **Каталог+UI-тест** (fixture из `SETFixtureCatalog` + UI-тест со скриншотом), **Каталог** (fixture существует, рендерится в галерее), **UI-тест (runtime)** (реальный маршрут/launch-аргументы + скриншот в тесте), **Unit-тест** (детерминизм без скриншота), **Нет** (честное отсутствие).
- **GOV-003 (iPhone+iPad):** контракт `ipad-platform-contract-v1.md` — device family `1,2`, все четыре ориентации, ~~`UIRequiresFullScreen=YES`~~ (**сверка 2026-09-27, §19 п.13:** с `d4815f3` — `UIRequiresFullScreen=NO`, native resizable windows; см. receipt UI-009), минимум 320pt на camera/AR-окно; паритет зон на обоих идиомах. Ориентации по состояниям отмечены там, где они известны из тестов/контракта. Физическая iPad-приёмка — UI-009.
- Локализация: все copy — через `SETCopyKey` → `shafinMultitool/Resources/Localizable.xcstrings` (ru+en, единый каталог). VoiceOver labels/hints и Dynamic Type-поведение перечислены по коду вьюх.

Общие инварианты всех зон:

- Идентичность анимации — через event ledger (`SETMotionEventLedger`); `reduceMotion` гасит draw/leader-анимации (переход в терминальную фазу без шагов).
- Camera preview скрыт от VoiceOver (`CameraPreview.accessibilityHidden(true)`, `SETCameraCoachProductionView.swift:202`).
- Кнопка Privacy доступна на Entry и Library-поверхностях (`SETPrivacyEntryButton`, `SETPrivacyInformationView.swift:6`).

---

## §1. Зона A — Camera Coach: Entry / Permission / Onboarding

Владелец state-машины: `CameraCoachEntryPhase` (`shafinMultitool/Multitool2Module/EntryFlow/CameraCoachEntryFlowModel.swift:12-19`), маппинг snapshot→phase `:348-365`. Владелец вьюхи: `CameraCoachEntryView` (`…/EntryFlow/CameraCoachEntryView.swift`). Root accessibilityIdentifier на каждую фазу: `:507-531`; primary action по фазе: `:533-546`. Восстановление по foreground только для blocked (`shouldRecheckOnForeground`, `CameraCoachEntryFlowModel.swift:104-107`).

| State | Entry | Exit | Владелец (файл:строка) | Fixture | Expected screenshot + accessibility |
|---|---|---|---|---|---|
| A1 `entry.resolving` | Запуск маршрута до первого snapshot разрешений (`resolveInitialState`, `CameraCoachEntryFlowModel.swift:113-125`) | Любая фаза после snapshot (`transition`, `:239-280`) | `CameraCoachEntryFlowModel.swift:13`; view `CameraCoachEntryView.swift:206-213` | Каталог `entry.resolving` (`SETFixtureCatalog.swift:37`); экран галереи `DesignSystemPreviews.swift:258,268` | Статусная строка `entryResolving` без действий; RU/EN; VoiceOver: корень `camera-coach-entry-resolving`, лейбл = copy ключа; Dynamic Type: single-column, скролл |
| A2 `entry.intro` (первый запуск/onboarding) | Первый запуск (`introStore.hasSeenCameraCoachIntro() == false`) | Тап «Открыть камеру» → `markCameraCoachIntroSeen` + `.resolving` (`openCameraTapped`, `:127-139`) | `CameraCoachEntryFlowModel.swift:14,43-64,120-124`; view `CameraCoachEntryView.swift:230-243` | Каталог `entry.intro` + UI-тест `CameraCoachEntryFlowUITests.swift:22` (`-SHAFIN_CAMERA_INTRO_STATE notSeen`) с проверкой одного primary action | Постер: intro title/body, действие `actionMain`; VoiceOver: `camera-coach-entry-intro-title/-body`, action label `accessibilityOpenCamera`, hint `entryHelper`; Dynamic Type: display-шрифт с `minimumScaleFactor(0.60)`, маркер в отдельном rail (не клиптит title, `CameraCoachEntryView.swift:398-407`) |
| A3 `entry.permission` (first-ask context) | Snapshot `notDetermined` (`CameraCoachEntryFlowModel.swift:354-355`) | «Продолжить» → `.requesting` + системный промпт (`continuePermissionRequest`, `:141-169`) | view `CameraCoachEntryView.swift:244-259` | Каталог `entry.permission` + UI-тест (`permission: notDetermined`) | Title `permissionTitle`, body `permissionBody`, supplemental `entryLocalProcessing`, действие `permissionContinue`; VoiceOver: `camera-coach-entry-permission-context-title/-body/-local-processing`, action label `accessibilityContinue`, hint `permissionTitle` |
| A4 `entry.requesting` (системный промпт в полёте) | Вызов `request(.camera)` | Возврат snapshot → целевая фаза; повторный тап «Продолжить» ждёт тот же task (`:141-152`) | `CameraCoachEntryFlowModel.swift:16,156-168`; view `CameraCoachEntryView.swift:214-221` | Каталог `entry.requesting`; прямой UI-тест короткого окна — нет (Unit: `CameraCoachEntryFlowModelTests`) | Статусная строка `entryRequesting`, действий нет; VoiceOver: `camera-coach-entry-requesting` |
| A5 `entry.ready` | Snapshot `authorized` | `ContentView` переключает на `OverlayView` + leader countdown (`ContentView.swift:106-118`; `acceptCameraEntry`, `:205-231`) | `CameraCoachEntryFlowModel.swift:17`; view `:222-229` | Каталог `entry.ready` + UI-тест `CameraCoachEntryFlowUITests.swift:52` (authorized) | Статус `entryReady` + bracket-маркер; далее leader 3-2-1 (Reduce Motion: сразу action, `:217-221`); VoiceOver: `camera-coach-entry-ready`, leader `camera-coach-entry-leader` hit-testing off |
| A6 `entry.blocked-denied` | Snapshot `denied` (`:358-359`) | Settings return → `recheckCameraAccess` (`:171-200`) → `.ready`/остаётся blocked | view `blockedPanel`, `CameraCoachEntryView.swift:425-463` | Каталог `entry.blocked-denied` + UI-тесты `:63` (recovery без live-контролов), `:76` (foreground recheck), `:130` (landscape split), `:166` (XXXL scroll) | Title `blockedDenied`, действие `openSettings`, secondary `checkAgain`; footer fallback при отказе openURL (A10); VoiceOver: `camera-coach-entry-blocked-denied`, action `accessibilityOpenSettings` |
| A7 `entry.blocked-restricted` | Snapshot `restricted` (`:360-361`) | Только recheck (Settings не предлагается) | view `:464-472` | Каталог `entry.blocked-restricted` + UI-тест `:92` | Title `blockedRestricted`, единственное действие `checkAgain`; VoiceOver: `accessibilityRecheck`; landscape: split-layout протестирован для denied-панели (общий layout-владелец `SETEntryLayout`) |
| A8 `entry.blocked-unavailable` (нет камеры/железа) | Snapshot `availability != .available` (`:349-351`) | Recheck; честный device-copy, без обещаний | view `:473-481` | Каталог `entry.blocked-unavailable` + UI-тест `:104` | Title `blockedUnavailable`, действие `checkAgain`; VoiceOver: `accessibilityRecheck` |
| A9 `entry.blocked-unknown` | Snapshot `limited`/`unknown` (`:362-364`) | Recheck | view `:482-490` | Каталог `entry.blocked-unknown` + UI-тест `:116` | Title `blockedUnknown`, действие `checkAgain` |
| A10 settings-fallback (sub-state blocked) | `openSettings` отклонён системой (`CameraCoachEntryView.swift:494-505`) | Закрытие вместе с blocked-панелью | `CameraCoachEntryView.swift:97,367-374,446` | Нет (редкий путь; Unit — нет). `absent (gap)` для fixture | Footer `entrySettingsFallback` c ID `camera-coach-entry-settings-fallback`; ожидание: не заменяет primary action |

Флаги доступности зоны: Dynamic Type — `@ScaledMetric` + layout `SETEntryLayout.resolve(accessibilityType:)` (`CameraCoachEntryView.swift:92-96,146-150`); Reduce Motion — `updateAccessibilityPreferences` (`CameraCoachEntryFlowModel.swift:109-111`), marker animation `:417-422`.

---

## §2. Зона B — Camera Coach: Live (видоискатель и коучинг)

Канонический owner: `CameraOverlayUXPresentation.State` — S01…S11, L01 (`shafinMultitool/Multitool2Module/UI/Overlay/CameraOverlayUXPresentation.swift:86-105`). Проекция `make(liveHint:context:)`: `:273-349`; граничные условия `boundaryPresentation`: `:361-428`; episode-проекция `:472-605`. Хост: `SETCameraCoachRuntimeSurface` (`SETCameraCoachProductionView.swift:135-262`). Атрибуты поведения: `recoveryAction` `:162-179`, `exitAction` `:181-183`, cycle-контролы (repeat/skip/pause — не motor actions) `:20-41,231-241`, `canContinueEpisode` `:148-160`.

Ориентации: fixture-тесты чередуют portrait/landscapeLeft (`CameraCoachProductionUITests.swift:95-103`); размещение rail решает `CameraOcclusionSolver` по canvas (`SETCameraCoachProductionView.swift:1334-1348`). iPad: 4 ориентации, min 320pt (`ipad-platform-contract-v1.md`).

| State | Entry | Exit | Владелец (файл:строка) | Fixture | Expected screenshot + accessibility |
|---|---|---|---|---|---|
| B1 `S01 starting` | `lifecycleState .starting/.idle` (`CameraOverlayUXPresentation.swift:365-372`) | `.running` → следующее состояние; action → `viewModel.start()` (`SETCameraCoachProductionView.swift:239-246`) | `CameraOverlayUXPresentation.swift:366-372`; view `:239-246` | Каталог `camera.starting` + UI-тест `CameraCoachProductionUITests.swift:66-83` | `SETCameraStatusOverlay` copy `cameraPreparing`, tally standby; VoiceOver: наблюдение=copy, action=retry/start; RU/EN |
| B2 `S02 interrupted` | `.stopping` или `failed(.sessionInterrupted)` (`:373-379,380-386`) | Resume-действие → `start()` | `:373-386`; view `:239-246` | Каталог `camera.interrupted` + UI-тест `:66-83` | Copy `cameraInterrupted`, recovery `cameraResume`; VoiceOver: recovery-действие доступно; честный «поток прерван», без псевдодиагностики |
| B3 `S03 failed` | `failed(≠sessionInterrupted)` или `analysisStatus == .failed` (`:380-386,413-420`) | Retry → `start()` | `:380-386,413-420` | Каталог `camera.failed` + UI-тест `:66-83` | Copy `cameraFailed`, recovery `retry`; сырые ошибки `CameraManagerError` не текут в UI (fail-closed) |
| B4 `S04 liveSeeking` | Нет liveHint / planner `wait/abstain/selectSubject` / активная episode-фаза (`:281-287,454-459,446-452`) | Появление валидного hint/keep | `:281-287`; view `:247-259` | Каталог `camera.seeking` + UI-тест `:66-83`; Unit `CameraOverlayUXPresentationTests` | Copy `cameraSeeking`; маркеров нет (`:991`); VoiceOver: наблюдение без действий; stale-подсказок нет |
| B5 `S06 stableTip` (corrective) | Маппинг валидного hint, healthy, не limited, есть spatial evidence (`:296-306`) | Смена hint / episode / pause | `:296-348`; view `:247-259` | Каталог `camera.corrective` + UI-тесты `:18-35,95-103` (4 ориентации/локали) + галерея owner-матрица `SETDesignSystemGalleryUITests.swift:19-25,33-39` | Одна primary инструкция; arrow-геометрия при evidence (`:989,1272`); confidence не показывается; VoiceOver: `visibleCopy` joined (`:187-194`), cycle-контролы repeat/skip/pause (`:231-241`); Dynamic Type: scaled-шрифты, surface max width 420 (`:113`) |
| B6 `S07 explanation` | Hint-тип explanation (`map(liveHint:)`, `:288`) | Смена hint | view `:247-259` | Каталог `camera.explanation` + UI-тест `:66-83` | Copy `cameraExplanation`, underline-маркер при region (`:990`); VoiceOver: объяснение, не команда |
| B7 `S08 actionObserved` | Episode `.collectingStableAfterFrames` (`:572-585`) | `.readyForVerification` / отмена | `:572-585` | Каталог `camera.movement` + UI-тест `:95-103` | Progress copy `cameraEpisodeCollecting`, action повторяется; VoiceOver: действие + прогресс |
| B8 `S09 verification` | Episode `.readyForVerification` без результата (`:574-585`) | Verdict → S10a/b или S11 | `:574-585` | Каталог `camera.verification` + UI-тест `:95-103` | Progress copy `cameraEpisodeChecking`, action скрыт; outline-маркер (`:1274`); VoiceOver: идёт проверка |
| B9 `S10a verificationImproved` | Verdict `fixed/improved` при токене episode (`:503-537`) | «Продолжить» → следующий цикл | `:518-537` | Unit-тесты; dedicated screenshot fixture `Нет` (покрыт `camera.verification` частично) | Copy `cameraVerificationFixed/Improved`; recovery `cameraContinue` (`:170-171`); honest confirm: только измеренный результат |
| B10 `S10b verificationNotImproved` | Verdict `unchanged/worse` (`:538-558`) | «Продолжить» | `:538-558` | Unit-тесты; fixture `Нет` (gap для скриншот-матрицы) | Copy `cameraVerificationUnchanged/Worse`; никогда не хвалит неверное движение |
| B11 `S10c keepAsIs` | Planner `keep` вне episode (`:461-462`) | `canContinueEpisode` → skip/pause | `:461-462`; view `:247-259` | Каталог `camera.keep` + UI-тесты `:66-83,95-103` | Copy `cameraKeep`; continue только при episode token (`:172-173`); underline при region |
| B12 `S11 abstention` | Verdict `incomparable` (`:506-515`) | «Продолжить» | `:506-515` | Каталог `camera.abstain` + UI-тест `:95-103` | Copy `cameraVerificationIncomparable`; `verificationClarity = unknown` (`:219-220`); VoiceOver: честное «нельзя сравнить» |
| B13 `L01 lensSwitching` | `lensState .switching/.failed` (`:406-411`) | Завершение транзакции → idle | `CameraViewModel.swift:38-42,192-193`; view `:1001-1005`; fixture `:1358-1379` | Каталог `camera.lens-switching` + UI-тест `:66-83` | Copy `cameraLensSwitching`, узкий статус-rail; без ложного claim о завершённом switch |

Дополнительно (режимы, не состояния): ECO-индикатор `camera.eco` (Каталог + UI-тест `:66-83`) — `showsECO` (`:140-141`), eco copy `:334`; noisy-frame fixture — тестовый сигнал геометрии, не user-visible state (`SETCameraCoachProductionView.swift:70-84`). Нумерация **S05 отсутствует в enum** — нумерационная дыра, не user-visible state (`absent`, не выдумывать).

---

## §3. Зона C — Camera Coach: Pause / Review (локальный deep-dive кадра)

Owner: `CameraPausePresentationState`, `CameraPauseFailureReason` (`shafinMultitool/Multitool2Module/ViewModels/CameraViewModel.swift:11-35`, published `:166-168`). Хост-роутинг: `SETCameraCoachRuntimeSurface` (`SETCameraCoachProductionView.swift:159-262`): pause-проекция → `SETPauseReviewOverlay`; `pauseFailureReason != nil` → failure-оверлей `:204-217`; `isPauseCapturePending` → `.pauseLoading` `:218-226`; `.resuming` → `:227-235`. Copy-мод: `pauseMode` `:554-565`. Pause блокируется при активной записи (`SETCameraTopChrome` `isPauseEnabled`, `:264-269`).

| State | Entry | Exit | Владелец (файл:строка) | Fixture | Expected screenshot + accessibility |
|---|---|---|---|---|---|
| C1 `P01 pause-loading` | `togglePause` → рендер accepted snapshot в полёте (`CameraViewModel.swift:13`) | Успех → P02; пусто → P03; провал → P04 | `CameraViewModel.swift:13,250-263`; view `:218-226,554-557` | Каталог `camera.pause-loading` (`SETFixtureCatalog.swift:57`; mode `SETCameraCoachProductionView.swift:723`) + UI-тест `CameraCoachProductionUITests.swift:142-149` | Copy `pauseLoading`; фон warm-white (`:189`); VoiceOver: статус загрузки; без действий |
| C2 `P02 pause-success` | Рендер + критика готовы (`:14`) | Resume → P05 | view `:165-184,558` | Каталог `camera.pause-success` (en, UI-тест `:149,173-179`; галерея `SETDesignSystemGalleryUITests.swift:26-32`) | Snapshot-кадр + «что увидели → что сделать → как проверить»; resume-CTA; VoiceOver: критика читается как наблюдение+действие; marker region при evidence |
| C3 `P03 pause-empty` | Кадр принят, критики нет (`:15`) | Resume | `CameraViewModel.swift:15`; view `:558-559` | Каталог `camera.pause-empty` + UI-тест `:142-149` | Честное «нечего сказать» без выдуманной критики; resume доступен |
| C4 `P04 pause-failure` | `CameraPauseFailureReason` (`noAcceptedEvidence/displayRenderFailed/pipelineUnavailable/timeout`, `:31-35`) | Resume (`onResume → togglePause`) | view `:204-217,560-561` | Каталог `camera.pause-failure` + UI-тест `:142-149` | Copy `cameraFailed`-семейство, resume-CTA; сырая причина не показывается; Unit: `CameraCloudPauseIntegrationTests`, `CameraReviewPresentationTests` |
| C5 `P05 resuming` | Resume стартует (`:17`) | `.running` → live-состояния | `CameraViewModel.swift:17,763`; view `:227-235` | Каталог `camera.resuming` (`:55`)+UI-тест `:66-83` | Copy `cameraResuming`, действий нет; восстановление review при неудаче restart (`restorePauseReviewAfterResumeFailureIfNeeded`, `CameraViewModel.swift:802-810`) |

---

## §4. Зона D — Camera Coach: Cloud deep-review и consent (post-1.0-граница честности)

Owner: `CameraCloudReviewState`, `CameraCloudReviewFailure` (`shafinMultitool/Multitool2Module/Services/Reasoning/CameraCloudReviewState.swift:3-26`), published `CameraViewModel.swift:169-170`. Copy-маппинг: `CameraCloudReviewControls.swift:73-92`. Consent sheet: `CameraCloudTransferConsentSheet` (`:100-215+`).

| State | Entry | Exit | Владелец (файл:строка) | Fixture | Expected screenshot + accessibility |
|---|---|---|---|---|---|
| D1 `cloud preparing` | Запрос deep-review (`requestCloudPauseAnalysis`, `CameraViewModel.swift:1089`) | → awaitingConsent/analyzing/failed | `CameraCloudReviewState.swift:13`; controls `:74` | Unit: `CameraCloudPauseIntegrationTests`; скриншот-fixture `Нет` | Copy `cameraCloudPreparing`; занятость не блокирует resume |
| D2 `cloud awaitingConsent` | Политика требует явного approve | Approve/Cancel → analyzing/failed | `CameraCloudReviewState.swift:14`; controls `:75` | UI-тест через `-SHAFIN_CAMERA_CLOUD_CONSENT_FIXTURE` (root `SETCameraCloudConsentFixtureRoot`, `SceneDelegate.swift:101-105,175-176`) | Copy `cameraCloudAwaitingConsent` |
| D3 `cloud consent sheet` | `pendingCloudTransfer` показан | Approve → analyzing; Cancel — явный, `interactiveDismissDisabled` + `accessibilityAction(.escape)` (`:161-164`) | `CameraCloudReviewControls.swift:100-215` | Fixture root + Unit `CameraCloudTransferConsentTests` | Превью выбранного кадра (или `cameraCloudPreparationError` при битом декоде, `:190-194`), все policy-поля (operator/region/retention/deletion, `:198-215`), Cancel над скроллом; VoiceOver: заголовок-трейт, текст selectable |
| D4 `cloud analyzing` | Approve | → complete/noAdditionalEvidence/failed | `CameraCloudReviewState.swift:15`; controls `:76` | Unit; fixture `Нет` | Copy `cameraCloudAnalyzing` |
| D5 `cloud complete` | Успешный ответ | Терминальный, в review-поверхность | `:16`; controls `:77` | Unit; fixture `Нет` | Copy `cameraCloudComplete`, иконка checkmark (декоративная) |
| D6 `cloud noAdditionalEvidence` | Ответ без новой evidence | Терминальный | `:17`; controls `:78` | Unit; fixture `Нет` | Copy `cameraCloudNoEvidence` — честное «нового нет» |
| D7 `cloud failed(.preparation/.authentication/.network/.serviceUnavailable/.responseInvalid)` | Typed-отказ клиента | Recovery через resume/retry владельца | `:18`; controls `:79-83` | Unit: `CameraCloudAnalysisClientTests`; fixture `Нет` (gap) | Отдельная локализованная copy на каждый тип (`cameraCloudNetworkError` и т.д.); offline = `.network`; сырой NSError не показывается |

---

## §5. Зона E — Camera Coach: Recording / Capture / Export

Owner: `CameraCoachRecordingPhase` + `CameraCoachRecordingIssue` (`shafinMultitool/Services/Recording/CameraCoachRecordingCoordinator.swift:154-174`, published `:200-209`); `RecordingLifecycleState` (`shafinMultitool/Services/Recording/RecorderContracts.swift:139-153`). Вьюха: `CameraRecordingControlsView` (`shafinMultitool/Multitool2Module/UI/Overlay/CameraRecordingControlsView.swift`): статус-маппинг `:311-318`, failure copy `:331-348`, photos-исходы `:232-236`, unavailable controls `:355-378`.

| State | Entry | Exit | Владелец (файл:строка) | Fixture | Expected screenshot + accessibility |
|---|---|---|---|---|---|
| E1 `recording preparing` (+changingMeter) | Старт записи | → recording / failed | `CameraCoachRecordingCoordinator.swift:156-157`; view `:312` | Unit: `CameraCoachRecordingCoordinatorTests`; UI smoke `UITests.swift:149-166`; catalog fixture `Нет` | Copy `cameraRecordingPreparing`; контролы блокируются (`:36`) |
| E2 `recording recording` | Первый аппенд | Стоп → finalizing | `:158`; view `:313` | Runtime UI smoke (см. E1); catalog fixture `Нет` | Copy `cameraRecordingRecording`, tally запись; sound switch отдельный (`camera_recording_sound`) |
| E3 `recording finalizing` | Стоп (в т.ч. route exit/background/interruption, `RecorderContracts.swift:76-82`) | → saving / failed | `:159`; view `:314` | Unit: `PendingRecordingJournalTests`, `RecordingRecoveryAndRetentionTests`; fixture `Нет` (gap) | Copy `cameraRecordingFinalizing`; journal гарантирует восстановление после обрыва |
| E4 `recording saving` | Промоушен артефакта | → review / failed | `:160`; view `:315` | Unit; fixture `Нет` (gap) | Copy `cameraRecordingSaving` |
| E5 `recording review` (saved take) | Финализация успешна | Playback/share/close | `:161`; view `:316` | Runtime smoke; fixture `Нет` | Copy `cameraRecordingSaved`; кнопки playback/share/delete с ID `camera_recording_*` |
| E6 `recording failed` (+pendingSave) | Любой `RecorderFailure`/persistence (`:166-174`; copy `view:331-348`) | Retry сохранения | `:162`; view `:317,331-348` | Unit: `RecordingContractV1Tests`; fixture `Нет` (gap) | Copy по типу: `cameraRecordingStorageFull`, `cameraRecordingMediaUnavailable`, `cameraRecordingSaveFailed`, `cameraRecordingCaptureFailed`; pendingSave → `cameraRecordingPendingSave` |
| E7 `recording busy` | Повторный запрос в полёте | Завершение операции | `:167`; view `:331` | Unit; fixture `Нет` | Copy `cameraRecordingBusy` |
| E8 `recording released` | Роут-exit / teardown | Только закрытие | `:174`; view `:318,333` | Unit; fixture `Нет` | Copy `cameraRecordingUnavailable`; контролы не мёртвые — скрыты/заменены |
| E9 `preparation unavailable` (+retry) | Координатор не подготовился | Retry preparation (`camera_recording_retry_preparation`, `:372`) | view `:355-378` | Runtime UI smoke `UITests.swift:151`; fixture `Нет` | Отдельная поверхность `camera_recording_unavailable_controls` с retry; без зависания |
| E10 playback sheet | Открыть сохранённый дубль | Close (`camera_recording_player_close`, `:172`) | view `:159-175,382-410` | Runtime; fixture `Нет` | Системный плеер; VoiceOver: close доступен до/во время воспроизведения (`:406-410`) |
| E11 share sheet | Поделиться дублем | Системный dismiss | view `:176-195` | Runtime; fixture `Нет` | Стандартный UIActivityViewController |
| E12 photos export исходы | «Сохранить в Фото» | `exported/denied/restricted/alreadyInFlight/failed` (`view:232-236`) | `ScenePhotosExportService` + `lastPhotosOutcome` (`CameraCoachRecordingCoordinator.swift:205`) | Unit; fixture `Нет` (gap) | Copy: `cameraRecordingExported/PhotosDenied/PhotosRestricted/Exporting/ExportFailed`; denied/restricted не предлагают повтор до recheck |

Примечание offline: у Camera Coach нет отдельного «offline»-state — продукт локальный; сетевые отказы существуют только в зоне D (`.network`).

---

## §6. Зона F — Scene Mode (Generator): вход, job-статусы, error/offline

Owner request-машины: `SceneGenerationRequestState` (`shafinMultitool/SceneGeneratorModule/Models/SceneExecutionRuntimeContracts.swift:46-62`), failure kinds + `isRetryable` `:14-40`. Вьюха-хост: `SceneGeneratorView` (`shafinMultitool/SceneGeneratorModule/Views/SceneGeneratorView.swift`); input: `SceneInputSheet.swift`; job-статусы API: `SceneGenerationAPIContracts.swift:23-42`. Канонический словарь ID: `SceneJourneyState` (`SceneBundleContracts.swift:13-123`). Ориентации: generator-фикстуры каталога landscape (`SETFixtureCatalog.swift:61-66`); UI-тесты реального маршрута — landscapeLeft (`SETLibraryProductionUITests.swift:295` для library; генератор аналогично).

| State | Entry | Exit | Владелец (файл:строка) | Fixture | Expected screenshot + accessibility |
|---|---|---|---|---|---|
| F1 `idle` | Старт workspace | Ввод → `input` | `SceneExecutionRuntimeContracts.swift:48` | Storyboard/gallery fixtures не покрывают; Unit: `SceneGenerationAPIContractsTests` | Нет surfaces сверх камеры-шелла |
| F2 `input` (sheet открыт) | Кнопка ввода (`showInputSheet`) | Submit → validating; cancel | `:49`; sheet `SceneInputSheet.swift:317` | UI-тест `SETGeneratorProductionUITests.swift:24,178` (real route, keyboard) | Editor `generator_input_editor`, paste `generator_input_paste`, transfer disclosure `generator_transfer_disclosure/policy`; RU/EN |
| F3 `input validation: empty/tooLong(5000)/invalidText` | Пустой/длинный/невалидный текст (`SceneInputValidationIssue`, `SceneGeneratorViewModel.swift:287-291`) | Исправление текста | view: `generator_input_validation`, `SceneInputSheet.swift:372`; лимит `:300` | UI-тест whitespace `:146` | Inline-валидация без alert; VoiceOver: сообщение рядом с полем; generate-CTA disabled (`:481`) |
| F4 `validating` | Submit | → clarification/accepted/terminalFailure | `:50` | Catalog `generator.preflight` (статичный, `DesignSystemPreviews.swift:319`); runtime: Unit `SceneGenerationClientTests` | Прогресс без притворной точности; cancel доступен |
| F5 `clarification` | Backend `awaiting_clarification` (`SceneGenerationAPIContracts.swift:26-28`) | Ответ (option/free text) → generating; исчерпание попыток → failure | `:51`; sheet `:88-91,192-276` | Catalog `generator.clarification` (статичный) + fixture-пейлоады `SceneBundleContracts.swift:32`; runtime UI-тест прямой `Нет` (gap) | Prompt, options (`generator_clarification_option_*`), free text `generator_clarification_text` c лимитом, feedback `generator_clarification_feedback`; VoiceOver: prompt как label поля |
| F6 `accepted` | Валидация пройдена | → leader | `:52` | Unit; fixture `Нет` | Без вспышки UI — переход в leader |
| F7 `leader` (countdown 3-2-1) | Перед генерацией | → queued/generating | `SceneGeneratorView.swift:67-73,137-161` | UI-тесты `SETGeneratorProductionUITests.swift:782,835` (rotation, Reduce Motion) | `SETLeaderCountdown`, ID `generator_leader`; eventID в accessibilityValue только DEBUG (`:150-154`) |
| F8 `queued` | Job принят | → generating | `:54` | Catalog `generator.progress` (галерея-матрица owner approval `SETDesignSystemGalleryUITests.swift:40-46,61-67`, landscape) | Прогресс чтения/планировки; стадии `reading/planning/placing` (`SceneGeneratorViewModel.swift:185-189`) |
| F9 `generating` (+стадии) | Poll `running` | → success/отказы | `:55`; стадии `:185-189` | Catalog `generator.progress`; runtime: AR-fixture error test `:440-443` | Стадийный прогресс; ECO-притворства нет |
| F10 `cancelling` | Пользователь/фон отмена | → input / terminalFailure | `:56` | Catalog `generator.cancelled` (статичный) | Copy `generatorCancelled`; сохранение предыдущей сцены |
| F11 `paused` / F12 `backgrounded` | Системные паузы/фон | Возобновление или teardown (`SceneGeneratorView.swift:103-109`) | `:57-58` | Unit; fixture `Нет` (gap; сверить с UI-010) | Фон: teardown + dismiss; без «зависшего» прогресса |
| F13 `retryableFailure` | Retryable kind (`:31-39`): arNotReady, cameraPosition, network, quota, model, persistence, compilation, timeout | Retry → генерация заново; persistence-retry только при идентичном вводе (`canRetryGenerationPersistence`, `:1649-1658`) | `:59`; error band `SceneGeneratorView.swift:53-65,168-269` | UI-тест `testErrorBandIsTheHonestFailureSurface` `:224`; deterministic AR EN-fixture `:440-443` | Банд `generator_error_band` c copy по типу (`generatorError*`, `:2833-2843` и `:6297-6385`); recovery-действие + Close (`generator_error_close`); offline = `network` → localized, retry; камера-шелл продолжает жить под бандом |
| F14 `terminalFailure` | parse, malformed, cancelled, remoteExpired, remoteDisabled (`:36-38`) | Закрытие/редактирование ввода | `:60` | UI-тест `:224,443` | Честная причина без сырого technical error; RemoteTransfer policy unavailable → `generatorTransferUnavailable` |
| F15 `success` | `complete` job + quality gate | Workspace ready / storyboard | `:61` | Catalog `generator.result` (статичный) + storyboard.result UI-тесты `:504-543` | Переход в AR/storyboard без потери ввода |
| F16 mic-permission recovery (recording) | Микрофон denied/restricted при записи | openSettings / recheck / video-only | `SceneRecordingPermissionRecovery` (`SceneGeneratorViewModel.swift:180-183`); band `SceneGeneratorView.swift:199-222`; copy `:6378-6385` | Unit: `SceneRecordingControllerTests`; UI-тест звука `:264`; fixture `Нет` (gap) | `generator_microphone_open_settings` / `generator_microphone_recheck` / `generatorRecordWithoutSound`; выбор не блокирует видео-запись |
| F17 recording save recovery | Обрыв финализации | Retry `generator_recording_save_retry` (`SceneGeneratorView.swift:190-198`) | `hasPendingRecordingSave`, `:554-556` | Unit: `RecordingRecoveryAndRetentionTests`; fixture `Нет` | Copy `generatorRecordingSavePending/Retry/Saving`; нет dead CTA |

---

## §7. Зона G — Library

Owner: `SETLibraryModel` (`shafinMultitool/ScenesOverviewModule/SETLibraryProductionView.swift:190-238`, `shouldShowEmptyState` `:264-265`); failure kinds `:9-17,201-215`; artifact health `:21-27,755-762`. Поверхность: `SETLibraryContactSheet` `:899-1002`. Ориентации: production fixture-тесты — landscape (`SETLibraryProductionUITests.swift:11,295`); catalog `library.contact-sheet` — landscape (`SETFixtureCatalog.swift:67`).

| State | Entry | Exit | Владелец (файл:строка) | Fixture | Expected screenshot + accessibility |
|---|---|---|---|---|---|
| G1 `load failure` | Провал начальной загрузки (`flow = .failure(.load)`), recovery hero даже при старых данных (`:254-263`) | Retry load | `:279-293,499-502`; панель `:1019+`/failure panel | UI-тест-провайдер `library.persistence-failure` покрывает панель/`library_failure_retry` (`SETLibraryProductionUITests.swift:97-114`) | `library_failure_title/detail` + retry; VoiceOver: панель контейнером `library_root`; пустой герой не подменяет отказ (`:924-927`) |
| G2 `empty` | `hasLoadedSuccessfully && scenes.isEmpty && flow == .idle && loadFailure == nil` (`:264-265`) | Create → список | view `SETLibraryEmptyState` `:1019-1061` | Production fixture `library.empty` + UI-тест RU/EN landscape `:11-35` | Title/helper `libraryEmptyTitle/Helper`, CTA `library_empty_create`; film-edge декор; VoiceOver: контейнер `library_empty_state`, label CTA `accessibilityLibraryCreate` |
| G3 `pre-load blank` | До первой успешной загрузки (`Color.clear`, `:924-927`) | Загрузка → empty/list/failure | `:921-927` | Нет — честно: без спиннера; fixture `Нет` (gap: решение о loading-индикаторе — UI-011) | Пустая поверхность; пустой герой зарезервирован только для честного zero-project |
| G4 `creating` | «Создать» (`beginCreate`) | Confirm → created/invalid/duplicate; cancel | `:193,237`; панель create | Production fixtures `library.create-name` (UI-тест `:99,130`) | Поле `library_create_field`, confirm/cancel `library_create_confirm/cancel`; helper placeholder |
| G5 `duplicate name` | Конфликт имени (`:194`) | Правка имени / cancel | `:194,342-358` | Production fixture `library.duplicate-name` + UI-тест `:100` | `library_duplicate_notice` с конфликтующим именем; CTA остаётся живым |
| G6 `renaming` / `renameDuplicate` | Контракт зарезервирован; presentation — `EmptyView` («later Library rename slice», `:972-976`) | — | `:195-196,972-976` | `absent (gap)` — user-visible presentation нет; SceneJourneyState имеет `library.rename-name/-duplicate-name` (`SceneBundleContracts.swift:18-19`) без fixture | Честно: состояния не отрисованы; не считать проверенными |
| G7 `deleting` (confirm) | `beginDelete` | Confirm → удаление; cancel | `:197,371-412`; панель delete | Production fixture `library.delete-confirmation` + UI-тест `:101,140` | `library_delete_detail/confirm/cancel`; имя сцены в детали |
| G8 `flow failure` (create/rename/delete/open) | Typed `SETLibraryFailure` (`:9-17,201-215`) | Retry/закрытие | `:198`; панель failure `library_failure_*` | Production fixture `library.persistence-failure` (provider `failCreate`, `:856-880`) + UI-тест `:102-104,114` (RU/EN, Reduce Motion) | Actionable retry `library_failure_retry`; имя/причина без NSError |
| G9 `artifact health` (row-лейбл) | Метаданные сцены: none/healthy/missing/corrupt/unavailable (`:21-27`) | — | copy `:755-762`; честный metadata-placeholder при отсутствии записи (`:45`) | Unit: `SETLibraryModelTests`; dedicated fixture `Нет`; `library.missing-preview` в словаре без fixture (gap) | Copy `libraryArtifact*` (`libraryArtifactMissing/Corrupt/Unavailable`); отсутствие — честный placeholder, не битая плитка |
| G10 `privacy entry` | Кнопка Privacy на Library | Открытие Privacy-поверхности (зона H) | safeAreaInset `:1000-1004` | UI-тест `SETPrivacyUITests.swift:58-96` | `library_privacy`; Persistent bottom-inset, не перекрывает строки |

---

## §8. Зона H — Privacy / onboarding-данные / deletion

Owner вьюхи: `SETPrivacyInformationView` (`shafinMultitool/Multitool2Module/UI/DesignSystem/SETPrivacyInformationView.swift:48+`); entry button `:6-33`; deletion state-машина: `SceneInstallationDeletionState` (`shafinMultitool/SceneGeneratorModule/Models/SceneInstallationDeletionState.swift:5-13`) с copy-маппингом `SETInstallationDeletionPresentation.swift:118-135`. Onboarding intro — зона A (A2).

| State | Entry | Exit | Владелец (файл:строка) | Fixture | Expected screenshot + accessibility |
|---|---|---|---|---|---|
| H1 `privacy surface` | `SETPrivacyEntryButton` с Entry/Library | Close (`privacy_close`, `:264`) | `SETPrivacyInformationView.swift:48-266` | UI-тесты `SETPrivacyUITests.swift:15-96` (открытие до permissions, RU/EN; license return) | Документ `privacy_document` (scroll), секции account/data (`privacy_account` и др.), лицензии `privacy_notice_<id>`; VoiceOver: доступно до выдачи разрешений; RU/EN |
| H2 `notice unavailable` | Лицензионный файл не читается (`:143`) | Close | `:138-143` | Unit: `SETPrivacyInformationTests`; fixture `Нет` | `privacy_notice_unavailable_<id>` — честный fallback вместо пустоты |
| H3 `deletion: unavailable` | Сервис недоступен | Retry/status check | `SceneInstallationDeletionState.swift:6`; copy `privacyDeletionUnavailable` | Unit: `SETInstallationDeletionPresentationTests`, `InstallationDeletionLifecycleTests`; UI fixture `Нет` (gap) | Copy + иконка info; request/check кнопки (`privacy_deletion_request/check`, `:210,222`) |
| H4 `deletion: noInstallation` | Нет инсталляции на бэкенде | — (информационный) | `:7` | Unit; fixture `Нет` | `privacyDeletionNoInstallation` |
| H5 `deletion: ready` | Инсталляция найдена, подтверждение доступно | Confirm → working | `:8`; confirm/cancel `:170-176` | Unit; fixture `Нет` | `privacy_deletion_confirm/cancel` + retained-дисклеймер `privacy_deletion_retained` (`:189`) |
| H6 `deletion: working/pending` | Запрос в полёте / подтверждён, поллинг | → complete/uncertain/failed | `:9-10` | Unit; fixture `Нет` | `privacyDeletionWorking/Pending`, иконка clock; статус читается VoiceOver (`privacy_deletion_status`, `:198`) |
| H7 `deletion: complete` | Бэкенд подтвердил удаление | Терминальный | `:11` | Unit; fixture `Нет` | `privacyDeletionComplete`, checkmark |
| H8 `deletion: uncertain` | Таймаут/неоднозначный ответ | Re-check | `:12` | Unit; fixture `Нет` (gap) | `privacyDeletionUncertain` — честное «неизвестно», не «успех» |
| H9 `deletion: failed(transport/secretStorage/policyMismatch/receiptUnavailable/…)` | Typed `InstallationDeletionError` (`:13,125-135`) | Retry/check | `:13`; copy `:125-135` | Unit; fixture `Нет` (gap) | `privacyDeletionNetworkError/StorageError/PolicyError/ReceiptError`; сырой error не показывается |
| H10 photos add-only permission | Экспорт в Фото: denied/restricted (зона E12) | Settings/retry владельцем export | `PermissionContracts.swift:5` (photosAddOnly); copy `CameraRecordingControlsView.swift:233-234` | Unit: `PermissionFoundationTests`; physical device — DEV-002 | Copy `cameraRecordingPhotosDenied/PhotosRestricted` |

---

## §9. Counts

| Зона | User-visible states | С fixture (каталог-фикстура и/или UI-тест со скриншотом/runtime) | Fixture нет (detail) |
|---|---:|---:|---:|
| A Entry/Permission | 10 | 9 (A1–A9) | 1 (A10 settings-fallback — без fixture и без теста) |
| B Camera live | 13 | 11 (B1–B8, B11–B13) | 2 (B9, B10 — только Unit) |
| C Pause/Review | 5 | 5 (C1–C5) | — |
| D Cloud review/consent | 11 | 1 (D3 consent fixture root) | 10 (D1, D2, D4–D7×5 — только Unit) |
| E Recording/Export | 12 | 3 (E1, E2, E9 — runtime UI smoke без скриншота) | 9 (E3–E8, E10–E12 — Unit: coordinator/journal/recovery/export-тесты) |
| F Scene Mode | 20 | 7 (F3, F7, F8, F9, F13, F14, F15) | 13 (F1, F5–F6, F10–F12, F16–F17 — Unit/каталог-статика) |
| G Library | 10 | 7 (G1, G2, G4, G5, G7, G8, G10) | 3 (G3 — нет, G6 — презентация отсутствует, G9 — только Unit) |
| H Privacy | 10 | 1 (H1) | 9 (H2–H10 — Unit: privacy/deletion/permission-тесты) |
| **Итого** | **91** | **44** | **47** |

Из 47 состояний без dedicated fixture у 44 есть хотя бы unit/интеграционное покрытие; полностью без тестов — A10; G6 не имеет презентации (тестировать нечего, состояние контракта). Полнота per-state unit-покрытия по каждой строке не аудировалась — проверено существование тест-файлов владельцев (см. receipt, «Метод»).

Канонический fixture-манифест (`SETFixtureCatalog.swift:27-69`, DEBUG): 42 fixture ID (entry 9, camera 11, pause 4, generator 6, library 1, storyboard 1 + foundations/components 10); required modes: ru/en + default/reduce-motion/reduce-transparency/xxl (`:71-77`); owner-approval скриншот-матрица покрывает подмножество (`SETDesignSystemGalleryUITests.swift:17-96`).

## §10. Gaps (честные отсутствия; ничего не выдумано)

1. **`absent (gap)`** — A10 settings-fallback: нет fixture/теста на отказ `openSettings` (`CameraCoachEntryView.swift:494-505`).
2. **`absent` (numeration, не state)** — S05 отсутствует в `CameraOverlayUXPresentation.State` (`:86-105`); между S04 и S06 дыра нумерации.
3. **`absent (gap)`** — Camera live offline-состояние не существует как отдельный user-visible state: локальный продукт; сеть проявляется только в зоне D (`.network`) — покрыть скриншот-фикстурой при закрытии UI-010.
4. **`absent (gap)`** — B9/S10a и B10/S10b не имеют dedicated screenshot fixture (покрытие unit + частично `camera.verification`).
5. **`absent (gap)`** — зоны E (recording) и D (cloud review), H3–H9 (deletion), F5/F11/F12/F16/F17: нет скриншот-фикстур; присутствуют unit/интеграционные тесты.
6. **`absent (gap)`** — G6 rename/renameDuplicate: flow-состояния есть, user-visible презентации нет (`EmptyView`, `SETLibraryProductionView.swift:972-976`); словарные ID `library.rename-*` без fixture.
7. **`absent (gap)`** — G3 pre-load blank: осознанный пустой pre-load без индикатора; решение о loading-индикаторе — UI-011.
8. **`absent (gap)`** — G9 missing/corrupt artifact: copy есть, dedicated fixture/скриншота нет.
9. Catalog `generator.preflight/clarification/progress/cancelled/failure/result` — статичные галерейные экраны (`DesignSystemPreviews.swift:319,468-526`), не runtime-проекция ViewModel; runtime-покрытие генератора — только реальные UI-тесты маршрута. Расхождениеcatalog↔runtime должно закрываться UI-012/UI-013.
10. Физическая приёмка (denied/restricted на устройстве, VoiceOver-джорни, iPad 4-ориентации) — вне этого документа: DEV-002, UI-008, UI-009.
