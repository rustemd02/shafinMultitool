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
| CC-001 | in_progress | Luna / Max | bootstrap commit | Release bundle inventory и allowlist proposal |
| CC-002 | draft | Luna / Max | CC-001 | Benchmark/test assets исключены из Release без поломки DEBUG harness |
| CC-003 | accepted | Luna / Max | bootstrap commit | Все permission/data paths инвентаризированы; подтверждены отсутствующие denied/restricted/Settings flows и privacy manifest |
| CC-004 | in_progress | Luna / Max | accepted audit baseline | Dependency/model/media provenance inventory |
| CC-005 | accepted | Luna / Max | bootstrap commit | 29 test files классифицированы; подтверждён unit-hosted pseudo-UI test и механический план настоящего UI-test target |
| CC-006 | accepted | Luna / Max | bootstrap commit | Проверен launch graph; принят `SceneDelegate` commercial-shell seam, persistence/benchmark boundaries зафиксированы |
| CC-007 | draft | Sol → Luna | CC-006, UX spec | Commercial app shell и Camera Coach default route |
| CC-008 | proposed_for_owner_acceptance | Sol | product baseline | 610-строчная UX state machine подготовлена; implementation gate ждёт осмысленного owner acceptance |
| CC-009 | in_progress | Luna / Max | CC-003, CC-006 | Camera/session owner and lifecycle audit запущен из принятой store baseline |
| CC-010 | draft | Terra / High | CC-009 | Camera foundation migration plan при подтверждённой сложности |
| CC-011 | draft | Luna / Max | CC-001, CC-005 | Reproducible local/CI release gates |
| CC-012 | draft | Sol → Luna | CC-008 | Privacy-safe activation and coaching-loop event contract |

## Активная работа

- Sol: принял CC-003, CC-005 и CC-006 после diff/source/build checks; CC-001 возвращён тому же worker на сверку clean worktree с локальным ignored GGUF.
- CC-001: correction in progress, task `01a0055c-a4b4-70e2-bb46-53a03f9a57e0`, worktree `/Users/unterlantas/.codex/worktrees/f179/shafinMultitool`; parent Release partial app = 1 198 316 КБ, GGUF = 1 094 912 КБ, Release compile blocker воспроизведён.
- CC-003: accepted, task `01a0055c-a4b2-7e82-93db-5d7098bc664d`, worker commit `a91a290`, accepted commit `e3b3712`, evidence `docs/implementation/audits/privacy-permissions-inventory.md`.
- CC-005: accepted, task `01a0055c-a4b4-70e2-bb46-5381f4f0acf1`, worker commit `05cad36`, accepted commit `e8f8615`, evidence `docs/implementation/audits/test-topology.md`.
- CC-006: accepted, task `01a0055c-a4b4-70e2-bb46-536ebdfd5585`, worker commit `caefe22`, accepted commit `67ede42`, evidence `docs/implementation/audits/runtime-entry-routing.md`.
- CC-009: task `01a00572-424a-7211-85df-c1719caf6108`, worktree `/Users/unterlantas/.codex/worktrees/39f4/shafinMultitool`.
- CC-004: task `01a00574-d6e4-7043-aafe-1cc3fd44eae6`, worktree `/Users/unterlantas/.codex/worktrees/121a/shafinMultitool`.
- CC-008: proposed evidence `docs/implementation/ux/camera-coach-state-spec.md`, commit `c1f6920`; до owner acceptance UI source tasks не запускаются.

## Ворота следующего шага

Перед исходными Release/UI изменениями должны быть приняты CC-001, CC-003, CC-005 и CC-006. Перед изменениями camera lifecycle — CC-009 и отдельная high-complexity классификация. Перед коммерческим UI — однозначная UX state specification CC-008.

## Внешние блокеры

Сейчас внешних блокеров для M0 нет. Физические устройства, Apple Developer credentials, privacy processor/region и платная инфраструктура потребуются на последующих milestones.

## Resume hint

При возобновлении прочитать этот файл, `docs/app-store-product-plan.md`, `docs/implementation/BACKLOG.md`, затем сравнить Git HEAD/status с последним принятым task evidence. Не продолжать из памяти.
