# Camera Coach execution status

Последнее обновление: 16 августа 2026 года.

## Глобальная цель

Автономно довести всю систему до production-level, submission-ready App Store candidate по `docs/implementation/PRODUCTION_ACCEPTANCE.md`. Camera Coach остаётся первичным продуктом, Scene Mode — вторичным; parent/main-chat Sol владеет архитектурой, low-level task contracts, tracker и одной bounded risk-based milestone acceptance, а отдельные user-visible Codex threads GPT-5.6 Luna / Max владеют всей реализацией, тестированием, correction loops, task-level independent review и verification. Task/milestone/build completion не закрывают глобальную цель. Push, PR, платные действия, TestFlight/App Store submission и юридические решения не разрешены автоматически.

## Hard orchestration policy (current)

- Every new executor, reviewer, correction-loop or verification worker MUST be a separate USER-VISIBLE Codex chat/thread, never a hidden collaboration subagent.
- When continuing the current checkout, create the thread in the project-local environment (`environment.type=local`) with explicit `model=gpt-5.6-luna` and `thinking=max`; hidden collaboration spawning is forbidden.
- The main chat is the sole Sol orchestrator.
- Visible Luna / Max threads own all implementation, testing, correction loops, task-level independent review and verification.
- The parent/main-chat Sol may own architecture, low-level task contracts, the tracker and one bounded risk-based milestone acceptance only. It may create/manage visible Luna / Max threads, but MUST NOT create hidden workers or any Sol, Terra or inherited-model worker thread.
- If a visible Luna / Max thread cannot be created, fail closed; never silently use a hidden task/subagent or substitute another model. The installed native adapter is not reinstalled/reloaded, so native roles are not a valid execution path.
- The active system goal text is immutable through the goal API while active; the durable goal-policy amendment is recorded in `docs/aegis/work/2026-08-15-camera-coach-release/10-intent.md` and `20-checkpoint.md`.
- Existing historical queue labels and evidence that mention past Sol reviews or verification are preserved as historical evidence only. They are not current routing permission and do not authorize task-level Sol review or any Sol/Terra worker thread.

## Текущий milestone

`M0 — product and release baseline`

Цель milestone: получить воспроизводимую базовую сборку, убрать противоречия в product source of truth, определить фактический Release bundle и превратить P0/P1 риски в задачи с точным ownership.

## Baseline snapshot

- Git: ветка `store`, base `018ceab` до bootstrap-коммита.
- Текущий принятый integration baseline: ветка `store`, `9f2f5f2`; CC-011E remains accepted at its historical baseline, the bounded CC-007/CC-010E integration remains recorded at `ff9ce3e`, and the bounded CC-011C UI slice is recorded at `9f2f5f2`.
- Tracked source до bootstrap не изменён.
- `xcodebuild ... build-for-testing` для `generic/platform=iOS` прошёл 15 августа 2026 года.
- В проекте есть app target, unit-test target и отдельный `shafinMultitoolUITests` target; CC-011C принимает только bounded real-process root smoke.
- Test build bundle: около 1,2 ГБ.
- Главный bundled P0: `dataset_v9_event_sft_q4_k_m.gguf`, около 1,0 ГБ.
- `Resources/DeviceBenchmark`: около 51 МБ и 182 файла; benchmark-изображения и JSONL попадают в app bundle.
- Core ML models: около 47 МБ в исходном дереве.
- `PrivacyInfo.xcprivacy` не найден.
- Usage descriptions существуют, но их UX, язык, фактическая необходимость и denied/restricted flow не проверены.
- `SceneDelegate` сохраняет benchmark branch первым; normal non-benchmark branch теперь открывает `CommercialShell` с Camera Coach route. CC-011C bounded true-process root smoke, включая portrait/landscape root no-crash checks, принят; full portrait behavior, camera permission UX and saved-project access remain unverified.
- Deep Research принят с рекомендацией `NARROW`; публичная монетизация отложена до instrumented beta.

## Очередь первой волны

The queue below preserves historical lane labels and evidence for traceability. The current hard policy above supersedes any historical `Sol verification`, `Sol review`, `Terra / High` or similar wording: all current/future executor, reviewer, correction-loop and verification work must be separate visible Luna / Max threads; the parent/main-chat Sol has only the bounded milestone acceptance described above.

| ID | Состояние | Lane | Зависимости | Краткий результат |
| --- | --- | --- | --- | --- |
| CC-000 | accepted | Sol | — | Product/research baseline синхронизирован |
| CC-001 | accepted | Luna / Max | bootstrap commit | Clean/contaminated bundle inventory принят; Release partial = 1 198 316 КБ, GGUF contamination = 1 094 912 КБ |
| CC-002 | accepted | Luna / Max | CC-001 | Release = 72 728 КБ без DeviceBenchmark/GGUF; Debug сохраняет оба benchmark-пака |
| CC-003 | accepted | Luna / Max | bootstrap commit | Все permission/data paths инвентаризированы; подтверждены отсутствующие denied/restricted/Settings flows и privacy manifest |
| CC-003A | accepted | Luna / Max | CC-003 | Typed permission foundation принято: current-SDK adapter, add-only Photos, coalesced prompts, 10/10 focused tests |
| CC-004 | accepted | Luna / Max | accepted audit baseline | 16 provenance dispositions accepted; 8 missing, 2 exclude, 4 development-only, 2 verified |
| CC-005 | accepted | Luna / Max | bootstrap commit | 29 test files классифицированы; подтверждён unit-hosted pseudo-UI test и механический план настоящего UI-test target |
| CC-006 | accepted | Luna / Max | bootstrap commit | Проверен launch graph; принят `SceneDelegate` commercial-shell seam, persistence/benchmark boundaries зафиксированы |
| CC-007 | partially_accepted | Sol → Luna | CC-006, CC-008 | Normal Camera Coach launch and bounded CC-011C root smoke are accepted separately; full product/UI, permission, orientation and saved-project evidence remain open |
| CC-007A | accepted | Luna / Max | CC-006, CC-008 | Single-child shell routing contract принят; launch graph не изменён, release-ready не заявляется |
| CC-008 | accepted | Sol | product baseline | UX state machine принята явным запуском полного автономного implementation pipeline и предыдущими product/UI решениями owner |
| CC-008A | accepted | Luna / Max | CC-008, CC-010B | Truthful live surface для уже доказуемых S04/S06/S07/S10c принят; release-ready не заявляется |
| CC-009 | accepted | Luna / Max | CC-003, CC-006 | Подтверждены три media contour и отсутствие awaited exclusive route/session owner |
| CC-010A | accepted | Luna / Max | CC-009 | Awaitable lifecycle, typed failures и late-callback fence; 7/7 focused tests прошли |
| CC-010A1 | accepted | Luna / Max | CC-010A, CC-010B1 | Failed-start rollback принят после correction loop; generic build и 22/22 пересекающихся focused tests прошли |
| CC-010A2 | accepted | Luna / Max | CC-010A | Atomic motion snapshot принят после correction loop; 4/4 focused tests прошли |
| CC-010A3 | accepted | Luna / Max | CC-010A | Transactional lens input принят; worker `85fc422` → `15aa4e5`, 16/16 intersecting tests прошли |
| CC-010A4 | accepted | Luna / Max | CC-010A3 | Confirmed lens presentation принят; worker `993510e` → `b38f9fb`, 15/15 intersecting tests прошли |
| CC-010B | accepted | Luna / Max | CC-010A | Детерминированный unregister/drain, release/re-register и stale-result fences; 23/23 focused tests прошли |
| CC-010B1 | accepted | Luna / Max | CC-010B | Coherent latest-frame envelope и session-local reset приняты; 12/12 focused tests прошли |
| CC-010C | partially_accepted | Sol → Luna / Max | CC-009, recording policy | Policy-neutral serialized recorder core принято; production wiring/save policy остаются gated |
| CC-010C-A | accepted | Luna / Max | CC-009 | Изолированное recorder core принято после Sol-review, canonical build и 29/29 simulator tests |
| CC-010D | draft | Luna / Max | CC-010C | Awaited Scene exit/background AR and persistence teardown remains incomplete |
| CC-010E | partially_accepted | Luna / Max | CC-007, CC-010A, CC-010D | Bounded exclusive lease accepted at `ff9ce3e`; Scene library root may release, deeper workspace/modal remains blocked |
| CC-010F | ready | Luna / Max | CC-008, CC-010A | In-place orientation continuity и media metadata готовы к реализации |
| CC-010G | accepted | Luna / Max | CC-010A | Stateless thermal budget принят; worker `3212923` → `6bfd3a4`, 6/6 focused tests прошли |
| CC-011 | decomposed | Luna / Max | CC-001, CC-005 | Privacy manifest, deterministic bundle gate и real UI-test target разложены |
| CC-011A | accepted | Luna / Max | CC-013A | App-owned manifest и validator приняты; Release содержит ровно app + SnapKit manifests |
| CC-011B | accepted | Luna / Max | CC-002, CC-011A | Единый clean-HEAD gate принят: Debug, Release, privacy, allowlists, sizes и 6 contamination fixtures |
| CC-011C | partially_accepted | Luna / Max | CC-007, CC-008 | Bounded real UI target/root smoke принят at `9f2f5f2`: 4/4 process tests passed; permission UX, full orientation/product behavior and deeper Scene evidence remain open |
| CC-011D | accepted | Luna / Max | CC-013B1, CC-013C1 | Два offline provenance validator приняты как fail-fast stages canonical release gate |
| CC-011E | accepted | Luna / Max | CC-005, raw full-target audit | Test/contract hygiene accepted at `6ff225d553ae654298dda70b9c779c1226c31800`; E1–E4 gave 104 executed, 102 passed, 2 intended skips, 0 failures; canonical clean gate passed all stages |
| CC-012 | decomposed | Sol → Luna | CC-008 | Privacy-safe activation and coaching-loop event contract |
| CC-012A | accepted | Luna / Max | CC-003, CC-008 | 12 instrumentation owners, 59 active events, 63 properties; activation требует action + independent verification |
| CC-013A | accepted | Luna / Max | CC-004 | ARVideoKit удалён; SnapKit 5.7.1 privacy bundle доказан в Release app |
| CC-013B | partially_remediated | Sol → Luna / Max | CC-004 | Exact llama artifact traceability принята; rebuild/legal/GGUF/Core ML остаются owner-gated |
| CC-013B2 | proposed_for_owner_acceptance | Sol → Luna / Max | CC-004 | Минимальный RC без third-party Core ML; Vision/saliency + deterministic critique сохраняются |
| CC-013C | partially_remediated | Sol → Luna / Max | CC-004, CC-008 | Circle repository correlation принята; causality/права/Person/images/замены остаются owner-gated |

## Активная работа

- Visible Luna / Max threads выполняют реализацию, коррекции и основное тестирование; Sol ограничен архитектурными решениями, трекером и короткой risk-based приёмкой интегрированного evidence, без дублирования каждого worker run.
- Earlier canonical clean release gate прошёл на `store` / `6ff225d553ae654298dda70b9c779c1226c31800`; all stages passed: offline llama and Circle provenance, privacy self-tests, Debug build-for-testing, Release build и bundle validation; Release 72 032 KiB, 2 privacy manifests, only SnapKit.framework and llama.framework, 5 material contributors, 5 blockers, 2 provenance validators and 6/6 contamination fixtures.
- Host-retry canonical release gate прошёл на clean HEAD `5e5dfef859c7db220864076aead9c0de44181a8d`: `scripts/run_release_gates.sh --derived-data-root /private/tmp/shafin-release-gate.20260816-host-retry`, exit 0, `dirty=false`; passed Debug build-for-testing, Release build, 2 provenance validators, privacy validation, bundle validation and 6 contamination fixtures. Values: `manifest_count=2`, `TOTAL_APP_KIB=72104`, `KNOWN_BLOCKER_COUNT=5`. Logs: `/private/tmp/shafin-release-gate.20260816-host-retry/shafin-release-gates/{debug-build.log,release-build.log,release-validation.log,release-fixtures.log}`.
- The previous exit 66 was a sandbox/Xcode/CoreSimulator host restriction, not a repository failure; the host retry restored valid evidence. Five existing provenance/license blockers remain unresolved: `llama.framework`, two Core ML models and `Circle.usdz`/`Person.usdz`; release readiness must not be overstated.
- Pre-CC-011C raw full unit-target audit remains unresolved: 593 total, 496 passed, 94 failed, 3 skipped; XCResult `/private/tmp/shafin-main-complete-tests/Logs/Test/Test-shafinMultitool-2026.08.15_21-53-59-+0300.xcresult`. Классы отказов включали unit-hosted pseudo-UI без target app, default-запуск opt-in model/physical benchmark, Settings force unwraps, real-image Camera Coach evaluation с simulator Vision/Espresso и отсутствующими never-tracked assets, legacy parser/persistence/fixture failures.
- CC-011E accepted at `6ff225d553ae654298dda70b9c779c1226c31800`: E1 opt-in gates; E2 metadata persistence и dialogue parser/subtitle presentation; E3 neural/domain fixture corrections; E4 DeepCritic/Hybrid/Semantic truth. Интегрированный Luna gate: 104 executed, 102 passed, 2 intended skips, 0 failures; XCResult `/private/tmp/shafin-test-hygiene-final-luna/Logs/Test/Test-shafinMultitool-2026.08.15_22-52-30-+0300.xcresult`. Дополнительно: Scene 18/18 два последовательных раза и DB performance 4/4; DeepCritic 20/20; subtitle/config 22 с одним intended skip; Hybrid 7/7; Semantic 8/8.
- CC-011E contracts: nil map сохраняет metadata и не меняет legacy `_map`, без заявления о pair transaction; parser arrays параллельны, subtitle отображает `Иван: Привет.`; отсутствующая benchmark-конфигурация означает skip, некорректная — fail; certainty validation учитывает русские формы и calibrated language; non-whitelisted semantic actions подавляются; Hybrid production не изменён.
- CC-007/CC-010E bounded integration accepted at `ff9ce3e`: normal `SceneDelegate` non-benchmark launch opens the commercial shell with Camera selected while the benchmark branch remains first; the Camera route retains the existing `CameraViewModel`, awaits `stopAndWait` before shell removal/next construction, and shares repeated deactivation calls through one idempotent task. The Scene library root can release to Camera; a deeper Scene workspace or any modal blocks without constructing Camera because AR/persistence teardown is still non-awaitable. Generic workspace `build-for-testing` passed with derived data at `/private/tmp/shafin-cc010e-derived`; focused workspace tests passed 22/22 (11 `CommercialShellLaunchCompositionTests`, 11 `CommercialShellRoutingTests`). Full CC-010E/CC-010D, permission-state UX, full portrait/landscape product behavior and saved-project/deeper Scene smoke remain incomplete.
- CC-011C bounded true-process UI evidence accepted at `9f2f5f2`: the new `shafinMultitoolUITests` target is a shared-scheme member with neither `TEST_HOST` nor `BUNDLE_LOADER`, replacing the unit-hosted pseudo-UI test. DEBUG-only `SHAFIN_UI_TESTING=1` composes the real `CommercialShellComposition` and `ContentView` with the existing deterministic `CameraManager` failure `.noWideCamera`; the benchmark branch still comes first, no permission/hardware prompt is requested, and Release does not contain this path. Workspace `build-for-testing` succeeded. `/private/tmp/shafin-cc011c-ui-tests-20260816.xcresult` records 4/4 passed with 0 failures on iPhone 17 Pro / iOS 26.5: normal Camera shell, real Scene library root → Camera return, portrait root no crash and landscape root no crash. This does not claim full portrait behavior, camera permission UX, live capture continuity, completed analysis, deeper Scene workspace switching, full-suite health, physical-device behavior or release readiness.
- CC-010A4 accepted: task `01a006af-8d1a-7941-a294-84a330bb1e01`, worker `993510e`, accepted `b38f9fb`; Sol прошёл 15/15 lens transaction/presentation/lifecycle tests.
- CC-010G accepted: task `01a006b4-a0bf-7e52-b870-bb3c77505063`, worker `3212923`, accepted `6bfd3a4`; Sol прошёл 6/6 focused thermal policy/concurrency tests.
- CC-010A3 accepted: task `01a006a4-5560-7851-acfc-730223da26e8`, worker `85fc422`, accepted `15aa4e5`; Sol прошёл 16/16 transaction/manager/view-model tests.
- CC-010A1 accepted: task `01a00683-dd24-72b1-a914-302c7b59db9f`, worker `7169d85`, accepted `d7c4e98`, correction `f49953a` → `9a63f69`; Sol прошёл generic build и 22/22 пересекающихся lifecycle/release tests.
- CC-003A accepted: task `01a0064b-e81f-71f0-ac7e-661725dd3011`, worker `322faeb`, accepted `f246ada`; Sol прошёл generic integrated build и 10/10 `PermissionFoundationTests`.
- CC-010B1 accepted: task `01a0064f-3d5a-7452-a196-5ce39f1fae8b`, worker `b38ef12`, accepted `8b20380`, correction `772fe33` → `ee019f0`; Sol прошёл 12/12 focused tests.
- CC-010A2 accepted: task `01a0064f-d087-7b92-9424-8a90cebb989e`, worker `9fb974e`, accepted `caef74b`, correction `f80e1a3` → `b76f217`; Sol прошёл 4/4 `MotionGateTests`.
- CC-001: accepted, task `01a0055c-a4b4-70e2-bb46-53a03f9a57e0`, worker commits `c96b679`, `25bf140`, accepted commits `d8061aa`, `d4c4873`, evidence `docs/implementation/audits/release-bundle-inventory.md`.
- CC-002: accepted, task `01a00578-f7d5-75d3-ba32-3796ce136c1b`, worker commit `c2b8d4c`, accepted commit `2d7c26e`; parent Release и Debug build/bundle assertions прошли.
- CC-003: accepted, task `01a0055c-a4b2-7e82-93db-5d7098bc664d`, worker commit `a91a290`, accepted commit `e3b3712`, evidence `docs/implementation/audits/privacy-permissions-inventory.md`.
- CC-005: accepted, task `01a0055c-a4b4-70e2-bb46-5381f4f0acf1`, worker commit `05cad36`, accepted commit `e8f8615`, evidence `docs/implementation/audits/test-topology.md`.
- CC-006: accepted, task `01a0055c-a4b4-70e2-bb46-536ebdfd5585`, worker commit `caefe22`, accepted commit `67ede42`, evidence `docs/implementation/audits/runtime-entry-routing.md`.
- CC-009: accepted, task `01a00572-424a-7211-85df-c1719caf6108`, worker commit `addb184`, accepted commit `07a449a`, evidence `docs/implementation/audits/camera-session-ownership.md`.
- CC-004: accepted, task `01a00574-d6e4-7043-aafe-1cc3fd44eae6`, worker commit `c02cbea`, accepted commit `bfad2fa`, evidence `docs/implementation/audits/dependency-provenance-inventory.md`.
- CC-010A: accepted, task `01a00586-0a90-7323-b195-21d7941ffc70`, worker commit `b93e4aa`, accepted commit `e0bd423`; Sol повторил 7/7 simulator tests.
- CC-010B: accepted, task `01a0059d-6beb-71d3-a194-552d1e474f89`, worker commit `1926988`, accepted commit `79f7d1d`; Sol повторил generic simulator build-for-testing и 23/23 focused tests: 9 pipeline release, 7 scheduler, 7 camera lifecycle.
- CC-012A: accepted, task `01a0058b-d2da-7491-b3f4-de880445997b`, worker commit `2c75c53`, accepted commit `7a7c55b`, evidence `docs/implementation/audits/coaching-loop-event-contract-inventory.md`; Sol correction loop removed a duplicate metric and reconciled accepted CC-010A lifecycle evidence.
- CC-013A: accepted, task `01a005ae-36ec-7fe3-80ac-3fa10ed2703a`, worker commit `3a7731f`, accepted commit `c4275da`; Sol повторил Release build и bundle assertions на основной ветке: 71 848 КБ, SnapKit manifest присутствует, ARVideoKit/DeviceBenchmark/Models/GGUF отсутствуют.
- CC-011A: accepted, task `01a005c4-6a4d-7e63-a8d2-cd7199ea921f`, worker commit `a49c234`, accepted commit `c1e6646`; Sol повторил Release build, validator и negative self-test: ровно два manifests, 71 888 КБ, no unexpected paths.
- CC-011B: accepted, task `01a005d8-ac86-7d02-98ec-8b41b398bbe8`, worker commit `1223e01`, accepted commit `f56b7b7`; Sol повторил полный public gate на clean HEAD: Debug/Release прошли, Release = 71 900 КБ, 2 privacy manifests, 5 material contributors, 5 known provenance blockers и 6/6 contamination fixtures.
- CC-008: accepted evidence `docs/implementation/ux/camera-coach-state-spec.md`, commit `c1f6920`; owner явно потребовал запустить полный автономный implementation pipeline после серии подтверждённых product/UI решений.
- CC-007A: accepted slice — custom single-child container с системным `UITabBar`, ленивые routes, awaited teardown, blocked-transition rollback, rapid-tap coalescing и 11 focused routing tests. Пакет сам не меняет launch graph; normal parent launch integration принята отдельно в `ff9ce3e`, а true UI launch smoke, portrait/landscape checks and saved-project access остаются отдельной работой.
- CC-008A: accepted slice — typed presentation только для S04/S06/S07/S10c, один lower-third coaching surface, action-linked guides, production-safe copy, accessibility и Reduce Motion/Transparency. Пакет не обещает subject clarification, verification, recording, Deep Review или persistence; эти состояния остаются вне slice.
- CC-013B1: accepted, Luna / Max task `01a00603-9514-7ea0-81f3-21361862bc87`, worker twice-amended commit `ac97f6e`, accepted commit `d7fff1b`. После двух Sol fix-first loops зафиксированы только exact artifact traceability и existing build-output match; clean rebuild не заявлен. На основной ветке прошли 15 llama fixtures, offline/optional-upstream validators и совместные 25 provenance tests; legal/redistribution и archive proof остаются открыты.
- CC-011D: accepted, Luna / Max task `01a00631-d259-7c22-aa35-7e6ef95e8e1b`, worker commit `4802b9c`, accepted commit `7891fec`. Fresh Sol-review дал `ship`; orchestration test подтвердил pre-build order, fail-fast, offline args, отдельные логи и paths with spaces. Sol повторил полный gate на clean main: Debug/Release, 2 privacy manifests, 2 provenance validators, Release 71 968 KiB, 5 material contributors, 5 честных blockers и 6/6 contamination fixtures.
- CC-013C1: accepted, Luna / Max task `01a00603-9514-7ea0-81f3-2140ad032657`, worker amended commit `81f50c2`, accepted commit `c8601ba`. После Sol fix-first review claim сужен до repository correlation; 10/10 fixtures и реальный offline validator повторно прошли на основной ветке. Source-to-export causality, deterministic recipe и creator/rights/legal decision остаются открыты.
- CC-010C-A: accepted, Luna / Max task `01a00609-a689-7373-b2d4-d0eb245a6c66`, worker twice-amended commit `d1277ca`, accepted commit `9b41adf`. Sol-review снял ложный recoverable artifact, `hasAudio` overclaim, слабые concurrency assertions и потерю результата в `releaseAndWait`. На основной ветке прошли canonical generic iOS Simulator `build-for-testing` и 29/29 `SerializedMediaRecorderTests` на iPhone 17 Pro. `CameraService`, Scene/Camera call sites, Photos, permission UI и runtime behavior не входят в принятый пакет.
- CC-013B2: `docs/implementation/provenance/coreml-model-replacement-research.md` подтвердил exact-byte происхождение DETR из исследованного Apple package, но не валидировал текущий semantic-coverage-as-confidence product contract. Sol по-прежнему рекомендует минимальный RC без DETR/NIMA/compact neural fusion: сохранить Apple Vision/saliency и deterministic critique, явно отключить production consumers и сделать Release gate zero-Core-ML. Implementation ждёт owner acceptance, потому что продукт осознанно теряет object-aware DETR labels и model aesthetic score.

## Ворота следующего шага

Перед исходными Release/UI изменениями должны быть приняты CC-001, CC-003, CC-005 и CC-006. Перед изменениями camera lifecycle — CC-009 и отдельная high-complexity классификация. CC-008, CC-011E, CC-007A, CC-008A и bounded CC-007/CC-010E integration приняты в заявленных границах; следующий шаг остаётся в соответствии с `BACKLOG.md`. Full test topology и real-image evaluation остаются отдельными незакрытыми lanes.

## Внешние блокеры

CC-008 больше не блокирует коммерческий UI. CC-013B2 остаётся отдельным owner-gated решением о составе минимального RC. Для окончательного release candidate также потребуются asset/model rights decisions, физические устройства, Apple Developer credentials, privacy processor/region и платная инфраструктура; они не нужны для текущих технических пакетов.

## Resume hint

При возобновлении прочитать этот файл, `docs/app-store-product-plan.md`, `docs/implementation/BACKLOG.md`, затем сравнить Git HEAD/status с последним принятым task evidence. Перед любой новой реализацией, review, correction loop или verification создать отдельный user-visible Codex thread в project-local environment (`environment.type=local`) с `model=gpt-5.6-luna` и `thinking=max`; если такой thread нельзя создать, остановиться fail-closed и не использовать hidden/native route. Не продолжать из памяти.
