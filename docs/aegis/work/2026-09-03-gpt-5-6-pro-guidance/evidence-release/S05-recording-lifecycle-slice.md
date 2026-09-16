# S05 — recording/media lifecycle slice (source/targeted)

Дата: 2026-09-13. Статус: **needs_review**. Закрыто срезом: сверка historical M7 source PASS
с текущими callers, аудит/подтверждение инвариантов recorder, source/targeted state matrix на
симуляторе, доказательство hint-isolation со стороны recorder, подготовленный (не выполненный)
аппаратный протокол. Осталось **Q04**: реальный A/V sync, аппаратные прерывания, low disk/ENOSPC,
thermal/soak, реальные Photos/микрофон, физический SIGKILL.

Ветка `store`, HEAD `0733df2` (тот же, что в M7-gate). M7 base_for_range `02f03f6`.
Recorder-файлы не переписывались: `git status` по `shafinMultitool/Services/Recording/**` и
`SceneRecordingController.swift` чист; единственное новое — целевой тест (см. §2).

## 1. Сверка historical M7 PASS с текущими callers

M7-gate (`evidence-m7/M7-gate.json`, verdict PASS, source scope) собран на BASE_HEAD `02f03f6`,
который является предком текущего HEAD; все M7-коммиты (`1880e5c..850e150`) входят в HEAD.
Сигнатуры/пути M7 не изменились: `MediaRecording`, `RecordingWriter`, `RecordingOwnerToken`,
`SceneRecordingController.start/stop/releaseAndWait`, `RecordingArtifactStore.*` —
те же, что описаны в M7-001/M7-002/M7-013/M7-019…M7-025.

Изменения callers в рабочем дереве (чужие незакоммиченные правки) проверены и **не нарушают**
инварианты M7:

| Caller / diff | Фактическое изменение | Инвариант M7 | Где соблюдён |
|---|---|---|---|
| `CameraService.swift` (uncommitted, поток C06) | `focusOnTap` → `Bool` fail-closed + `defaultWBValues`; та же правка добавляет `defer { commitConfiguration() }` в `prepareRecorderLocked` | begin/commit всегда закрывается; один writer | `CameraService.swift:304-335` (defer commit), `:423-463` (start gate), `:465-511` (stop compare-and-clear) |
| `SceneGeneratorViewModel.swift` (uncommitted) | перестановка `#if DEBUG` полей, обёрнутые `print` под `#if DEBUG` | recording-пути не затронуты | запись/стоп остаются `:5843-5866`, `:6095-6123` |
| `CameraScreenInteractor.swift` (uncommitted) | `firstIndex(...)!` → `?? 0` для ISO/WB picker | не recording-состояние | `:407-421`; `startRecording/stopRecording :341-395` без изменений |

Единственный caller-файл с реальной recording-правкой (`CameraService` begin/commit) —
собственность параллельного потока и **не тестируется** на симуляторе (см. §7).

Инварианты M7 в текущем дереве (file:line):

- **Один writer/capture owner:** `RecorderContracts.swift:551-557` (`RecordingSourceFence.accepts`);
  `SerializedMediaRecorder.swift:182-209` (exclusive claim + generation fence), `:211-222`
  (release только точного токена), `:389-404` (`admissionVerdict`);
  `SceneRecordingController.swift:184-200` (чужой owner отклоняется при активной записи),
  `:228-274` (owner/token-гейт в `enqueueVideo`); `CameraService.swift:449-463` (ленивый
  cameraCoach-токен), `:725` (принимается только `.cameraCoach`).
- **begin/commit configuration:** `AppleRecordingAdapters.swift:676-683` (commit на success и на
  `canAdd`-отказе); `CameraService.swift:304-335` (defer commit — правка C06).
- **stop/finalize идемпотентность:** `SerializedMediaRecorder.swift:525-568` (cached
  `lastStopResult`), `:570-613` (`finishInFlight` не даёт второго finish), `:636-720`
  (`guard finishInFlight`, terminal result один раз), `:756-799` (release идемпотентен);
  `AppleRecordingAdapters.swift:465-487` (mark finished once), `:489-521` (`finishRequested`
  once), `:542-554` (`completionDelivered` once); `SceneRecordingController.swift:352-410`
  (общий `stopTask`), `:414-427` (общий `releaseTask`).
- **transactional promotion/save/export/delete:** `RecordingArtifactStore.swift:311-449`
  (journal-before-rename + `RENAME_EXCL` + idempotent destination), `:938-1018` stage,
  `:1028-1104` commit, `:1106-1163` rollback, `:1023-1026` removeProjectArtifacts;
  `DBService.swift:633-731` (stage → metadata → commit, rollback, fail-closed);
  `SceneGeneratorViewModel.swift:6174-6220` (promote до persist, pending-очередь, ID-ledger);
  `ScenePhotosExportService.swift:56-94` (success только после Photos change commit).

## 2. Файлы (sha256 рабочего дерева) и зачем

| Файл | sha256 | Зачем в срезе |
|---|---|---|
| `shafinMultitoolTests/RecordingHintIsolationTests.swift` (**новый**) | `f7f36bd7f7fe704671edebf1034e948694aa950621cb728427ab8e48436357a9` | S05-пункт 4 со стороны recorder: hint-канал не меняет recording-проекцию и sound policy |
| `shafinMultitool/Services/Recording/RecorderContracts.swift` | `062ab187c26551f6752ddf8150cd6cee5fc31c711363375927ea784f088bb7e6` | контракт owner-fence/lifecycle/terminal-артефакта, сверен без изменений |
| `shafinMultitool/Services/Recording/SerializedMediaRecorder.swift` | `8fc23dae08d1a6fd4473b207c7a653b6ec0c09229df88b9eb58114a90b329c58` | единственный writer, timebase, stop/finalize, cleanup-honesty |
| `shafinMultitool/SceneGeneratorModule/Services/SceneRecordingController.swift` | `0ad357368d42e14f20a542647be16af34b7d50218a112a8a74a6f669645d0f44` | entry point controller: preflight→prepare→claim→start, stop/release sharing |
| `shafinMultitool/Services/Recording/RecordingArtifactStore.swift` | `c5cccfecc5c14043492de4abb1ad833dc74e95541cba817c395d71338b412e7a` | transactional promote/retention/orphan/deletion |
| `shafinMultitool/Services/Recording/AppleRecordingAdapters.swift` | `15a7a97a0650dc2cbdd77f63b7a5256bde373e59e1b2f6281ec658ee8ce87156` | AVAssetWriter config/finish/discard, ENOSPC typing |
| `shafinMultitool/Services/Recording/RecordingPreflight.swift` | `cf5960a6fe7b39c7aee1f7b5fb43cb9da81dc808e859fbc86a82b0896c33be4a` | denied mic / audio session / disk preconditions до создания writer |
| `shafinMultitool/Services/Recording/PendingRecordingJournal.swift` | `19f137b2c736c0b9e6340302bf222c3bcd8c867d872ce16d6b182816c393b8fa` | atomic journal для promoted/pending |
| `shafinMultitool/Services/Recording/ScenePhotosExportService.swift` | `46294b8b1a49595b3dcdcc66e335e62890a2f9bdb6755dd76cd1b69e55fef00f` | Photos denied/restricted/failed, success только после commit |
| `shafinMultitool/Services/Recording/AudioSessionCoordinator.swift` | `a943e678be48e4ed8a79734c7bb48ad8bd523ded619a838b79d4f95a2458a2e6` | interruption/route/reset без auto-resume |
| `shafinMultitool/Services/CameraService.swift` (dirty, чужой) | `d8f64930c40f270e8e559bce4fcd60c1625ad9ef87b111156365189795435e43` | legacy writer: begin/commit + token fence (правка C06, не моя) |
| `shafinMultitool/Services/DBService.swift` | `935e13f07cd5bb5b682da2b9ddc21e19a39a08e60726f9831d37708a3106a3ee` | transactional project+artifact deletion и cold-launch maintenance caller |

## 3. Команды, exit code, результат

```bash
# Симулятор один: iPhone 17e, id=1F680A42-CEB3-43E8-9CED-52F874962A62
xcrun simctl shutdown 1F680A42-…; xcrun simctl boot 1F680A42-…; xcrun simctl bootstatus 1F680A42-… -b   # ok

xcodebuild build-for-testing -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /tmp/shafin-s05-verify -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
# ** TEST BUILD SUCCEEDED **, exit 0

xcodebuild test-without-building … те же destination/derivedDataPath/-parallel-testing-enabled NO \
  -resultBundlePath /tmp/shafin-s05-slice.xcresult  <22 × -only-testing:shafinMultitoolTests/…>
# XCODEBUILD_EXIT=0; Executed 274 tests, with 0 failures (0 unexpected); 0 "Test Case … failed"
```

Прогон (274 теста, 22 сюиты, все passed): `SerializedMediaRecorderTests` 47,
`SceneSaveLoadTests` 28, `SceneRecordingControllerTests` 26, `CameraManagerLifecycleTests` 26,
`DBServiceConcurrencyTests` 22, `AppleRecordingAdaptersTests` 16, `SceneWorkspaceTeardownTests` 16,
`RecordingPreflightTests` 13, `RecordingRecoveryAndRetentionTests` 13, `RecordingContractV1Tests` 9,
`RecordingArtifactPromotionTests` 8, `CommercialShellLifecycleAdapterTests` 7,
`ARSessionOwnershipTests` 6, `AudioSessionCoordinatorTests` 6, `RecordingLifecycleTransitionTests` 6,
`SceneJourneyContractTests` 6, `PendingRecordingJournalTests` 5, `RecordingDiagnosticsTests` 5,
`ScenePhotosExportServiceTests` 5, `RecordingStartTeardownRaceTests` 2,
`GenerationBackgroundRecoveryTests` 1, `RecordingHintIsolationTests` 1 (новый).
Durable xcresult: `/tmp/shafin-s05-slice.xcresult`. Параллельные клоны отключены; флейков не было.

## 4. Source/targeted state matrix (симулятор)

| # | Ячейка | Что делали | Ожидалось | Получено | Вердикт |
|---|---|---|---|---|---|
| 1 | Entry: Scene/AR REC | `SceneRecordingController.start` → preflight→prepare→claim→start | один recorder, один source token, `.recording` | `SceneRecordingControllerTests`, `RecordingLifecycleTransitionTests` passed | PASS source |
| 2 | Entry: sound-off (явный silent режим) | `startRecordingWithoutSound` → `.disabled + .explicitVideoOnlySelection` | 0 запросов микрофона, нет audio driver | `testSoundOffSkipsMicrophoneAndAudioSessionAndUsesDisabledContract`, `testDisabledAudioNeverCreatesDriver` passed | PASS |
| 3 | Entry: legacy CameraScreen | `CameraService.startRecording` | один writer, блок при preparing/finishing, cameraCoach-токен | `testCameraServiceStopPreservesReplacementClaimMadeDuringUnlockedCleanup` passed; AVFoundation-путь на симуляторе не исполняется | PASS source / Q04 |
| 4 | Route switch / teardown | teardown останавливает запись и ждёт finalize до persist/detach | один awaited stop, `released` терминален | `testTeardownAwaitsRecordingFinalizationBeforePlaybackAndPersistence`, `…PersistenceBeforeTerminalRecordingReleaseAndDetach`, `RecordingStartTeardownRaceTests` passed | PASS source |
| 5 | Background | background-lease → workspace teardown; cold recovery | остановка ровно один раз, сходимость через journal | `CommercialShellLifecycleAdapterTests` 7/7, `GenerationBackgroundRecoveryTests`, `testRouteBackgroundHookUsesTheSameIdempotentWorkspaceTeardown` passed | PASS source / Q04 |
| 6 | Cancel/error | stop без кадров, append failure, ENOSPC, timeout финализации | typed failure, нет вымышленного артефакта | `testStopWithoutVideoFramesNeverFinalizes`, `testVideoAppendFailureReturnsRecoverableArtifact`, `testStoragePressureAppendFailsTyped…`, `testFinalizationTimeoutFailsTypedAndLateCallbackCannotReviveTheTake` passed | PASS |
| 7 | Denied microphone | denied/restricted/unavailable | recorder не создаётся, explicit retry без downgrade | `testMicrophoneDenialDoesNotCreateOrStartARecorder`, `testDeniedMicrophoneOffersExplicitSilentRetry…`, `testMicrophoneRestrictionOffersRecheckRecovery`, `testDeniedMicrophoneFailsSoundRequiredTake` passed | PASS source |
| 8 | Denied Photos | add-only denied/restricted/failed/in-flight | typed outcome, библиотека не тронута | `ScenePhotosExportServiceTests` 5/5 passed | PASS source / Q04 |
| 9 | Audio absent | `.disabled`; `.required`+unavailable; audio до origin | нет driver; typed failure; сэмплы отклонены | `testRequiredAudioFailureIsTyped`, `testAudioBeforeOriginAndOutOfOrderAudioIsRejectedAndCounted`, `testDisabledAudioNeverCreatesDriver` passed | PASS |
| 10 | Restart recovery | K0–K4, cold-launch converge, retention, orphans, delete-journal | ровно одна валидная ссылка либо честный failure | `RecordingArtifactPromotionTests` 8/8, `RecordingRecoveryAndRetentionTests` 13/13, `PendingRecordingJournalTests` 5/5, `SceneSaveLoadTests` 28/28 passed | PASS source / Q04 |
| 11 | Hints ↔ recording state | toggle hints + live hint frame + hint pause review | проекция записи и sound policy не меняются | `RecordingHintIsolationTests` 1/1 passed | PASS source |
| 12 | Hints ↔ voice capture | hint-канал не выбирает `.required` | голос не пишется без явного режима | `RecordingHintIsolationTests` + recorder-гейт `appendAudioOnQueue` (`SerializedMediaRecorder.swift:459-463`) и factory-гейт (`SceneRecordingController.swift:119-124`) | PASS source |

## 5. Доказательства двух ключевых требований

**Ошибка cleanup не даёт успешный artifact.** Артефакт строится только при
`timebase.acceptedVideoCount > 0` (`SerializedMediaRecorder.swift:722-736`); при finish-ошибке
recoverable-артефакт берётся **только** из явной аттестации writer'а
(`:657-683`, `RecordingWriterError.finishFailed(recoverableArtifact:)`), иначе `nil`.
AVAssetWriter-адаптер при незавершённом writer'е удаляет неполный output и возвращает
`.finishFailed(recoverableArtifact: nil)` (`AppleRecordingAdapters.swift:499-520`), а `discard()`
удаляет неполный файл (`:523-540`). Пины: `testFinishFailureDoesNotInventRecoverableArtifact`,
`testFinishFailureUsesOnlyExplicitWriterAttestation`, `testStopWithoutVideoFramesNeverFinalizes`,
`testStoragePressureAppendFailsTypedWithoutRecoverableArtifactAndLeavesNoFrames`. Для удаления:
pre-commit partial unlink откатывается (`RecordingArtifactStore.swift:1095-1103`,
`testStagedArtifactCommitRollsBackAfterInjectedPartialUnlink`), post-commit сбой удаления
tombstone'а логируется и **не** превращается в rollback-успех и не создаёт artifact
(`:1080-1093`); `DBService` при провале rollback отдаёт `.persistence`, при artifact-ошибке —
`.artifactCleanup` (`DBService.swift:703-729`). Все прогоны зелёные.

**Подсказки не меняют recording state и не пишут голос.** На стороне recorder'а единственный
вход аудио — `appendAudioOnQueue`, который первым делом требует
`configuration.audioMode == .required` (`SerializedMediaRecorder.swift:459-463`); audio driver
создаётся фабрикой только для `.required` (`SceneRecordingController.swift:119-124`), а `.required`
выбирается исключительно пользовательским `recordingSoundEnabled`
(`SceneGeneratorViewModel.swift:1625-1629`). Hint-канал (`toggleHintsEnabled` `:5686-5698`,
live-frame `:6244-6309`, pause review `:5700+`) не вызывает ни `startRecording`, ни
`setRecordingSoundEnabled`. Новый `RecordingHintIsolationTests` прогоняет полный hint-lifecycle
(включение, live hint frame с drain, pause review, выключение) и проверяет равенство полной
наблюдаемой проекции (`isRecording`, `isRecordingStarting`, `isRecordingFinalizing`,
`recordingSoundEnabled`) до/после — passed. Это независимое от C07 (VoiceOver-канал)
подтверждение со стороны recorder'а.

## 6. Аппаратный протокол (Q04-пакет; НЕ выполнен, гейты не отмечены)

Протокол уже залочен и расширен Q03: `docs/implementation/device-tests/recording-v1.md`
(v1 steps 1–15 + v3 checks 16–19) и `evidence-release/Q03-device-run-packet.md`.
S05 не дублирует handbook; ниже — точная привязка S05-требований к шагам для владельца.
Все статусы стартуют `not_executed` и остаются такими до реального device-run.

| S05-требование | Шаг recording-v1.md | Роль evidence (импортёр) | Статус |
|---|---|---|---|
| A/V sync | step 7 `rec.av_sync` (клэп/вспышка, 30 s, ≤80 ms start/end) | device-origin `audio_sync_report` (`sync_error_start_ms`/`sync_error_end_ms`) | not_executed |
| Прерывания (звонок) | step 5 `rec.audio_interruption` (partial finalize ровно один, без auto-resume) | reference count + audio-track presence | not_executed |
| Background/suspension | step 6 `rec.background` (finalize под lease или cold recovery) | relaunch state dump | not_executed |
| Low disk / ENOSPC | step 9 `rec.low_disk` (start rejected; active take fails typed, media цела) | preflight screenshot + media checksums | not_executed |
| Thermal/energy/soak | step 15 `rec.soak` + `hw.thermal_soak` (30 min mixed) | `thermal_sample_count`, `thermal_states_seen`, `benchmark_summary` | not_executed |
| Route switch | step 1 `rec.start_stop` + AR-side `ar.*` route checks | project list + Pending/Projects listing | not_executed |
| Photos denied | step 12 `rec.photos_export` | Photos verification + export receipt | not_executed |
| OS kill/recovery | step 10 `rec.os_kill` (K0–K4) | per-point relaunch state dump | not_executed |

Правило Q03 сохраняется: screenshot не является доказательством A/V sync/thermal; legacy
CameraService-путь (AVFoundation writer начинается только при наличии физического capture device)
на симуляторе не проверяется и обязан быть пройден на устройстве шагами 1–3/9/15.

## 7. Что честно НЕ сделано

- Ни один аппаратный гейт не выполнен и не отмечен PASS: A/V sync, реальные прерывания,
  background suspension, ENOSPC/low disk, thermal/soak, Photos/микрофон, SIGKILL — Q04.
- Legacy `CameraService` AVFoundation recording path не исполнялся на симуляторе (нет
  `AVCaptureDevice`); begin/commit-правка в `CameraService.swift` — чужая (C06, uncommitted),
  сверена чтением, отдельного теста не имеет.
- Recorder не переписывался и второй не строился: production-код не менялся.
- `recording-v1.md` не редактировался (его уже расширил Q03) — во избежание конфликта с
  параллельным потоком; аппаратный протокол S05 дан привязкой, а не копией.
- Не проверялись real A/V sync content-markers и полная device metadata (duration/audio треки
  реального устройства) — probe покрыт unit-уровнем (`AppleRecordingMediaMetadataProbe`), но не
  физическим артефактом.
