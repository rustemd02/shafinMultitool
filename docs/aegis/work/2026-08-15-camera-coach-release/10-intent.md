# Camera Coach release intent

## Requested outcome

Запустить автономный pipeline Sol-оркестратор → Luna / Max исполнители и довести приложение до проверенного release candidate.

## Goal and stop condition

- `done`: доступные локальные implementation, UX, quality, privacy и release gates пройдены; внешние App Store/device/legal gates явно перечислены.
- `blocked`: отсутствует обязательная внешняя зависимость, полномочие или решение владельца.
- `needs-verification`: реализация существует, но evidence недостаточно.
- `scope-exceeded`: продолжение требует push/PR, расходов, публикации, юридического решения или изменения утверждённого product scope.

## Scope and non-goals

Scope: Camera Coach first, Scene Mode secondary, free complete local loop, evidence-gated Deep Review and monetization. Не-цели: универсальный AI director, курсы, social, mandatory account, StoreKit до beta evidence, скрытая публикация или расходы.

## Baseline read set

- `docs/app-store-product-plan.md`
- `docs/implementation/STATUS.md`
- `docs/implementation/BACKLOG.md`
- `docs/implementation/orchestration-setup.md`
- релевантные technical source-of-truth документы только по конкретному slice

## Impact and risk

Работа затрагивает release bundle, app entry, Camera/AR lifecycle, UX, privacy, server boundary и позднее StoreKit. Persistent Scene Mode data защищены. Worker reports не считаются приёмкой.
