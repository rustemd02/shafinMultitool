# Автономная реализация: Sol Advisor и Luna task lane

Статус: `active`.

Дата: 15 августа 2026 года.

## 1. Цель

Основная Sol-сессия автономно доводит Camera Coach до проверенного release candidate: поддерживает исполнимый backlog, создаёт задачи для Luna / Max, контролирует зависимости, принимает structured handoff с task-level evidence, возвращает исправления исполнителям и продолжает работу до выполнения релизных ворот или появления настоящего внешнего блокера. Реализацию, тестирование, correction loops, task-level independent review и verification полностью выполняет Luna / Max.

Глобальная цель назначается main-chat Sol-оркестратору. Luna / Max получает только полностью специфицированные task packets и не выбирает архитектуру или следующий milestone.

## Durable goal-policy boundary

The active system goal text is immutable through the goal API while it is active. The durable goal-policy amendment is recorded in `docs/aegis/work/2026-08-15-camera-coach-release/10-intent.md` and `20-checkpoint.md`.

The main chat is the sole Sol orchestrator. Every spawned subagent for this project MUST be GPT-5.6 Luna / Max. Never spawn a Sol, Terra or inherited-model subagent; if Luna / Max is unavailable, fail closed rather than substituting another model. The parent/main-chat Sol may own architecture, low-level task contracts, the tracker and one bounded risk-based milestone acceptance only, and MUST NOT spawn any Sol reviewer, advisor or implementer subagent.

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
      "model": "gpt-5.6-luna",
      "effort": "max"
    },
    "high": {
      "model": "gpt-5.6-luna",
      "effort": "max"
    },
    "advisor": {
      "model": "gpt-5.6-luna",
      "effort": "max",
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

Luna / Max is the only current spawned-subagent route, for routine, high-complexity, implementation, review and verification work. The saved profile's `inherit` orchestrator is the main-chat Sol coordinator only; it is never a spawned-subagent route. There is no Terra/native or inherited-model subagent fallback. Unavailability of Luna / Max is a hard stop.

Until the saved adapter is explicitly reinstalled/reloaded after owner confirmation, every spawn MUST use explicit args `fork_turns=none`, `model=gpt-5.6-luna`, `reasoning_effort=max`; do not use inherited/native Sol Advisor roles. The logical profile is `ready`/`valid`, but the installed adapter target state differs.

## 3. Routing policy

### Parent/main-chat Sol (orchestrator only)

Parent/main-chat Sol владеет только:

- глобальной целью и критериями завершения;
- продуктовой и технической архитектурой;
- low-level task contracts, dependency graph и порядок стеков;
- выдачей Luna / Max точного ownership;
- tracker;
- одной bounded risk-based milestone acceptance после Luna / Max evidence.

Parent/main-chat Sol does not perform task-level independent review or verification and MUST NOT spawn any Sol reviewer, advisor or implementer subagent. It may consume Luna / Max evidence for the single bounded milestone acceptance only.

### Luna / Max

Luna / Max — единственный spawned-subagent исполнитель и task-level reviewer/verifier для полностью специфицированных задач, включая:

- локальные компоненты и сервисы с утверждённым контрактом;
- всю реализацию и тесты для утверждённого поведения;
- bounded refactors с точным ownership;
- UI-состояния по готовой спецификации;
- wiring и release hygiene;
- механические миграции без открытой продуктовой или архитектурной развилки;
- correction loops и task-level independent review/verification по конкретным замечаниям main-chat Sol.

Каждая Luna / Max задача получает полный task packet и отдельный user-visible Codex task. Она не наследует контекст основной сессии, не меняет архитектуру, не расширяет scope и не подменяется другим model lane.

### Terra / High (historical classification; disabled)

Следующий список сохраняется как историческая классификация прежней конфигурации, а не как действующий маршрут:

- camera/session lifecycle и concurrency;
- persistence/schema migration;
- StoreKit entitlement state machine;
- privacy/security-sensitive server boundary;
- сложная диагностика и нестабильные тесты;
- широкий refactor с несколькими runtime owners;
- повторная неудача Luna, указывающая на недостаточную спецификацию или сложность, а не на механическую ошибку.

Ни один пункт не разрешает запуск Terra: текущая политика запрещает Terra subagents, Sol subagents и inherited-model subagents. Если задача остаётся сложной, Luna / Max получает уточнённый packet или task-level correction loop; при недоступности Luna / Max работа завершается fail-closed.

## 4. Автономный цикл

1. Sol читает product source of truth, текущий tracker, git state и evidence предыдущего gate.
2. Sol раскрывает только ближайший milestone и создаёт готовые task packets.
3. Независимые задачи с непересекающимся ownership могут выполняться Luna параллельно в отдельных worktrees.
4. Задачи с общими файлами или зависимостями выполняются последовательно.
5. Luna / Max возвращает structured handoff с фактическими изменениями, task-level review/verification evidence, командами, результатами и git state.
6. Luna / Max выполняет независимую task-level review/verification; parent/main-chat Sol принимает evidence, не создавая Sol reviewer/advisor/implementer subagent.
7. Ошибки возвращаются в ту же Luna / Max задачу как точечная correction; новый model lane не создаётся ради обхода исправления.
8. После task-level verification parent/main-chat Sol обновляет tracker и запускает следующий ready packet.
9. После завершения milestone parent/main-chat Sol выполняет только одну bounded risk-based milestone acceptance на Luna / Max evidence, обновляет планы и только затем раскрывает следующую волну.
10. Цикл продолжается до release candidate или настоящего блокера, требующего внешнего действия, решения владельца или Luna / Max, причём недоступность Luna / Max означает fail-closed stop.

## 5. Планирование

Не создаётся плоский список из сотен задач заранее.

- Весь продукт описывается milestones и gates.
- Детально раскрывается только ближайшая волна ориентировочно из 10–30 атомарных пакетов.
- Следующая волна зависит от фактической архитектуры, diff, тестов и результатов предыдущего gate.
- Количество задач является результатом декомпозиции, а не целевым показателем.
- Одна Luna-задача имеет один наблюдаемый результат; допустим небольшой связанный стек без открытых решений.

## 6. Приёмка и полномочия

Worker-отчёт считается утверждением, а не доказательством. Task-level статус получает `accepted` только после независимой review/verification Luna / Max; parent/main-chat Sol не выполняет task-level acceptance и может учесть evidence только в одной bounded risk-based milestone acceptance.

Luna / Max не могут без отдельного разрешения:

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
6. Не активировать native Sol/Terra/inherited-model subagent roles; после установки adapter проверить, что единственный spawned-subagent route — GPT-5.6 Luna / Max с `max` effort.
7. Проверить доступность Codex app-task tools и поддержку `gpt-5.6-luna` / `max`.
8. Зафиксировать product baseline в Git: untracked документы и внешний research не видны изолированным worktrees.
9. Создать tracker, первую волну задач и глобальную Sol-цель отдельными проверяемыми шагами.

## 9. Текущий технический статус

- Sol Advisor plugin version: `0.5.0`.
- Bun установлен через Homebrew: `1.3.14`.
- Каталог данных плагина приведён к обязательному приватному режиму `0700`.
- MCP-инструменты Sol Advisor доступны.
- Project-scoped logical configuration сохранена и повторно прочитана через MCP.
- Историческая запись bootstrap: native adapter был установлен без предупреждений и резервных копий; имена ролей `sol_advisor_routine`, `sol_advisor_high` и `sol_advisor_advisor` не являются текущими subagent routes.
- MCP-валидация после установки вернула `status: ready` и `valid: true`; фактические хеши всех трёх файлов совпадают с отрендеренным adapter.
- Native role discovery и Codex app-task lane подтверждены рабочими задачами; текущая policy разрешает только GPT-5.6 Luna / Max для spawned subagents.
- Автономный цикл запущен: main-chat Sol выдаёт contracts и обновляет tracker, а Luna / Max выполняет реализацию, тестирование, correction loops, task-level review и verification в отдельных worktrees.
