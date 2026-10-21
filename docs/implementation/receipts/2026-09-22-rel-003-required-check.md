# REL-003 — минимальный required check: скрипт + CI workflow + локальная верификация

Date: 2026-09-22. Candidate HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`).
Рабочее дерево было и осталось dirty (чужой CAM-009 diff + чужие untracked-артефакты +
параллельная sibling-волна правок UI/localization — см. «Наблюдение о гонке» ниже).
Ни один чужой файл не изменён; commit/push не выполнялись (файлы остались untracked по
границам задачи); каноническая строка трекера оставлена оркестратору.

## Task

REL-003 (tracker §16, P1, Depends REL-001): «Добавить минимальный required check: source
validation, privacy/provenance, focused unit/UI build. Check / Done when: Clean CI runner
воспроизводит; artifact/log retention configured.»

Использованы канонические lane'ы `docs/implementation/test-command-matrix-v1.md`:
M0 smoke (blocking-минимум, 133 теста) + `scripts/validate_privacy_manifest.sh` + два
ML contract-валидатора из REL-001 M4 (source sanity). Документированный обход Xcode 27.0
drift из `receipts/2026-09-22-cam-003-calibration-contract.md` воспроизведён как шаг 2.

## Changes (новые файлы, Own scope)

1. `scripts/required_check.sh` (executable) — детерминированный локальный required-check
   из 4 шагов, fail-fast, без ретраев и без маскирования:
   - **Step 1 — source sanity:** `python3 ml/camera_coach/contracts/check_production_heads_v1.py`
     (ML-002, stdlib-only) и `python3 ml/camera_coach/contracts/validate_camera_release_label.py`
     (DATA-001: schema + positive fixture + 16 named negative mutations + boundary).
   - **Step 2 — Pods prebuild** (задокументированный обход Xcode 27.0): `xcodebuild
     -workspace … -scheme Pods-shafinMultitool … IPHONEOS_DEPLOYMENT_TARGET=15.0 build`
     в scratch DerivedData; override только командной строкой, ни один файл репозитория
     не меняется.
   - **Step 3 — M0 smoke lane** из test-command-matrix-v1.md §3: `xcodebuild -project
     shafinMultitool.xcodeproj -scheme shafinMultitool -sdk iphonesimulator
     -destination id=1F680A42-CEB3-43E8-9CED-52F874962A62 -derivedDataPath <scratch>
     -parallel-testing-enabled NO -collect-test-diagnostics never` + ровно 13
     `-only-testing` масок матрицы (5 классов: CameraAdviceSafetyGateTests 19,
     GoodFramePreservationPolicyTests 8, ActionVerifierTests 28, UserMovementObserverTests 39,
     SemanticTipPlannerTests 31; + 7 методов AnalysisPipelinePresentationTests; +
     CameraCoachClosedLoopTests/testFreshReplanningPreservesEpisodeThroughVerification).
     Инвариант «zero-test run = failure» реализован тройной проверкой: (a) парсинг
     финальной строки `Executed N tests, with F failures`; (b) `N == 133` (заявленное
     число матрицы: 125 + 8); (c) каждая маска должна наблюдаться в сыром логе
     (`Test Suite '<Class>' passed` / `Test Case '<method>]' passed` fixed-string);
     отсутствие summary или `N == 0` = FAIL; `F > 0` = FAIL с распечаткой упавших
     `Test Case` строк — красный не маскируется.
   - **Step 4 — privacy/provenance:** `scripts/validate_privacy_manifest.sh
     --source-manifest shafinMultitool/PrivacyInfo.xcprivacy --app <scratch DerivedData>/
     Build/Products/Debug-iphonesimulator/shafinMultitool.app` — source + собранный бандл
     (root + SnapKit nested, 4 required-reason записи, 0 unexpected manifest paths).
   - Scratch (DerivedData + логи) только в `/tmp`; `REQUIRED_CHECK_KEEP=1` сохраняет для
     диагностики, по умолчанию удаляется на выходе. Переменные-оверрайды (не секреты):
     `REQUIRED_CHECK_DESTINATION`, `REQUIRED_CHECK_DERIVED_DATA`, `REQUIRED_CHECK_KEEP`.
     Существующие тесты/схемы/скрипты не изменялись.
2. `.github/workflows/required-check.yml` — prepared CI config: `macos-latest`,
   `actions/checkout@v4`, запись тулчейна в лог, динамический резолв доступного
   iPhone-симулятора (hosted UDID не совпадает с локальным пином), запуск
   `scripts/required_check.sh` c `REQUIRED_CHECK_KEEP=1`, upload логов
   `actions/upload-artifact@v4` с `retention-days: 14` (env
   `REQUIRED_CHECK_ARTIFACT_RETENTION_DAYS`, конфигурируемо, не секрет), `if: always()`.
   В заголовке файла явно задокументировано: **hosted-runner воспроизводимость НЕ
   верифицирована**; включение CI, выбор образа/Xcode и любые будущие секреты — решение
   владельца (tracker §0/§19). Секретов workflow не использует.
3. Receipt: этот файл.

## Локальная верификация (CHECK) — 5 прогонов, честная хроника

Среда: Xcode 27.0 (27A266a), iOS SDK 27.0, destination id=1F680A42… (iPhone 17e).
HEAD во всех прогонах `f8b6afd…`; дерево одновременно правили sibling-исполнители
(см. ниже). Все временные файлы — в `/tmp`.

| Прогон | Длительность | Результат скрипта | Причина |
|---|---|---|---|
| 1 (23:26) | 71 s | rc=1 | Steps 1–3 зелёные; **M0 lane зелёный: `Executed 133 tests, with 0 failures (0 unexpected) in 10.875s`, TEST SUCCEEDED**; упала собственная проверка масок в скрипте: grep-паттерн `Test Case '<method>' passed` не совпадал с фактическим форматом лога `Test Case '-[Target.Class method]' passed (…)`. Скрипт честно отчитался красным; паттерн исправлен на fixed-string `"<method>]' passed"`. Это баг скрипта, не продукта. |
| 2 (23:28) | 20 s | rc=1 | Красный по внешней причине: компиляция app target упала (`cannot find 'SETLibraryLoadingState'/'SETLibraryRenamePanel' in scope` в `SETLibraryProductionView.swift`) — sibling-волна писала этот файл (mtime 23:32:24) во время сборки; сработал zero-test rule (run прерван до тестов), скрипт не маскировал. |
| 3 (23:36) | 50 s | rc=1 | Аналогичная гонка: компиляция тестового бандла упала на `CameraCoachAccessibilityPresentationTests.swift`, который sibling правил в 23:36:24 (40 секунд до запуска). Zero-test rule, fail-fast. |
| 4 (23:40) | 36 s | rc=1 | Новый untracked-файл sibling'а `CameraCoachDynamicTypeLayoutTests.swift` создан в 23:40:42 посреди сборки (частичная запись → `Cannot find 'scaledObservation' in scope`). Zero-test rule, fail-fast. Step 4 дополнительно выполнен вручную на собранном в этом прогоне app-бандле: **PASS** (source+built app, root=1, SnapKit=1). |
| 5 (23:47) | 83 s | **rc=0, PASSED** |Sibling починил свой файл в 23:46:15, дерево затихло. Полный зелёный: `Executed 133 tests, with 0 failures (0 unexpected) in 11.070 (11.103) seconds`, rc=0, все 13 масок наблюдены, Step 4 PASS. |

Финальный вывод прогона 5 (без raw-лога):

```text
PASS  source sanity: check_production_heads_v1.py (production heads contract)
PASS  source sanity: validate_camera_release_label.py (schema + positive/negative fixtures)
PASS  Pods prebuild (deployment-target override, scratch derived data)
PASS  M0 smoke lane: 133 tests executed, 0 failures, all declared masks observed (serial)
PASS  privacy manifest: source + built app validated (root + SnapKit nested, 4 required-reason entries)
REQUIRED CHECK: PASSED
```

Побочно подтверждено правилами матрицы: известные diagnostic-страницы (3 perceptual
метода CAM-009, NIMA payload, device-gated) в M0 не входят и скриптом не вызываются —
маскировать нечего и нечем; любой неизвестный красный останавливает check (прогоны 2–4
это демонстрируют).

## Наблюдение о гонке (факт для владельца)

Рабочее дерево — общее: во время окна верификации (23:26–23:48) sibling-волна меняла
≥10 файлов (`SETLibraryProductionView.swift`, `SETComponents.swift`,
`SETCameraCoachProductionView.swift`, `CameraOverlayUXPresentation.swift`,
`SETLocalization.swift`, `SETMetrics.swift`, `Localizable.xcstrings`,
`SETLibraryModelTests.swift`, новые untracked-тесты). Три красных прогона 2–4 —
исключительно эти гонки/промежуточные состояния чужих файлов; ни одного падения
собственно M0-ассертов не зафиксировано. Следствие: локальный required check на общем
dirty-дереве имеет смысл запускать на затихшем дереве; CI на чистом checkout (как в
подготовленном workflow) этой проблемы не имеет.

## Границы и что НЕ заявляется

- Не заявляется, что hosted GitHub Actions runner воспроизводит check: ни один push
  против hosted runner не выполнялся (это и есть remaining owner action). В workflow
  добавлены шаг записи тулчейна и динамический резолв симулятора как best effort, но
  зелёным evidence остаётся только локальный прогон.
- Число 133 зафиксировано на момент REL-001; добавление/удаление тестов в замаскированных
  классах даст честный FAIL с сообщением о расхождении с матрицей — это требование
  «заявленные тесты исполнены», а не подгонка.
- Скрипт не покрывает M1–M7/M-UI lane'ы (это последующие задачи, не REL-003) и не
  заменяет CAM-001/CAM-022 regression matrix.
- Privacy-валидация в скрипте завязана на app-бандл из Step 3 (build-for-testing собирает
  app target); отдельно от тестов она не запускается — это сознательная связка
  «артефакт последнего шага проверяется на нём же».
- Секреты не нужны; если появятся — новое owner-решение.

## Что останется владельцу

1. Включить CI: закоммитить `scripts/required_check.sh` +
   `.github/workflows/required-check.yml` (сейчас untracked по границам задачи) и
   подключить GitHub Actions к репозиторию; выбрать образ runner'а и версию Xcode.
2. Выполнить один контрольный hosted-прогон и приложить его к этому receipt — до этого
   reproducibility на clean runner остаётся незакрытым пунктом строки REL-003.
3. Retention 14 дней настроен в workflow (артефакты-логи); при желании поменять
   `REQUIRED_CHECK_ARTIFACT_RETENTION_DAYS`. Секретов на текущем шаге нет.
4. При изменении набора M0-тестов обновить `EXPECTED_M0_TESTS`/маски синхронно с
   `docs/implementation/test-command-matrix-v1.md`.
