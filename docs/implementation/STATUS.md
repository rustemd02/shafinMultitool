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
| CC-003 | in_progress | Luna / Max | bootstrap commit | Privacy/permission inventory и executable gap list |
| CC-004 | ready | Luna / Max | bootstrap commit | Dependency/model/media provenance inventory |
| CC-005 | in_progress | Luna / Max | bootstrap commit | Test topology и UI-test target implementation plan |
| CC-006 | accepted | Luna / Max | bootstrap commit | Проверен launch graph; принят `SceneDelegate` commercial-shell seam, persistence/benchmark boundaries зафиксированы |
| CC-007 | draft | Sol → Luna | CC-006, UX spec | Commercial app shell и Camera Coach default route |
| CC-008 | in_progress | Sol | product baseline | UI/UX state specification без vibe-code patterns |
| CC-009 | ready | Luna / Max | bootstrap commit | Camera/session owner and lifecycle audit |
| CC-010 | draft | Terra / High | CC-009 | Camera foundation migration plan при подтверждённой сложности |
| CC-011 | draft | Luna / Max | CC-001, CC-005 | Reproducible local/CI release gates |
| CC-012 | draft | Sol → Luna | CC-008 | Privacy-safe activation and coaching-loop event contract |

## Активная работа

- Sol: принял CC-006 после проверки diff, исходных ссылок и повторной generic iOS test build; освободившийся слот передаётся CC-009.
- CC-001: task `01a0055c-a4b4-70e2-bb46-53a03f9a57e0`, worktree `/Users/unterlantas/.codex/worktrees/f179/shafinMultitool`.
- CC-003: task `01a0055c-a4b2-7e82-93db-5d7098bc664d`, worktree `/Users/unterlantas/.codex/worktrees/5496/shafinMultitool`.
- CC-005: task `01a0055c-a4b4-70e2-bb46-5381f4f0acf1`, worktree `/Users/unterlantas/.codex/worktrees/f619/shafinMultitool`.
- CC-006: accepted, task `01a0055c-a4b4-70e2-bb46-536ebdfd5585`, worker commit `caefe22`, accepted commit `67ede42`, evidence `docs/implementation/audits/runtime-entry-routing.md`.

## Ворота следующего шага

Перед исходными Release/UI изменениями должны быть приняты CC-001, CC-003, CC-005 и CC-006. Перед изменениями camera lifecycle — CC-009 и отдельная high-complexity классификация. Перед коммерческим UI — однозначная UX state specification CC-008.

## Внешние блокеры

Сейчас внешних блокеров для M0 нет. Физические устройства, Apple Developer credentials, privacy processor/region и платная инфраструктура потребуются на последующих milestones.

## Resume hint

При возобновлении прочитать этот файл, `docs/app-store-product-plan.md`, `docs/implementation/BACKLOG.md`, затем сравнить Git HEAD/status с последним принятым task evidence. Не продолжать из памяти.
