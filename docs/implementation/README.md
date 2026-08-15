# Camera Coach implementation tracker

Этот каталог — исполнимый слой поверх `docs/app-store-product-plan.md`. Продуктовый документ определяет цели, аудиторию, scope и gates; здесь Sol-оркестратор хранит текущее состояние, ближайшую волну и полные task packets для исполнителей.

## Источники правды

Приоритет при конфликте:

1. `docs/app-store-product-plan.md` — продукт, UX, монетизация и release gates.
2. `docs/implementation/STATUS.md` — единственный текущий статус исполнения.
3. `docs/implementation/BACKLOG.md` — ближайшая детализированная волна.
4. `docs/implementation/TASK_TEMPLATE.md` — обязательный контракт Luna-задачи.
5. `docs/implementation/orchestration-setup.md` — routing и полномочия Sol Advisor.
6. Старые `docs/cameraanalysis/**`, `docs/workflow/**` и thesis-материалы — evidence существующей реализации, но не источник коммерческого scope.

Внешний Deep Research не передаётся исполнителям как неявный контекст. Принятые выводы должны сначала попасть в продуктовый документ или конкретный task packet.

## Состояния задач

`draft → ready → in_progress → implemented → verified → accepted`

Дополнительные состояния: `blocked`, `deferred`, `rejected`.

- Только Sol меняет `STATUS.md` и принимает работу.
- `implemented` означает, что worker закончил изменения; это не приёмка.
- `verified` ставится после проверки diff и повторного запуска команд основной Sol-сессией.
- `accepted` ставится после проверки scope, acceptance criteria и отсутствия незакрытых замечаний.

## Правила волн

- Детализируется только ближайшая волна из 10–30 задач.
- Независимые задачи могут идти параллельно лишь при непересекающемся ownership.
- Общие файлы и зависимые стеки выполняются последовательно.
- Исправления возвращаются в ту же Luna-задачу.
- Luna работает в отдельном Codex worktree на `gpt-5.6-luna` / `max`.
- Worker не делает push, PR, merge или rebase без явного разрешения Sol.
- Sol проверяет реальный worktree, полный diff, base, branch и тесты.

## Definition of Done продукта

Pipeline останавливается как `done` только когда доступные автоматические, UX, privacy, quality и release gates пройдены и собран проверенный release candidate. Физические camera-сценарии, Apple credentials, платная инфраструктура, юридические решения и App Store submission остаются внешними воротами и не подменяются утверждениями агента.
