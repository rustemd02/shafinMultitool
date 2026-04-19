# 01. Roadmap

## Phase 0. Baseline and Freeze

Цель:
- заморозить текущее поведение camera-модуля и определить стартовую точку.

Задачи:
- зафиксировать current live/pause UX;
- собрать список существующих сигналов и их частот;
- зафиксировать текущие тексты подсказок;
- собрать baseline screen/video examples;
- зафиксировать known failure modes.

Артефакты:
- `docs/cameraanalysis/baseline-notes.md`
- `docs/cameraanalysis/baseline-failure-modes.md`
- frozen список текущих signals и UI states

PR wave:
- `PR-001 baseline freeze`

## Phase 1. Contracts and Domain Foundation

Цель:
- зафиксировать contracts новой системы до начала активного кодинга.

Задачи:
- описать доменную модель `FrameFeatureSnapshot`, `SceneSemanticsReport`, `CritiqueReport`, `RecommendationPlan`;
- зафиксировать explainability contract;
- определить issue taxonomy и strength taxonomy;
- определить boundary между deterministic logic и LLM layer;
- определить mobile execution policy для `live` и `pause`.

Артефакты:
- domain contract spec: [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md)
- explainability contract spec
- issue taxonomy
- integration contract для presentation layer

PR wave:
- `PR-002 domain contracts`
- `PR-003 explainability contract`

## Phase 2. Deterministic Critique Core

Цель:
- собрать работающее explainable ядро без зависимости от LLM.

Задачи:
- агрегировать текущие признаки в единый snapshot;
- реализовать `PrimarySubjectResolver`;
- реализовать scene-type heuristics/classifier `v1`;
- реализовать `FrameCritiqueEngine`;
- реализовать `RecommendationPlanner`.

Артефакты:
- deterministic critique core
- unit tests для issue detection
- traceable recommendation plan

PR wave:
- `PR-004 feature snapshot aggregator`
- `PR-005 primary subject resolver`
- `PR-006 scene type classifier`
- `PR-007 critique engine`
- `PR-008 recommendation planner`

## Phase 3. Presentation and Runtime Integration

Цель:
- встроить новое ядро в текущий camera UX без разрушения существующего модуля.

Задачи:
- адаптировать `CameraViewModel` под новые states;
- вывести новый `live hint`;
- добавить `pause critique card`;
- добавить overlay annotations;
- сохранить fallback на текущий `SuggestionEngine`.

Артефакты:
- новый live/pause state model
- expanded critique UI
- overlay annotations

PR wave:
- `PR-009 live hint adapter`
- `PR-010 pause critique card`
- `PR-011 overlay annotations`

## Phase 4. LLM and Deep Pause Reasoning

Цель:
- добавить более "умный" и более исследовательски интересный слой reasoning без потери explainability.

Задачи:
- ввести `ReasoningProvider` abstraction;
- реализовать локальный или stubbed hybrid provider;
- ограничить LLM usage в основном pause-режимом;
- использовать LLM для text refinement и optional semantic arbitration;
- добавить graceful degradation при недоступности heavy reasoning.

Артефакты:
- `ReasoningProvider`
- `PauseAnalysisCoordinator`
- LLM-assisted expanded explanation

PR wave:
- `PR-012 reasoning provider abstraction`
- `PR-013 pause LLM explanation`

## Phase 5. Evaluation and Runtime Feedback

Цель:
- сделать систему измеримой и пригодной к итеративному улучшению.

Задачи:
- собрать curated cinematic eval set;
- реализовать automated evaluation harness;
- зафиксировать quality metrics;
- добавить runtime feedback logging;
- добавить backlog для hard failure cases.

Артефакты:
- eval dataset
- metrics report
- runtime feedback log format
- failure backlog

PR wave:
- `PR-014 eval harness`
- `PR-015 runtime feedback loop foundation`

## Рекомендуемый порядок реализации

1. `PR-001`
2. `PR-002`
3. `PR-003`
4. `PR-004`
5. `PR-005`
6. `PR-006`
7. `PR-007`
8. `PR-008`
9. `PR-010`
10. `PR-009`
11. `PR-011`
12. `PR-012`
13. `PR-013`
14. `PR-014`
15. `PR-015`

## Что можно запускать параллельно

- `PR-002` + `PR-003`
- `PR-005` + `PR-006` после `PR-004`
- `PR-010` + `PR-011` после `PR-007` и `PR-008`
- `PR-014` + `PR-015` после стабилизации core contracts

## Что нельзя делать раньше времени

- не переводить live UI на новый pipeline, пока не зафиксирован `CritiqueReport` contract;
- не подключать LLM к текстам, пока нет deterministic critique core;
- не запускать глубокий pause reasoning, пока нет fallback path;
- не строить eval метрики до фиксации issue taxonomy;
- не распараллеливать PR с пересекающимся write scope без явного ownership.
