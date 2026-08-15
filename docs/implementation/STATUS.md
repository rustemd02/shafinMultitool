# Camera Coach execution status

Последнее обновление: 15 августа 2026 года.

## Глобальная цель

Автономно довести всю систему до production-level, submission-ready App Store candidate по `docs/implementation/PRODUCTION_ACCEPTANCE.md`. Camera Coach остаётся первичным продуктом, Scene Mode — вторичным; Sol владеет архитектурой, декомпозицией, проверкой и приёмкой, Luna / Max выполняет полностью специфицированные задачи. Task/milestone/build completion не закрывают глобальную цель. Push, PR, платные действия, TestFlight/App Store submission и юридические решения не разрешены автоматически.

## Текущий milestone

`M0 — product and release baseline`

Цель milestone: получить воспроизводимую базовую сборку, убрать противоречия в product source of truth, определить фактический Release bundle и превратить P0/P1 риски в задачи с точным ownership.

## Baseline snapshot

- Git: ветка `store`, base `018ceab` до bootstrap-коммита.
- Tracked source до bootstrap не изменён.
- `xcodebuild ... build-for-testing` для `generic/platform=iOS` прошёл 15 августа 2026 года.
- В проекте есть app target и unit-test target; отдельного UI-test target нет.
- Test build bundle: около 1,2 ГБ.
- Главный bundled P0: `dataset_v9_event_sft_q4_k_m.gguf`, около 1,0 ГБ.
- `Resources/DeviceBenchmark`: около 51 МБ и 182 файла; benchmark-изображения и JSONL попадают в app bundle.
- Core ML models: около 47 МБ в исходном дереве.
- `PrivacyInfo.xcprivacy` не найден.
- Usage descriptions существуют, но их UX, язык, фактическая необходимость и denied/restricted flow не проверены.
- Единственный runtime entry открывает `SOModuleBuilder` через `SceneDelegate`; Camera Coach не является default product route.
- Deep Research принят с рекомендацией `NARROW`; публичная монетизация отложена до instrumented beta.

## Очередь первой волны

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
| CC-007 | decomposed | Sol → Luna | CC-006, CC-008 | Commercial app shell и Camera Coach default route |
| CC-007A | ready_after_CC-008 | Luna / Max | CC-006, CC-008 | Single-child shell routing contract без смены launch graph |
| CC-008 | proposed_for_owner_acceptance | Sol | product baseline | 610-строчная UX state machine подготовлена; implementation gate ждёт осмысленного owner acceptance |
| CC-008A | ready_after_CC-008 | Luna / Max | CC-008, CC-010B | Production-safe live surface только для уже доказуемых S04/S06/S07/S10c |
| CC-009 | accepted | Luna / Max | CC-003, CC-006 | Подтверждены три media contour и отсутствие awaited exclusive route/session owner |
| CC-010A | accepted | Luna / Max | CC-009 | Awaitable lifecycle, typed failures и late-callback fence; 7/7 focused tests прошли |
| CC-010A1 | accepted | Luna / Max | CC-010A, CC-010B1 | Failed-start rollback принят после correction loop; generic build и 22/22 пересекающихся focused tests прошли |
| CC-010A2 | accepted | Luna / Max | CC-010A | Atomic motion snapshot принят после correction loop; 4/4 focused tests прошли |
| CC-010A3 | accepted | Luna / Max | CC-010A | Transactional lens input принят; worker `85fc422` → `15aa4e5`, 16/16 intersecting tests прошли |
| CC-010A4 | in_progress | Luna / Max | CC-010A3 | Confirmed lens presentation task `01a006af-8d1a-7941-a294-84a330bb1e01`; no optimistic/stale UI state |
| CC-010B | accepted | Luna / Max | CC-010A | Детерминированный unregister/drain, release/re-register и stale-result fences; 23/23 focused tests прошли |
| CC-010B1 | accepted | Luna / Max | CC-010B | Coherent latest-frame envelope и session-local reset приняты; 12/12 focused tests прошли |
| CC-010C | partially_accepted | Sol → Luna / Max | CC-009, recording policy | Policy-neutral serialized recorder core принято; production wiring/save policy остаются gated |
| CC-010C-A | accepted | Luna / Max | CC-009 | Изолированное recorder core принято после Sol-review, canonical build и 29/29 simulator tests |
| CC-010D | draft | Luna / Max | CC-010C | Scene exit/background teardown с сохранением project state |
| CC-010E | blocked_by_CC-007 | Terra / High | CC-007, CC-010A, CC-010D | Exclusive route lease integration в commercial shell |
| CC-010F | blocked_by_CC-008 | Luna / Max | CC-008, CC-010A | In-place orientation continuity и media metadata |
| CC-011 | decomposed | Luna / Max | CC-001, CC-005 | Privacy manifest, deterministic bundle gate и real UI-test target разложены |
| CC-011A | accepted | Luna / Max | CC-013A | App-owned manifest и validator приняты; Release содержит ровно app + SnapKit manifests |
| CC-011B | accepted | Luna / Max | CC-002, CC-011A | Единый clean-HEAD gate принят: Debug, Release, privacy, allowlists, sizes и 6 contamination fixtures |
| CC-011D | accepted | Luna / Max | CC-013B1, CC-013C1 | Два offline provenance validator приняты как fail-fast stages canonical release gate |
| CC-012 | decomposed | Sol → Luna | CC-008 | Privacy-safe activation and coaching-loop event contract |
| CC-012A | accepted | Luna / Max | CC-003, CC-008 | 12 instrumentation owners, 59 active events, 63 properties; activation требует action + independent verification |
| CC-013A | accepted | Luna / Max | CC-004 | ARVideoKit удалён; SnapKit 5.7.1 privacy bundle доказан в Release app |
| CC-013B | partially_remediated | Sol → Luna / Max | CC-004 | Exact llama artifact traceability принята; rebuild/legal/GGUF/Core ML остаются owner-gated |
| CC-013B2 | proposed_for_owner_acceptance | Sol → Luna / Max | CC-004 | Минимальный RC без third-party Core ML; Vision/saliency + deterministic critique сохраняются |
| CC-013C | partially_remediated | Sol → Luna / Max | CC-004, CC-008 | Circle repository correlation принята; causality/права/Person/images/замены остаются owner-gated |

## Активная работа

- Sol: ведёт rolling-wave оркестрацию и принимает каждый Luna / Max пакет только после независимых diff/source/build/test checks на основной ветке.
- CC-010A4 task `01a006af-8d1a-7941-a294-84a330bb1e01`: Luna / Max переводит `CameraViewModel.currentLens` на подтверждённый CC-010A3 result с rapid-tap/lifecycle fence; Overlay/копирайт не меняются.
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
- CC-008: proposed evidence `docs/implementation/ux/camera-coach-state-spec.md`, commit `c1f6920`; до owner acceptance UI source tasks не запускаются.
- CC-007A: точный post-acceptance packet подготовлен: custom single-child container с системным `UITabBar`, ленивые routes, awaited teardown, blocked-transition rollback, rapid-tap coalescing и 10 focused routing tests. Пакет не меняет launch graph и не запускается до CC-008.
- CC-008A: точный post-acceptance packet подготовлен: typed presentation только для S04/S06/S07/S10c, один lower-third coaching surface, action-linked guides, production-safe copy, accessibility и Reduce Motion/Transparency. Пакет не обещает subject clarification, verification, recording, Deep Review или persistence и не запускается до CC-008.
- CC-013B1: accepted, Luna / Max task `01a00603-9514-7ea0-81f3-21361862bc87`, worker twice-amended commit `ac97f6e`, accepted commit `d7fff1b`. После двух Sol fix-first loops зафиксированы только exact artifact traceability и existing build-output match; clean rebuild не заявлен. На основной ветке прошли 15 llama fixtures, offline/optional-upstream validators и совместные 25 provenance tests; legal/redistribution и archive proof остаются открыты.
- CC-011D: accepted, Luna / Max task `01a00631-d259-7c22-aa35-7e6ef95e8e1b`, worker commit `4802b9c`, accepted commit `7891fec`. Fresh Sol-review дал `ship`; orchestration test подтвердил pre-build order, fail-fast, offline args, отдельные логи и paths with spaces. Sol повторил полный gate на clean main: Debug/Release, 2 privacy manifests, 2 provenance validators, Release 71 968 KiB, 5 material contributors, 5 честных blockers и 6/6 contamination fixtures.
- CC-013C1: accepted, Luna / Max task `01a00603-9514-7ea0-81f3-2140ad032657`, worker amended commit `81f50c2`, accepted commit `c8601ba`. После Sol fix-first review claim сужен до repository correlation; 10/10 fixtures и реальный offline validator повторно прошли на основной ветке. Source-to-export causality, deterministic recipe и creator/rights/legal decision остаются открыты.
- CC-010C-A: accepted, Luna / Max task `01a00609-a689-7373-b2d4-d0eb245a6c66`, worker twice-amended commit `d1277ca`, accepted commit `9b41adf`. Sol-review снял ложный recoverable artifact, `hasAudio` overclaim, слабые concurrency assertions и потерю результата в `releaseAndWait`. На основной ветке прошли canonical generic iOS Simulator `build-for-testing` и 29/29 `SerializedMediaRecorderTests` на iPhone 17 Pro. `CameraService`, Scene/Camera call sites, Photos, permission UI и runtime behavior не входят в принятый пакет.
- CC-013B2: source audit исправил прежнее предположение: DETR и NIMA компилируются в Release app-root `.mlmodelc`; исключённый `Resources/Models` к ним не относится. Sol рекомендует RC без DETR/NIMA/compact neural fusion: сохранить Apple Vision/saliency и deterministic critique, явно отключить production consumers и сделать Release gate zero-Core-ML. Implementation ждёт owner acceptance, потому что продукт осознанно теряет object-aware DETR labels и model aesthetic score.

## Ворота следующего шага

Перед исходными Release/UI изменениями должны быть приняты CC-001, CC-003, CC-005 и CC-006. Перед изменениями camera lifecycle — CC-009 и отдельная high-complexity классификация. Перед коммерческим UI — однозначная UX state specification CC-008.

## Внешние блокеры

Единственный текущий product gate для коммерческого UI — owner acceptance CC-008 фразой `принимаю CC-008`. Для окончательного release candidate также потребуются asset/model rights decisions, физические устройства, Apple Developer credentials, privacy processor/region и платная инфраструктура; они не нужны для текущих технических пакетов.

## Resume hint

При возобновлении прочитать этот файл, `docs/app-store-product-plan.md`, `docs/implementation/BACKLOG.md`, затем сравнить Git HEAD/status с последним принятым task evidence. Не продолжать из памяти.
