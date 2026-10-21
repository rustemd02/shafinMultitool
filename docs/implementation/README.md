# SET OS implementation documents

Текущий единый план исполнения до App Store находится в
`docs/implementation/APP_STORE_RELEASE_TRACKER.md`. Остальные документы этого
каталога задают acceptance-контракт, evidence или сохраняют историю.

## Источники правды

Приоритет при конфликте:

1. Реальный код, свежие исполнимые проверки и hash-bound receipts.
2. `docs/implementation/PRODUCTION_ACCEPTANCE.md` — контракт приёмки.
3. `docs/implementation/APP_STORE_RELEASE_TRACKER.md` — единственный текущий status, backlog, dependencies и owner blockers.
4. `docs/app-store-product-plan.md` — продуктовый контекст.
5. `docs/implementation/release/AppStoreSubmissionGates.json` — формальный снимок гейтов конкретного артефакта.
6. Старые execution/handover/master-файлы удалены как дублирующие источники; оставшиеся `docs/aegis/**`, `docs/cameraanalysis/**`, `docs/workflow/**` и thesis-материалы — evidence/контракты, не параллельный текущий backlog.

Внешний Deep Research не передаётся исполнителям как неявный контекст. Принятые выводы должны сначала попасть в продуктовый документ или конкретный task packet.

## Camera Coach: следующий сбор данных

- [Требования к входным данным для поиска, разметки и обучения](camera-coach-input-data-requirements-v1.md) — спецификация визуального киноассистента: capabilities, пространственная разметка, clips/scene packs/technical series, admission и границы текущего training/export пути.
- [Самодостаточный промпт для GPT 6 Pro](camera-coach-dataset-acquisition-swarm-prompt.md) — замысел киноассистента, исследование подсказок и визуальных предложений, получение корпуса, частный Google Drive upload и self-review. Текущий каталог не ограничивает новые возможности; дата съёмки stills необязательна. Сбор и обучение здесь не выполнялись.
- [Аудит полученного CameraCoach_Dataset_v2](acquisition/camera-coach-v2-audit-2026-10-11.md) — 3/10 для целевого live corpus; проверенные counts/bytes, визуальная выборка и границы native grounding.
- [Продолжение для GPT 6 Pro: полный кино/видеокорпус v3](acquisition/camera-coach-v3-continuation-prompt.md) — предыдущее acquisition-задание: films/TV, continuous video, camera/actor motion, temporal supervision, автоматическая подготовка, доставка и self-review.
- [Исправление v3 для GPT 6 Pro: полный repair prompt](acquisition/camera-coach-v4-repair-prompt.md) — актуальное задание по присланному критическому аудиту: все35 проблем и22 направления, честная приёмка≥8/10, смежные источники, очистка и проверяемая Drive-доставка. Запрет добровольного завершения до всего DoD; внешние блокеры сохраняют незавершённый статус. Сам v3/Drive в этой задаче не перепроверялись.

Эти документы не заменяют release-label schema, acceptance-контракт или текущий трекер исполнения.

## Состояния задач

Использовать словарь и протокол одной bounded-задачи из раздела 2
`APP_STORE_RELEASE_TRACKER.md`. Текущий статус меняется только там после
проверки evidence.

## Правила волн

- Один исполнитель получает одну строку из канонического трекера.
- Независимые задачи параллельны только при непересекающемся ownership.
- Общие файлы и зависимые стеки выполняются последовательно.
- Исполнитель не делает commit, push, PR, merge, rebase или reset без отдельного разрешения.
- Приёмка требует указанного в строке check и конкретного evidence.

## Definition of Done продукта

Pipeline останавливается как `done` только когда доступные автоматические, UX, privacy, quality и release gates пройдены и собран проверенный release candidate. Физические camera-сценарии, Apple credentials, платная инфраструктура, юридические решения и App Store submission остаются внешними воротами и не подменяются утверждениями агента.
