# Camera Coach execution status

Последнее обновление: 15 августа 2026 года.

## Глобальная цель

Автономно довести приложение до проверенного Camera Coach release candidate. Sol владеет архитектурой, декомпозицией, проверкой и приёмкой; Luna / Max выполняет полностью специфицированные задачи. Push, PR, платные действия, TestFlight/App Store submission и юридические решения не разрешены автоматически.

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
| CC-002 | in_progress | Luna / Max | CC-001 | Детерминированная Release resource boundary и Debug-only benchmark provisioning |
| CC-003 | accepted | Luna / Max | bootstrap commit | Все permission/data paths инвентаризированы; подтверждены отсутствующие denied/restricted/Settings flows и privacy manifest |
| CC-004 | accepted | Luna / Max | accepted audit baseline | 16 provenance dispositions accepted; 8 missing, 2 exclude, 4 development-only, 2 verified |
| CC-005 | accepted | Luna / Max | bootstrap commit | 29 test files классифицированы; подтверждён unit-hosted pseudo-UI test и механический план настоящего UI-test target |
| CC-006 | accepted | Luna / Max | bootstrap commit | Проверен launch graph; принят `SceneDelegate` commercial-shell seam, persistence/benchmark boundaries зафиксированы |
| CC-007 | draft | Sol → Luna | CC-006, UX spec | Commercial app shell и Camera Coach default route |
| CC-008 | proposed_for_owner_acceptance | Sol | product baseline | 610-строчная UX state machine подготовлена; implementation gate ждёт осмысленного owner acceptance |
| CC-009 | accepted | Luna / Max | CC-003, CC-006 | Подтверждены три media contour и отсутствие awaited exclusive route/session owner |
| CC-010A | in_progress | Luna / Max | CC-009 | Awaitable idempotent Coach capture lifecycle и late-callback fence |
| CC-010B | draft | Luna / Max | CC-010A | Scheduler registration ownership и pipeline release |
| CC-010C | draft | Terra / High | CC-009, recording policy | Serialized recorder ownership и typed save result |
| CC-010D | draft | Luna / Max | CC-010C | Scene exit/background teardown с сохранением project state |
| CC-010E | blocked_by_CC-007 | Terra / High | CC-007, CC-010A, CC-010D | Exclusive route lease integration в commercial shell |
| CC-010F | blocked_by_CC-008 | Luna / Max | CC-008, CC-010A | In-place orientation continuity и media metadata |
| CC-011 | draft | Luna / Max | CC-001, CC-005 | Reproducible local/CI release gates |
| CC-012 | draft | Sol → Luna | CC-008 | Privacy-safe activation and coaching-loop event contract |

## Активная работа

- Sol: принял CC-003, CC-005 и CC-006 после diff/source/build checks; CC-001 возвращён тому же worker на сверку clean worktree с локальным ignored GGUF.
- CC-001: accepted, task `01a0055c-a4b4-70e2-bb46-53a03f9a57e0`, worker commits `c96b679`, `25bf140`, accepted commits `d8061aa`, `d4c4873`, evidence `docs/implementation/audits/release-bundle-inventory.md`.
- CC-002: task `01a00578-f7d5-75d3-ba32-3796ce136c1b`, worktree `/Users/unterlantas/.codex/worktrees/9bd3/shafinMultitool`.
- CC-003: accepted, task `01a0055c-a4b2-7e82-93db-5d7098bc664d`, worker commit `a91a290`, accepted commit `e3b3712`, evidence `docs/implementation/audits/privacy-permissions-inventory.md`.
- CC-005: accepted, task `01a0055c-a4b4-70e2-bb46-5381f4f0acf1`, worker commit `05cad36`, accepted commit `e8f8615`, evidence `docs/implementation/audits/test-topology.md`.
- CC-006: accepted, task `01a0055c-a4b4-70e2-bb46-536ebdfd5585`, worker commit `caefe22`, accepted commit `67ede42`, evidence `docs/implementation/audits/runtime-entry-routing.md`.
- CC-009: accepted, task `01a00572-424a-7211-85df-c1719caf6108`, worker commit `addb184`, accepted commit `07a449a`, evidence `docs/implementation/audits/camera-session-ownership.md`.
- CC-004: accepted, task `01a00574-d6e4-7043-aafe-1cc3fd44eae6`, worker commit `c02cbea`, accepted commit `bfad2fa`, evidence `docs/implementation/audits/dependency-provenance-inventory.md`.
- CC-010A: task `01a00586-0a90-7323-b195-21d7941ffc70`, worktree `/Users/unterlantas/.codex/worktrees/d635/shafinMultitool`.
- CC-008: proposed evidence `docs/implementation/ux/camera-coach-state-spec.md`, commit `c1f6920`; до owner acceptance UI source tasks не запускаются.

## Ворота следующего шага

Перед исходными Release/UI изменениями должны быть приняты CC-001, CC-003, CC-005 и CC-006. Перед изменениями camera lifecycle — CC-009 и отдельная high-complexity классификация. Перед коммерческим UI — однозначная UX state specification CC-008.

## Внешние блокеры

Сейчас внешних блокеров для M0 нет. Физические устройства, Apple Developer credentials, privacy processor/region и платная инфраструктура потребуются на последующих milestones.

## Resume hint

При возобновлении прочитать этот файл, `docs/app-store-product-plan.md`, `docs/implementation/BACKLOG.md`, затем сравнить Git HEAD/status с последним принятым task evidence. Не продолжать из памяти.
