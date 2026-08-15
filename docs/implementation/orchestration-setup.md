# Автономная реализация: Sol Advisor logical profile и visible Luna thread lane

Статус: `active`.

Дата: 15 августа 2026 года.

## 1. Цель

Основная Sol-сессия автономно доводит Camera Coach до проверенного release candidate: поддерживает исполнимый backlog, создаёт user-visible Codex threads для Luna / Max, контролирует зависимости, принимает structured handoff с task-level evidence, возвращает исправления в новые visible threads и продолжает работу до выполнения релизных ворот или появления настоящего внешнего блокера. Реализацию, тестирование, correction loops, task-level independent review и verification полностью выполняют видимые Luna / Max threads.

Глобальная цель назначается main-chat Sol-оркестратору. Видимый Luna / Max thread получает только полностью специфицированный task packet и не выбирает архитектуру или следующий milestone.

## Durable goal-policy boundary

The active system goal text is immutable through the goal API while it is active. The durable goal-policy amendment is recorded in `docs/aegis/work/2026-08-15-camera-coach-release/10-intent.md` and `20-checkpoint.md`.

The main chat is the sole Sol orchestrator. Every new executor, reviewer, correction-loop or verification worker MUST be a separate USER-VISIBLE Codex chat/thread, never a hidden collaboration subagent. When continuing the current checkout, create the thread with `environment.type=local`, explicit `model=gpt-5.6-luna` and `thinking=max`; hidden collaboration spawning is forbidden. If the visible Luna / Max thread cannot be created, fail closed rather than using a hidden task or substituting another model. The parent/main-chat Sol may own architecture, low-level task contracts, the tracker and one bounded risk-based milestone acceptance only, and may create/manage visible Luna / Max threads; it MUST NOT create hidden workers or any Sol, Terra or inherited-model worker thread.

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

The JSON above is the logical profile: its orchestrator remains `inherit` with a `gpt-5.6-sol` / `high` recommendation, while routine, high and advisor profiles remain `gpt-5.6-luna` / `max`, with fail-closed fallbacks. It does not authorize native role execution.

The current execution route is a new user-visible Codex chat/thread for every executor, reviewer, correction loop and verification worker. When continuing the current checkout, its required settings are project-local (`environment.type=local`), explicit `model=gpt-5.6-luna`, `thinking=max`, and no hidden collaboration spawning. The installed native adapter is not reinstalled/reloaded, so native Sol/Terra/inherited-model roles are not a valid execution path; if the visible Luna / Max thread cannot be created, stop fail-closed.

## 3. Routing policy

### Parent/main-chat Sol (orchestrator only)

Parent/main-chat Sol владеет только:

- глобальной целью и критериями завершения;
- продуктовой и технической архитектурой;
- low-level task contracts, dependency graph и порядок стеков;
- выдачей Luna / Max точного ownership;
- tracker;
- одной bounded risk-based milestone acceptance после Luna / Max evidence.

Parent/main-chat Sol does not perform task-level independent review or verification and MUST NOT create hidden workers or any Sol reviewer, advisor or implementer thread. It may create/manage visible Luna / Max threads and consume their evidence for the single bounded milestone acceptance only.

### Luna / Max

Luna / Max — единственный visible-thread исполнитель и task-level reviewer/verifier для полностью специфицированных задач, включая:

- локальные компоненты и сервисы с утверждённым контрактом;
- всю реализацию и тесты для утверждённого поведения;
- bounded refactors с точным ownership;
- UI-состояния по готовой спецификации;
- wiring и release hygiene;
- механические миграции без открытой продуктовой или архитектурной развилки;
- correction loops и task-level independent review/verification по конкретным замечаниям main-chat Sol.

Каждая Luna / Max задача получает полный task packet и отдельный user-visible Codex chat/thread с явными `environment.type=local` (если продолжается текущий checkout), `model=gpt-5.6-luna` и `thinking=max`. Она не наследует контекст основной сессии, не меняет архитектуру, не расширяет scope и не подменяется hidden/native/другим model lane.

### Terra / High (historical classification; disabled)

Следующий список сохраняется как историческая классификация прежней конфигурации, а не как действующий маршрут:

- camera/session lifecycle и concurrency;
- persistence/schema migration;
- StoreKit entitlement state machine;
- privacy/security-sensitive server boundary;
- сложная диагностика и нестабильные тесты;
- широкий refactor с несколькими runtime owners;
- повторная неудача Luna, указывающая на недостаточную спецификацию или сложность, а не на механическую ошибку.

Ни один пункт не разрешает создание Terra worker thread: текущая политика запрещает Terra, Sol и inherited-model worker threads. Если задача остаётся сложной, создаётся новый visible Luna / Max thread с уточнённым packet или correction loop; при невозможности создать его работа завершается fail-closed.

## 4. Автономный цикл

1. Sol читает product source of truth, текущий tracker, git state и evidence предыдущего gate.
2. Sol раскрывает только ближайший milestone и создаёт готовые task packets.
3. Независимые задачи с непересекающимся ownership могут выполняться в отдельных user-visible Luna / Max threads только при явно безопасном project-local checkout; thread, продолжающий текущий checkout, использует `environment.type=local`.
4. Задачи с общими файлами или зависимостями выполняются последовательно.
5. Видимый Luna / Max thread возвращает structured handoff с фактическими изменениями, task-level review/verification evidence, командами, результатами и git state.
6. Отдельный visible Luna / Max thread выполняет независимую task-level review/verification; parent/main-chat Sol принимает evidence, не создавая скрытый или Sol/Terra/inherited-model worker.
7. Ошибки передаются в новый visible Luna / Max correction thread как точечная correction; hidden task или новый запрещённый model lane не создаётся.
8. После task-level verification parent/main-chat Sol обновляет tracker и запускает следующий ready packet.
9. После завершения milestone parent/main-chat Sol выполняет только одну bounded risk-based milestone acceptance на Luna / Max evidence, обновляет планы и только затем раскрывает следующую волну.
10. Цикл продолжается до release candidate или настоящего блокера, требующего внешнего действия, решения владельца или Luna / Max; невозможность создать очередной visible Luna / Max thread означает fail-closed stop.

## 5. Планирование

Не создаётся плоский список из сотен задач заранее.

- Весь продукт описывается milestones и gates.
- Детально раскрывается только ближайшая волна ориентировочно из 10–30 атомарных пакетов.
- Следующая волна зависит от фактической архитектуры, diff, тестов и результатов предыдущего gate.
- Количество задач является результатом декомпозиции, а не целевым показателем.
- Одна Luna-задача имеет один наблюдаемый результат; допустим небольшой связанный стек без открытых решений.

## 6. Приёмка и полномочия

Worker-отчёт считается утверждением, а не доказательством. Task-level статус получает `accepted` только после независимой review/verification в отдельном visible Luna / Max thread; parent/main-chat Sol не выполняет task-level acceptance и может учесть evidence только в одной bounded risk-based milestone acceptance.

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

## 8. Resume/bootstrap после перезапуска Codex

1. Проверить `get_setup_status` и `get_preferences` через MCP `sol-advisor`.
2. Сохранить project-scoped logical preferences из раздела 2.
3. Не выполнять `render_client_adapter`, reinstall или reload: установленный native adapter остаётся без переустановки/перезагрузки, а его native role paths не являются допустимым execution path.
4. Для каждого нового executor, reviewer, correction loop или verification worker создать отдельный USER-VISIBLE Codex chat/thread с `model=gpt-5.6-luna` и `thinking=max`; при продолжении текущего checkout выбрать project-local `environment.type=local`.
5. Проверить, что видимый thread создан и доступен владельцу; если видимый Luna / Max thread недоступен, завершить работу fail-closed без hidden collaboration worker и без model substitution.
6. Зафиксировать product baseline в Git: untracked документы и внешний research не видны изолированным worktrees.
7. Создать tracker, первую волну задач и глобальную Sol-цель отдельными проверяемыми шагами.

## 9. Текущий технический статус

- Sol Advisor plugin version: `0.5.0`.
- Bun установлен через Homebrew: `1.3.14`.
- Каталог данных плагина приведён к обязательному приватному режиму `0700`.
- MCP-инструменты Sol Advisor доступны.
- Project-scoped logical configuration сохранена и повторно прочитана через MCP.
- Историческая запись bootstrap: native adapter был установлен без предупреждений и резервных копий; имена ролей `sol_advisor_routine`, `sol_advisor_high` и `sol_advisor_advisor` не являются текущими worker-thread routes.
- MCP-валидация после установки вернула `status: ready` и `valid: true`; фактические хеши всех трёх файлов совпадают с отрендеренным adapter.
- Native role discovery и Codex app-task lane подтверждены историческими рабочими задачами; это не разрешает native или hidden execution. Текущая policy требует отдельные user-visible Codex threads с явными `model=gpt-5.6-luna` и `thinking=max`.
- Автономный цикл запущен: main-chat Sol выдаёт contracts и обновляет tracker, а visible Luna / Max threads выполняют реализацию, тестирование, correction loops, task-level review и verification; при продолжении current checkout используется project-local environment.
