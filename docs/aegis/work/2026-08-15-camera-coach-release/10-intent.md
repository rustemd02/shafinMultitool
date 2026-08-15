# Camera Coach release intent

## Requested outcome

Запустить автономный pipeline Sol-оркестратор → Luna / Max исполнители и довести всю систему до production-level, submission-ready App Store candidate по `docs/implementation/PRODUCTION_ACCEPTANCE.md`.

## Goal and stop condition

- `done`: все обязательные gates из `docs/implementation/PRODUCTION_ACCEPTANCE.md` подтверждены fresh evidence; task/milestone/build completion недостаточны.
- `blocked`: вся доступная безопасная независимая работа исчерпана, а продолжение требует отсутствующей внешней зависимости, полномочия, устройства, пользователя или решения владельца.
- `needs-verification`: реализация существует, но benchmark/device/beta/privacy/legal/commercial/release evidence недостаточно; это не завершение цели.
- `scope-exceeded`: продолжение требует push/PR, расходов, публикации, юридического решения, необратимой миграции или изменения утверждённого product scope.

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
