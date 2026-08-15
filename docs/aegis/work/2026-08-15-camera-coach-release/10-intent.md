# Camera Coach release intent

## Requested outcome

Запустить автономный pipeline main-chat Sol-оркестратор → GPT-5.6 Luna / Max исполнители и довести всю систему до production-level, submission-ready App Store candidate по `docs/implementation/PRODUCTION_ACCEPTANCE.md`.

## Durable orchestration policy amendment

The active system goal text is immutable through the goal API while it is active. This file and `20-checkpoint.md` are the durable goal-policy amendment for the orchestration boundary.

- Every spawned subagent for this project MUST use GPT-5.6 Luna / Max. Sol, Terra and inherited-model subagents are forbidden; if Luna / Max is unavailable, fail closed and do not substitute another model.
- The main chat is the sole Sol orchestrator.
- Luna / Max owns all implementation, testing, correction loops, task-level independent review and verification.
- The parent/main-chat Sol may own architecture, low-level task contracts, the tracker and one bounded risk-based milestone acceptance only. It MUST NOT spawn any Sol reviewer, advisor or implementer subagent.
- Existing mentions of past Sol reviews or verification in checkpoint, status and backlog evidence are historical evidence only; they are not current routing permission and must not be rewritten as if they were current policy.

## Goal and stop condition

- `done`: все обязательные gates из `docs/implementation/PRODUCTION_ACCEPTANCE.md` подтверждены fresh evidence; task/milestone/build completion недостаточны.
- `blocked`: вся доступная безопасная независимая работа исчерпана, а продолжение требует отсутствующей внешней зависимости, полномочия, устройства, пользователя или решения владельца.
- `needs-verification`: реализация существует, но benchmark/device/beta/privacy/legal/commercial/release evidence недостаточно; это не завершение цели.
- `scope-exceeded`: продолжение требует push/PR, расходов, публикации, юридического решения, необратимой миграции или изменения утверждённого product scope.
- `orchestration-stop`: если GPT-5.6 Luna / Max недоступен, работа останавливается в fail-closed состоянии; Sol не создаёт и не подменяет его Sol-, Terra- или inherited-model subagent.

## Scope and non-goals

Scope: production-level whole system; Camera Coach first, Scene Mode secondary, free complete local loop, evidence-gated Deep Review and monetization, full benchmark/device/privacy/release proof. Не-цели: универсальный AI director, курсы, social, mandatory account, StoreKit до beta evidence, скрытая публикация или расходы.

## Baseline read set

- `docs/app-store-product-plan.md`
- `docs/implementation/STATUS.md`
- `docs/implementation/BACKLOG.md`
- `docs/implementation/orchestration-setup.md`
- `docs/implementation/PRODUCTION_ACCEPTANCE.md`
- релевантные technical source-of-truth документы только по конкретному slice

## Impact and risk

Работа затрагивает release bundle, app entry, Camera/AR lifecycle, UX, privacy, server boundary и позднее StoreKit. Persistent Scene Mode data защищены. Worker reports не считаются приёмкой.
