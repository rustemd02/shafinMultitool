# 04. Explainability Contract (PR-003)

Статус: design spec (source-of-truth)

Дата: 2026-04-19

Связанные документы:
- [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/README.md)
- [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md)
- [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- [camera-analysis-v1-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/camera-analysis-v1-architecture.md)

## Цель

Зафиксировать explainability contract для `Camera Analysis v1`, чтобы:
- `FrameCritiqueEngine` и `RecommendationPlanner` ссылались на trace как на source-of-truth;
- debug/eval/UI получали одинаковую причинно-следственную структуру;
- deterministic core и optional LLM layer использовали совместимый формат.

## Boundary и роль в pipeline

Explainability trace не заменяет доменные отчеты, а связывает их:
- `observation`: измеримые сигналы из `FrameFeatureSnapshot` и `SceneSemanticsReport`;
- `interpretation`: выводы правил/аналитики;
- `recommendation`: конкретные действия из `RecommendationPlan`.

Минимальная целостность:
- каждый `FrameIssue` и `FrameStrength` обязан иметь ссылку хотя бы на один trace item;
- каждое действие `RecommendationAction` обязано иметь ссылку на trace items, которые его обосновывают;
- в `good`-кадрах trace должен объяснять, почему нужно `leave_frame_as_is`.

## Type Definitions

```text
TraceStage
- observation
- interpretation
- recommendation

TraceSourceKind
- snapshot_signal
- semantics_signal
- deterministic_rule
- planner_policy
- optional_reasoning

TraceCertainty
- deterministic
- probabilistic
- speculative

TraceAudience
- core
- debug
- eval
- ui

TraceLink
- kind: TraceLinkKind (required)
- refId: String (required)

TraceLinkKind
- issue
- strength
- action
- overlay
- summary

ExplainabilityTraceItem
- id: String (required, globally unique within frame)
- frameId: String (required)
- mode: AnalysisMode (required, live|pause)
- stage: TraceStage (required)
- sourceKind: TraceSourceKind (required)
- certainty: TraceCertainty (required)
- confidence: Double (required, 0...1)
- timestampMs: Int (required, monotonic within frame trace)
- statement: String (required, concise human-readable claim)
- evidenceKeys: [String] (required, keys вида snapshot.*, semantics.*, rule.*, planner.*)
- dependsOn: [String] (required, ids предыдущих trace items)
- links: [TraceLink] (required)
- audiences: [TraceAudience] (required, хотя бы core)
- metadata: [String: String] (optional, model/version/debug extras)

ExplainabilityTraceBundle
- frameId: String
- mode: AnalysisMode
- items: [ExplainabilityTraceItem]
- rootSummaryIds: [String]   // trace items для short verdict/live hint; каждый root обязан нести summary-role
```

## Матрица допустимых `stage x sourceKind`

Допустимые комбинации для `v1`:

| `sourceKind` | `observation` | `interpretation` | `recommendation` |
| --- | --- | --- | --- |
| `snapshot_signal` | yes | no | no |
| `semantics_signal` | yes | no | no |
| `deterministic_rule` | no | yes | no |
| `planner_policy` | no | no | yes |
| `optional_reasoning` | no | yes | no |

Любая комбинация вне таблицы считается невалидной для contract tests.

## Правила разрешения `TraceLink.refId`

`refId` всегда указывает на runtime ID в пределах того же `frameId + mode`:

- `issue` -> `FrameIssue.id`
- `strength` -> `FrameStrength.id`
- `action` -> `RecommendationAction.id`
- `overlay` -> `RecommendationAction.overlayHint.id`
- `summary` -> `CritiqueSummary.id`

Использование taxonomy ключей вместо runtime ID (`issue_backlight_hides_subject`) для `refId` не допускается.

## Каноническая цепочка `observation -> interpretation -> recommendation`

Для каждого проблемного и позитивного кейса цепочка должна быть явно представима:

1. Observation:
`snapshot.*` / `semantics.*` сигналы без вывода "что делать".

2. Interpretation:
правило/логика формирует объяснимый вывод (issue/strength/priority rationale).
Каждый `interpretation` item обязан быть заземлен минимум на одном `observation` item.

3. Recommendation:
planner выбирает действие, связывая его с интерпретацией и guardrails.

Один `recommendation` item может зависеть от нескольких `interpretation` items.

## Invariants

1. `dependsOn` никогда не ссылается на будущие или несуществующие `id`.
2. Для каждого item: `item.frameId == bundle.frameId` и `item.mode == bundle.mode`.
3. `observation` item может зависеть только от `observation` items.
4. `interpretation` item может зависеть только от `observation` items и обязан иметь хотя бы один dependency.
5. `recommendation` item может зависеть только от `interpretation` items c `sourceKind == deterministic_rule` и обязан иметь хотя бы один dependency.
6. Граф зависимостей `dependsOn` обязан быть ацикличным.
7. Для каждого ребра `dep -> item` выполняется строгий порядок времени: `dep.timestampMs < item.timestampMs`.
8. Пара `stage + sourceKind` обязана соответствовать матрице допустимых комбинаций.
9. Если `dependsOn` непустой, `confidence(item) <= max(confidence(dependsOn)) + 0.1`.
10. Если `dependsOn` пустой (обычно observation roots), действует только диапазон `0...1`.
11. Если `certainty == speculative`, то `sourceKind` не может быть `deterministic_rule`.
12. Любой `TraceLink` обязан резолвиться по правилам `TraceLink.refId` в пределах текущих `frameId + mode`.
13. `rootSummaryIds` должны ссылаться на существующие items со stage `interpretation` или `recommendation`.
14. Каждый item из `rootSummaryIds` обязан содержать минимум один `TraceLink(kind: summary, refId: CritiqueSummary.id)` для текущих `frameId + mode`.
15. При `mode == live` bundle должен оставаться компактным (рекомендуемо <= 12 items), но для каждого action должна сохраняться полная причинная цепочка из 3 стадий.
16. `optional_reasoning` items только append-only: они не изменяют и не удаляют items deterministic core.
17. Для каждого `FrameIssue.id` из `CritiqueReport(frameId, mode)` должен существовать минимум один `interpretation` item с `TraceLink(kind: issue, refId: issue.id)`.
18. Для каждого `FrameStrength.id` из `CritiqueReport(frameId, mode)` должен существовать минимум один `interpretation` item с `TraceLink(kind: strength, refId: strength.id)`.
19. Для каждого `RecommendationAction.id` из `RecommendationPlan(frameId, mode)` должен существовать минимум один `recommendation` item с `TraceLink(kind: action, refId: action.id)`.
20. Если `CritiqueReport(frameId, mode).verdict == good` и `RecommendationPlan(frameId, mode)` не требует corrective actions, trace обязан содержать `summary`-ссылку на `CritiqueSummary.id`, объясняющую `leave_frame_as_is` path.

## Serialization и совместимость

- Формат должен быть безопасен для JSON serialization.
- `id` рекомендовано в виде: `trc_<frameIdShort>_<nnn>`.
- Порядок в `items` не является source-of-truth; source-of-truth задается через `dependsOn` и `timestampMs`.
- Не допускается hard dependency на конкретный model name или endpoint.
- Для deterministic-only рантайма `sourceKind == optional_reasoning` просто отсутствует.

## Политика deterministic core vs optional reasoning

- Источник истины для issues/actions: deterministic core (`snapshot_signal`, `semantics_signal`, `deterministic_rule`, `planner_policy`).
- `optional_reasoning` в `v1` разрешен только на стадии `interpretation` и не создает `TraceLink(kind: action)`.
- `RecommendationPlanner` принимает решения только по deterministic items; это enforce-ится инвариантом #5.
- optional reasoning может дополнять объяснение и `summary`, но не влияет на `recommendation.dependsOn`.
- Если optional reasoning противоречит deterministic interpretation, planner/UI сохраняют deterministic decision, а конфликт маркируется в `metadata` (`conflictWith=<traceItemId>`).

## Использование trace

### Debug
- показывать DAG причин для выбранного issue/action;
- быстро находить, на каком шаге потеряна уверенность;
- сравнивать live и pause trace на одном `frameId`.

### Eval
- метрика faithfulness: каждое действие имеет поддерживающие interpretation items и наблюдения;
- метрика contradiction rate: нет несовместимых interpretation items для одного summary;
- метрика coverage: доля issues/actions с валидной цепочкой из 3 стадий.

### UI
- live: использовать `rootSummaryIds` для одной краткой подсказки;
- pause: раскрывать "почему" по тапу (observation -> interpretation -> action);
- good-кадры: показывать strengths и причины сохранения кадра без искусственных проблем.

## Trace Examples (7)

Примеры ниже JSON-like, сокращенные, но соблюдают цепочку.

### Example 1. Плохой кадр: объект прижат к правому краю

```text
o1: stage=observation, statement="subjectSignals.primaryCandidateRegion.x=0.83", evidenceKeys=["snapshot.subjectSignals.primaryCandidateRegion.x"]
i1: stage=interpretation, statement="Главный объект прижат к правому краю", dependsOn=["o1"], links=[issue:iss_f1021_1]
r1: stage=recommendation, statement="Сместить кадр левее", dependsOn=["i1"], links=[action:act_f1021_1, overlay:ov_a1_left_arrow]
```

### Example 2. Плохой кадр: контровой свет скрывает лицо

```text
o1: observation "snapshot.lighting.backlightIndex=0.86"
o2: observation "semantics.primarySubject.kind=face, confidence=0.88"
i1: interpretation "Контровой свет снижает читаемость лица", dependsOn=["o1","o2"], links=[issue:iss_f1021_2]
r1: recommendation "Повернуться к источнику света или добавить фронтальный свет", dependsOn=["i1"], links=[action:act_f1021_2]
```

### Example 3. Плохой кадр: визуальная перегрузка фона

```text
o1: observation "semantics.dominance.backgroundClutterScore=0.79"
o2: observation "semantics.dominance.focusCompetitionScore=0.74"
i1: interpretation "Нет ясного центра внимания", dependsOn=["o1","o2"], links=[issue:iss_f1600_1]
r1: recommendation "Упростить фон и приблизить объект", dependsOn=["i1"], links=[action:act_f1600_1]
```

### Example 4. Плохой кадр: недостаточно look space

```text
o1: observation "semantics.readability.lookSpaceAdequate=false"
o2: observation "snapshot.composition.horizontalOffset=0.67"
i1: interpretation "По направлению взгляда не хватает воздуха", dependsOn=["o1","o2"], links=[issue:iss_f1702_1]
r1: recommendation "Сместить камеру в сторону свободного пространства", dependsOn=["i1"], links=[action:act_f1702_1]
```

### Example 5. Хороший кадр: читаемый субъект и чистый фон

```text
o1: observation "semantics.readability.separationScore=0.81"
o2: observation "semantics.dominance.hasClearFocus=true"
i1: interpretation "Главный объект хорошо отделен от фона", dependsOn=["o1","o2"], links=[strength:str_f2033_1]
r1: recommendation "Оставить кадр как есть", dependsOn=["i1"], links=[action:act_f2033_1, summary:summary_f2033_main]
```

### Example 6. Хороший кадр: стабильный горизонт и balanced composition

```text
o1: observation "snapshot.horizon.angleDegrees=0.7"
o2: observation "snapshot.composition.horizontalOffset=0.08"
i1: interpretation "Композиция визуально сбалансирована, горизонт не отвлекает", dependsOn=["o1","o2"], links=[strength:str_f2034_1]
r1: recommendation "Сохранять текущий ракурс", dependsOn=["i1"], links=[action:act_f2034_1, summary:summary_f2034_main]
```

### Example 7. Mixed/uncertain: неоднозначный главный субъект

```text
o1: observation "semantics.ambiguities includes multiple_subjects_similar_confidence"
i1: interpretation "Неопределенность субъекта повышает риск потери фокуса", sourceKind=deterministic_rule, certainty=probabilistic, dependsOn=["o1"], links=[issue:iss_f2801_1]
i2: interpretation "Вероятно, приоритетнее ближайший человек в центре", sourceKind=optional_reasoning, certainty=speculative, dependsOn=["o1"], links=[summary:summary_f2801_main]
r1: recommendation "Сделать шаг ближе к предполагаемому главному объекту", dependsOn=["i1"], links=[action:act_f2801_1]
```

## Guidance для `design -> implement`

Минимум для реализации (`PR-003`):
- ввести сериализуемые типы `ExplainabilityTraceItem` и `ExplainabilityTraceBundle`;
- покрыть tests на invariants DAG, stage-order и `stage x sourceKind` matrix;
- покрыть tests на `TraceLink.refId` resolution (`issue/strength/action/overlay/summary`);
- покрыть tests на cross-contract coverage (`issue/strength/action` <-> trace links);
- подготовить fixture traces для bad/good/mixed кейсов.

Проверка готовности design:
- critique engine и planner могут ссылаться на trace IDs без домысливания;
- debug/eval/UI используют один и тот же contract без дополнительных преобразований смысла.
