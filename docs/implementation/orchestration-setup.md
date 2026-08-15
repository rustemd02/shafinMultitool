# Автономная реализация: Sol Advisor и Luna task lane

Статус: `pending_role_discovery_reload`.

Дата: 15 августа 2026 года.

## 1. Цель

Основная Sol-сессия автономно доводит Camera Coach до проверенного release candidate: поддерживает исполнимый backlog, создаёт задачи для Luna, контролирует зависимости, проверяет фактические изменения и тесты, возвращает исправления исполнителям и продолжает работу до выполнения релизных ворот или появления настоящего внешнего блокера.

Глобальная цель назначается Sol-оркестратору. Luna не получает цель «реализовать всё приложение» и не выбирает архитектуру или следующий milestone.

## 2. Зафиксированная конфигурация Sol Advisor

```json
{
  "client": "codex",
  "scope": "project",
  "workspace": "/Users/unterlantas/Documents/XCode/shafinMultitool",
  "orchestrator": {
    "model": "inherit",
    "recommendation": {
      "model": "gpt-5.6-sol",
      "effort": "high"
    }
  },
  "roles": {
    "routine": {
      "model": "gpt-5.6-terra",
      "effort": "high"
    },
    "high": {
      "model": "gpt-5.6-terra",
      "effort": "high"
    },
    "advisor": {
      "model": "gpt-5.6-sol",
      "effort": "high",
      "readonly": true
    }
  },
  "fallbackPolicy": "fail-closed",
  "fallbacks": [],
  "appTaskLane": {
    "enabled": true,
    "model": "gpt-5.6-luna",
    "effort": "max"
  }
}
```

Native-роли Terra сохраняются как редкий high-complexity маршрут, потому что Luna в Sol Advisor является отдельным Codex app-task lane, а не native fallback. Обычная реализация по умолчанию направляется в Luna / Max.

## 3. Routing policy

### Sol / High

Sol владеет:

- глобальной целью и критериями завершения;
- продуктовой и технической архитектурой;
- декомпозицией milestones в исполнимые task packets;
- dependency graph и порядком стеков;
- выдачей Luna точного ownership;
- проверкой реального worktree, base, branch и полного diff;
- повторным запуском проверок;
- correction loop в той же Luna-задаче;
- итоговой приёмкой и обновлением tracker;
- решениями об эскалации в Terra;
- релизными воротами.

Sol advisor/reviewer работает read-only. Поведенческое ограничение не называется OS-enforced, пока Codex не покажет фактический sandbox `read-only`.

### Luna / Max

Luna — основной исполнитель для полностью специфицированных задач, включая:

- локальные компоненты и сервисы с утверждённым контрактом;
- тесты для утверждённого поведения;
- bounded refactors с точным ownership;
- UI-состояния по готовой спецификации;
- wiring и release hygiene;
- механические миграции без открытой продуктовой или архитектурной развилки;
- исправления по конкретным замечаниям Sol.

Каждая Luna-задача получает полный task packet и отдельный user-visible Codex task. Она не наследует контекст основной сессии, не меняет архитектуру, не расширяет scope и не принимает собственный результат.

### Terra / High

Terra используется редко, когда задача остаётся сложной даже после декомпозиции:

- camera/session lifecycle и concurrency;
- persistence/schema migration;
- StoreKit entitlement state machine;
- privacy/security-sensitive server boundary;
- сложная диагностика и нестабильные тесты;
- широкий refactor с несколькими runtime owners;
- повторная неудача Luna, указывающая на недостаточную спецификацию или сложность, а не на механическую ошибку.

Terra не является молчаливым fallback. Sol явно классифицирует задачу как high-complexity и фиксирует причину маршрутизации.

## 4. Автономный цикл

1. Sol читает product source of truth, текущий tracker, git state и evidence предыдущего gate.
2. Sol раскрывает только ближайший milestone и создаёт готовые task packets.
3. Независимые задачи с непересекающимся ownership могут выполняться Luna параллельно в отдельных worktrees.
4. Задачи с общими файлами или зависимостями выполняются последовательно.
5. Luna возвращает structured handoff с фактическими изменениями, командами, результатами и git state.
6. Sol самостоятельно проверяет worktree, полный diff и соответствие ownership.
7. Sol повторяет необходимые тесты и сравнивает результат с acceptance criteria.
8. Ошибки возвращаются в ту же Luna-задачу как точечная correction; новый исполнитель не создаётся ради обхода исправления.
9. После принятия Sol обновляет tracker и запускает следующий ready packet.
10. После завершения milestone Sol выполняет полный gate, обновляет планы и только затем раскрывает следующую волну.
11. Цикл продолжается до release candidate или настоящего блокера, требующего внешнего действия или решения владельца.

## 5. Планирование

Не создаётся плоский список из сотен задач заранее.

- Весь продукт описывается milestones и gates.
- Детально раскрывается только ближайшая волна ориентировочно из 10–30 атомарных пакетов.
- Следующая волна зависит от фактической архитектуры, diff, тестов и результатов предыдущего gate.
- Количество задач является результатом декомпозиции, а не целевым показателем.
- Одна Luna-задача имеет один наблюдаемый результат; допустим небольшой связанный стек без открытых решений.

## 6. Приёмка и полномочия

Worker-отчёт считается утверждением, а не доказательством. Задача получает статус `accepted` только после проверки Sol.

Luna и Terra не могут без отдельного разрешения:

- создавать или отправлять PR;
- делать push;
- объединять ветки;
- менять утверждённый product scope;
- принимать расходы на инфраструктуру;
- принимать privacy/legal решения;
- объявлять App Store release готовым без прохождения ворот.

Автономность охватывает безопасные действия внутри репозитория и доступные автоматические проверки. Физические camera-сценарии, Apple Developer credentials, расходы, TestFlight/App Store submission и юридические решения остаются внешними gates.

## 7. Research input

Актуальный входной отчёт:

`/Users/unterlantas/Downloads/deep-research-report.md`

Отчёт достаточен для начала alpha: recommendation `narrow`, beachhead, локальный coaching loop, trust contract, scope и beta unknowns определены. Перед созданием первой implementation wave Sol переносит принятые выводы в `docs/app-store-product-plan.md`; внешний файл не используется Luna как неявный источник требований.

Research остаётся provisional для willingness to pay, подписки, Deep Review superiority и численных quality thresholds. Эти пункты закрываются benchmark и instrumented beta, а не выдуманными значениями.

## 8. Bootstrap после перезапуска Codex

1. Проверить `get_setup_status` и `get_preferences` через MCP `sol-advisor`.
2. Сохранить project-scoped logical preferences из раздела 2.
3. Выполнить `render_client_adapter` для указанного workspace.
4. Показать точные destination paths, полный content, warnings и install token.
5. Установить adapter только после повторения владельцем точного confirmation token.
6. Перезапустить Codex ещё раз, если native roles появились только после установки adapter.
7. Проверить доступность Codex app-task tools и поддержку `gpt-5.6-luna` / `max`.
8. Зафиксировать product baseline в Git: untracked документы и внешний research не видны изолированным worktrees.
9. Создать tracker, первую волну задач и глобальную Sol-цель отдельными проверяемыми шагами.

## 9. Текущий технический статус

- Sol Advisor plugin version: `0.5.0`.
- Bun установлен через Homebrew: `1.3.14`.
- Каталог данных плагина приведён к обязательному приватному режиму `0700`.
- MCP-инструменты Sol Advisor доступны.
- Project-scoped logical configuration сохранена и повторно прочитана через MCP.
- Native adapter установлен без предупреждений и резервных копий: созданы роли `sol_advisor_routine`, `sol_advisor_high` и `sol_advisor_advisor`.
- MCP-валидация после установки вернула `status: ready` и `valid: true`; фактические хеши всех трёх файлов совпадают с отрендеренным adapter.
- Нужен новый Codex-чат или reload, чтобы native role discovery увидел установленные роли.
