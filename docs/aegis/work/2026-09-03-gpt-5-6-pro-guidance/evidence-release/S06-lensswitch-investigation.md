# S06 — расследование трёх падений LensSwitch baseline / telephoto preservation

Дата: 2026-09-13. Задача: runbook `docs/aegis/plans/2026-09-13-setos-release-execution.md` (карточка S06) — «расследовать оставшиеся LensSwitch baseline и telephoto preservation failures, не объявлять их вечными flakes».
Вход: HEAD `0733df2cb83c8e3687c31251e11e5d0747052602`, ветка `store`, рабочее дерево грязное (см. «Ограничения»).
Scope изменений: только этот отчёт. Код и тесты не менялись (см. «Что не сделано»).

## 0. Вердикты (сводка)

| # | Тест | Вердикт | Причина |
|---|---|---|---|
| 1 | `CameraViewModelLifecycleTests.testCommittedPauseSurvivesSceneInactiveUntilSuccessfulResume` | **тест-тайминг / изоляция** (не дефект subject) | Тест даёт 2 с на ожидание коммита pause-review, тогда как production-дедлайн pause-анализа — 8 с. Под нагрузкой коммит не успевает; затем `reportSceneInactive()` законно отменяет некоммитнутый pause. Соло 6/6 PASS. |
| 2 | `CameraViewModelLensSwitchTests.testProductionSubjectChangeResetsOwnerBeforeFreshResolutionBaseline` | **устаревшая/несовместимая фикстура** (не дефект subject) | Production-admission baseline требует совпадающего видимого `currentLiveHint`; observation-only seam теста его не публикует и не может. Гейт присутствует уже в HEAD. |
| 3 | `CameraViewModelLifecycleTests.testSelectedTeleLensPresentationSurvivesPauseResumeUntilManagerReportsAgain` | **устаревшее ожидание фикстуры** (не дефект subject) | После resume `CameraViewModel.swift:664` берёт истину у менеджера: `activeLens == .wide` (задаётся `CameraManager.swift:989` у `.ready`-фикстуры), поэтому `currentLens` становится `.wide`, а тест ждёт `.telephoto`. Детерминированно, соло. |

Ни один из трёх не является дефектом subject-кода; правок в production не требовалось. Два теста (2, 3) требуют решения владельца (нужны test-seam/фикстура), один (1) — правки тест-бюджета владельцем тест-сюиты.

## 1. Тест 1 — committed pause не доживает до коммита

### Факт из лога C06 (`/tmp/c06-twb4.log:184–190`)
```
CameraViewModelLifecycleTests.swift:607 XCTAssertTrue failed
CameraViewModelLifecycleTests.swift:619 XCTAssertTrue failed
CameraViewModelLifecycleTests.swift:620 XCTAssertEqual failed: ("idle") is not equal to ("loading(snapshotID: "frame_4000")")
CameraViewModelLifecycleTests.swift:621 XCTAssertEqual failed: ("nil") is not equal to ("Optional("frame_4000")")
CameraViewModelLifecycleTests.swift:622 XCTAssertEqual failed: ("0") is not equal to ("1")
CameraViewModelLifecycleTests.swift:625 XCTAssertNotNil failed
CameraViewModelLifecycleTests.swift:639 XCTAssertTrue failed
```
Ключ — assertion 620: `committedState`, захваченный на `CameraViewModelLifecycleTests.swift:609`, равен **`.loading(snapshotID: "frame_4000")`** (фактическое), а не `.success/.empty/.failure` (ожидаемое `test...:600–606`). Assertions 614–615 прошли (accepted snapshot и displayImage уже есть) — то есть off-main рендер кадра завершился, `isPaused` был выставлен, но **терминальный результат pause-анализа не пришёл**.

### Причина по коду
1. Тест ждёт коммит через `waitUntil` с таймаутом по умолчанию **2 с** (`CameraViewModelLifecycleTests.swift:598–607`, дефолт на `:916`).
2. Production-дедлайн того же результата — **8 с**: `AnalysisPipeline.swift:2291–2292`
   ```swift
   static let productionTimeoutNanoseconds: UInt64 = 8_000_000_000
   ```
   Пока результат не пришёл, `CameraViewModel` держит `pausePresentationState = .loading` (`CameraViewModel.swift:909`) и не коммитит.
3. Через ~2 с ожидание падает, тест идёт дальше и вызывает `reportSceneInactive()`. Он сохраняет review только если `isPauseReviewCommitted == true` (`CameraViewModel.swift:484`), а это требует терминального `.success/.empty/.failure` (`:239–247`). При `.loading` коммита нет → pause отменяется, проекция очищается: отсюда фактические `.idle`, `nil`, `takeNumber 0`, `displayImage nil` в 619–625.
4. Второе ожидание (639, ещё 2 с) уже не может выполниться, т.к. resume запущен поверх отменённого pause.

Итог: subject ведёт себя по спецификации; падает тест, чей 2‑секундный бюджет меньше собственного 8‑секундного дедлайна production-пути. Это делает его чувствительным к задержке low-priority pause-анализа (`lowQueue`, `AnalysisPipeline.swift:3823`) под нагрузкой батча.

### Проверки (соло)
`testCommittedPause...` — **6/6 PASS** (5 повторов + первый прогон), каждый `exit 0`, время 0.82–1.07 с. В батче C06 он падал; в моих объединённых прогонах (A и B, см. §3) — проходил. Точный внешний фактор, сдвигающий анализ за 2 с, воспроизвести не удалось (причина — конкуренция за симулятор/машину, см. «Ограничения»).

### Решение для владельца (не меняет логику решений)
`CameraViewModelLifecycleTests.swift:598–607`: поднять бюджет ожидания коммита выше production-дедлайна (например `waitUntil(timeout: .seconds(10))`), либо добавить DEBUG-хук, управляющий завершением pause-анализа детерминированно. Ожидание самого коммита ослаблять нельзя; менять production-дедлайн/`isPauseReviewCommitted` не нужно.

## 2. Тест 2 — baseline не публикуется: нет видимого live-hint

### Факт из лога
Соло и в батче одинаково:
```
CameraViewModelLensSwitchTests.swift:185 XCTAssertTrue failed        // baselinePublished == false
CameraViewModelLensSwitchTests.swift:188 XCTAssertNotNil failed      // oldIdentity == nil
CameraViewModelLensSwitchTests.swift:211 XCTAssertTrue failed        // cancelled == false
CameraViewModelLensSwitchTests.swift:233 XCTAssertTrue failed        // recovered == false
CameraViewModelLensSwitchTests.swift:234/235 XCTAssertNotEqual failed: ("nil") is equal to ("nil")
```
Фактически первый baseline не появляется (`coachingEpisodeState.phase != .awaitingMovement`), `subject-old-f2` не публикуется, identity и токен остаются `nil`.

### Причина по коду
Тест шлёт кадры через `fixture.pipeline.testingPublishLiveCoachingEpisodeObservation(...)` (`CameraViewModelLensSwitchTests.swift:173–179`). Это DEBUG-вход, который вызывает `prepareLiveFrameSelectionContext` → `publishLiveCoachingEpisodeObservation` (`AnalysisPipeline.swift:6892`), но **не выполняет production-презентацию**, а `currentLiveHint` — `@Published private(set)` (`AnalysisPipeline.swift:3728`) и присваивается только внутри production-публикатора хинта (`AnalysisPipeline.swift:9958–10027`); тест-seam для него отсутствует.

При первичном baseline (`liveEpisodeActionID == nil`) действует admission:
`AnalysisPipeline.swift:7212–7232`
```swift
if liveEpisodeActionID == nil, let candidate, candidate.safetyFamily != .stability {
    guard let primaryAction = plan.primaryAction,
          let visibleHint = currentLiveHint,      // <-- nil в тесте
          visibleHint.frameId == snapshot.frameId,
          visibleHint.actionType == primaryAction.actionType,
          visibleHint.actionId == primaryAction.id,
          visibleHint.semanticActionType?.rawValue == candidate.actionID,
          ...
    else { return }                                  // baseline не публикуется
}
```
`currentLiveHint == nil` → guard не проходит → `return` без события. Это ровно то поведение, что зафиксировано в журнале (см. §4).

Дополнительно: тест-фикс другого потока (`CameraViewModelLensSwitchTests.swift`, грязный diff) уже добавил `targetIdentity` в `makeEpisodeObservation` и `provenance` в `FeatureSample` (строки 674–683, 720–733 diff) — это необходимо, но не адресует обязательное visible-hint-условие.

### Вердикт
Фикстура несовместима с production-контрактом, а не subject сломан. Сам гейт «verification только по видимой проекции» — намеренный (C05: одна видимая команда; комментарий `AnalysisPipeline.swift:7215–7219`), и он **присутствует уже в HEAD** (`/tmp/HEAD-AnalysisPipeline.swift:6465–6472`), то есть не внесён грязными правками.

### Решение для владельца
`CameraViewModelLensSwitchTests.swift:159–238` + `makeProductionEpisodeFrame` (`:689–828`): либо дать DEBUG-seam, публикующий `currentLiveHint`, полностью совпадающий с `plan.primaryAction`/candidate (frameId, actionType, actionId, semanticActionType, а для subject-binding — subjectIdentity/observedSourceRegion), либо прогонять презентацию и handoff одним production-путём. Ослаблять visible-projection admission нельзя (это C05-гейт).

## 3. Тест 3 — telephoto перетирается истиной менеджера (.wide)

### Факт (соло, инструментированный прогон)
```
CameraViewModelLifecycleTests.swift:804 XCTAssertTrue failed
  - S06DIAG lifecycle=running pause=idle lens=wide available=[CameraLens.wide]
```
Ожидалось: `lifecycleState == .running && pausePresentationState == .idle && currentLens == .telephoto`. Фактически два первых конъюнкта выполнены, не выполнен третий: **`currentLens == .wide` вместо `.telephoto`**.

### Причина по коду
1. Тест выставляет VM-состояние напрямую без менеджера: `fixture.viewModel.currentLens = .telephoto` (`CameraViewModelLifecycleTests.swift:785`); через `switchLens` он не идёт, поэтому `CameraManager` остаётся на `.wide`.
2. Resume вызывает `performStart`, где строка `CameraViewModel.swift:664`:
   ```swift
   currentLens = cameraManager.activeLens ?? currentLens
   ```
3. Фикстура `Self.makeManager()` создаёт менеджер с `configuration: .ready` (`CameraViewModelLensSwitchTests.swift:844–855`; аналогичная фикстура в Lifecycle — `CameraViewModelLifecycleTests.swift:827–856`). `.ready` вызывает `configureReadyTestSession()`, который делает `setCurrentLens(.wide)` (`CameraManager.swift:978–998`, строка `:989`), а `LensSwitchTestSessionRunner`/`CameraViewModelTestSessionRunner` его не меняют.
4. Значит `cameraManager.activeLens == .wide` → строка 664 перетирает `.telephoto`. Детерминированно; `currentLens == .telephoto` на `:796` (до завершения `performStart`) ещё проходит, а итоговое ожидание на `:799–804` — нет.

### Вердикт
Не дефект subject: код последовательно считает менеджер источником истины после start/resume (комментарий `CameraViewModel.swift:661–663`), и это поведение уже в HEAD (commit `e950e193`, 2026-09-04). Тест проверяет «представление выбранного tele не сбрасывается», но создаёт это представление без менеджерного подтверждения, чего `.ready`-фикстура дать не может. Ожидание фикстуры несовместимо с committed-контрактом.

### Решение для владельца
`CameraViewModelLifecycleTests.swift:777–806` / `CameraViewModelLensSwitchTests.swift:844–855`: нужен test-seam, позволяющий фикстуре выставить подтверждённый менеджером tele (например DEBUG-сеттер рядом с `CameraManager.setCurrentLens`, `CameraManager.swift:1124`, либо раннер, обновляющий `storedActiveLens`), после чего текущее ожидание `.telephoto` станет осмысленным. Альтернатива — если владелец решит, что презентация выбранного lens не должна перетираться значением менеджера по умолчанию, — менять `CameraViewModel.swift:664`; это уже решение по логике, поэтому оставлено владельцу.

## 4. Статус «известная документированная проблема»

**Тест 2 — подтверждено, что это записанный класс.** `EXECUTION_STATE.md:1274`:
> «The other failure is the existing `testProductionSubjectChangeResetsOwnerBeforeFreshResolutionBaseline`: observation-only ingress never publishes the visible hint required by earlier admission, so no initial episode forms and continuation/reset is never reached. Independent reviewer confirmed this fixture incompatibility; this is not evidence that it failed at clean HEAD.»

`EXECUTION_STATE.md:2069` повторяет: admission-production-путь требует `primaryCandidateSource`/provenance, фикстуре добавлен provenance, «необходимо, но недостаточно», отнесено владельцу episode/verification контракта. `EXECUTION_STATE.md:1570` классифицирует «LensSwitch subject-change ×1 (handover §9: исключённый несовместимый fixture)» как детерминированное pre-existing. `evidence-m9/M9-002-003-lens-labels-continuity.md`:
> «The single failure (`testProductionSubjectChangeResetsOwnerBeforeFreshResolutionBaseline`) reproduces on the clean store tree without any working-tree changes and is registered as a pre-existing failure, out of M9 scope.»

Моё подтверждение: гейт видимого хинта есть в HEAD (`/tmp/HEAD-AnalysisPipeline.swift:6465–6472`), поэтому dirty-дерево его не вносит. Полную проверку «на чистом дереве» я не повторял — `stash/checkout` запрещены, а дерево сейчас не компилируется из-за параллельных потоков (см. §5).

**Тест 3 — подтверждено, что задокументирован как отложенный поведенческий вопрос.** `EXECUTION_STATE.md:2070`:
> «`CameraViewModelLifecycleTests.testSelectedTeleLensPresentationSurvivesPauseResumeUntilManagerReportsAgain` (:804): resume не достигает комбинированного состояния (lifecycleState running + pausePresentationState idle + lens telephoto) при gated resume — поведенческий вопрос pause/resume + lens preservation.»

Мой прогон уточняет: из трёх условий не выполнено только `lens telephoto`; фактическое `.wide`.

**Тест 1 — как записанная pre-existing проблема НЕ подтверждён.** Имя встречается в леджере только в блоке C06 (`EXECUTION_STATE.md:3085`, перечень трёх падений) и в `evidence-m0/test-topology-v2.json`; отдельной записи с root cause/классом для него нет. Опровергаю статус «документированное pre-existing»: это первое расследование с точной причиной (2 с тест-бюджет против 8 с production-дедлайна). При этом `EXECUTION_STATE.md:3085` справедливо не приписывает падения срезу C06-A — моя проверка это подтверждает.

## 5. Команды и результаты

Симулятор один: `platform=iOS Simulator,id=1F680A42-CEB3-43E8-9CED-52F874962A62`, `-derivedDataPath /tmp/shafin-s06-verify`, всегда `-parallel-testing-enabled NO`; сборка `xcodebuild build-for-testing`, прогоны `test-without-building`.

| Прогон | Команда (only-testing) | Exit | Результат |
|---|---|---|---|
| Solo test1 ×5 | `.../testCommittedPauseSurvivesSceneInactiveUntilSuccessfulResume` | 0,0,0,0,0 | 5/5 PASS (0.82–1.07 с); ранее ещё 1/1 PASS |
| Solo test2 | `.../testProductionSubjectChangeResetsOwnerBeforeFreshResolutionBaseline` | 65 (SIGKILL 137 после ассертов) | FAIL, 6 asserts: 185,188,211,233,234,235 |
| Solo test3 | `.../testSelectedTeleLensPresentationSurvivesPauseResumeUntilManagerReportsAgain` | 65 | FAIL, 1 assert: 804 (`lens=wide`) |
| Lifecycle alone | `.../CameraViewModelLifecycleTests` | 65 | 17 tests, 1 failure (только test3); test1 PASS |
| Combined A | `CameraViewModelLensSwitchTests` + `CameraViewModelLifecycleTests` | 65 | LensSwitch 13/6 failures (только test2), test1 PASS, test3 FAIL |
| Combined B | + `CameraManagerLifecycleTests` + `CameraLensSwitchTransactionTests` | 65 | ManagerLifecycle 26/26 PASS, LensSwitchTransaction 4/4 PASS, test1 PASS, test2 FAIL, test3 FAIL |

Повторов test1: 6 соло (все PASS) + Lifecycle-alone + Combined A + Combined B (все PASS). Воспроизвести падение test1 в моих прогонах не удалось; единственное подтверждение — лог C06 `/tmp/c06-twb4.log:184–190`.

### Ограничения прогонов (честно)
- **Параллельные writer'ы**: во время работы дерево неоднократно было некомпилируемым из-за чужих правок (`AnalysisPipeline.swift:5813,9741,10719`; `SETCameraCoachProductionView.swift:2190`; `CameraCoordinateSpaceTests.swift:685`), окно 20:09–20:19. Часть прогонов сделана на ранее собранном бандле.
- **Перегрузка машины**: `load average` 140–340; зафиксированы `Mach error -308 (server died)`, `FBSOpenApplicationServiceError`-класс и `Restarting after unexpected exit, crash, or test timeout`. Поэтому в Combined B сюита Lifecycle перезапускалась, а `testFailedResumeRestoresCommittedPauseReviewAndPresentation` попал в fail-list как жертва перезапуска (не ассерт) — итоговые агрегаты по Lifecycle в этом прогоне не считать чистыми. Solo-прогоны и Lifecycle-alone валидны.
- Инструментирование test3 (`S06DIAG`) было временным и **откачено**; `CameraViewModelLifecycleTests.swift` побайтово совпадает с HEAD (`sha256 a20dfa5fb…`).

## 6. Что честно НЕ сделано

- Не менял production-код и тесты: ни одна из трёх причин не является узким безопасным дефектом subject-кода. Тесты 2 и 3 требуют test-seam/переработки фикстуры (решение владельца episode/lens-контракта), тест 1 — правки тест-бюджета владельцем тест-сюиты.
- Не воспроизвёл падение test1 (0 из 8 попыток) и не назвал конкретный внешний фактор, сдвигающий pause-анализ за 2 с; механизм доказан по коду/состоянию, но не стресс-репро.
- Не проверял «чистое дерево» для теста 2 (`stash/checkout` запрещены); подтвердил только, что admission-гейт есть в HEAD.
- Не трогал `AnalysisPipeline.swift`, `CameraService.swift`, C05-гейты, N7/N11-типы, `project.pbxproj` и прочие запрещённые пути.
