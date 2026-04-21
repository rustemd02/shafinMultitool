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
- explainability contract spec: [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md)
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

## Phase 6. Hybrid Neural Augmentation

Цель:
- усилить deterministic critique core нейросетевым evidence layer-ом без потери explainability.

Задачи:
- зафиксировать hybrid thesis и layer boundaries;
- определить evidence taxonomy и scoring axes;
- определить dataset schema и labeling protocol;
- определить AVA usage policy;
- определить compact on-device model и runtime contract.

Артефакты:
- hybrid architecture section inside [02-pipeline-architecture.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/02-pipeline-architecture.md)
- hybrid backlog and DoD inside [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md)
- research framing source-of-truth inside [14-hybrid-research-framing.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/14-hybrid-research-framing.md)
- hybrid prompts inside [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/12-agent-prompts.md)

PR wave:
- `PR-H01 thesis and hybrid scope freeze`
- `PR-H02 evidence taxonomy contract`
- `PR-H03 dataset schema and labeling guide`
- `PR-H04 AVA usage policy and pretraining design`
- `PR-H05 hybrid model architecture spec`
- `PR-H06 neural evidence domain contract`

## Phase 7. On-Device Hybrid Runtime

Цель:
- встроить compact neural evidence path в runtime сначала безопасно, потом полезно.

Задачи:
- подключить on-device inference wrapper;
- сначала ввести pause-only neural evidence path;
- затем fusion and reranking;
- затем optional live gating.

Артефакты:
- on-device inference wrapper
- hybrid fusion layer
- reranking / confidence calibration policy

PR wave:
- `PR-H07 on-device inference wrapper`
- `PR-H08 pause-only neural evidence path`
- `PR-H09 hybrid fusion layer`
- `PR-H10 neural reranker`
- `PR-H11 live neural gating`

## Phase 8. Gated Offloading and Thesis Demo

Цель:
- добавить deep-analysis path без потери offline-first архитектуры и подготовить демонстрацию для защиты.

Задачи:
- ввести offloading contract;
- при необходимости подключить teacher/richer critic;
- расширить eval для hybrid stage;
- логировать hybrid hard cases;
- собрать thesis demo bundle.

Артефакты:
- offloading contract
- hybrid eval outputs
- runtime telemetry for hybrid disagreements
- demo scenarios

PR wave:
- `PR-H12 offloading contract`
- `PR-H13 server / teacher critic prototype`
- `PR-H14 hybrid eval harness`
- `PR-H15 hybrid runtime telemetry`
- `PR-H16 thesis demo bundle`

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
16. `PR-H01`
17. `PR-H02`
18. `PR-H03`
19. `PR-H04`
20. `PR-H05`
21. `PR-H06`
22. `PR-H07`
23. `PR-H08`
24. `PR-H09`
25. `PR-H10`
26. `PR-H11`
27. `PR-H12`
28. `PR-H13`
29. `PR-H14`
30. `PR-H15`
31. `PR-H16`

## Что можно запускать параллельно

- `PR-002` + `PR-003`
- `PR-005` + `PR-006` после `PR-004`
- `PR-010` + `PR-011` после `PR-007` и `PR-008`
- `PR-014` + `PR-015` после стабилизации core contracts
- `PR-H03` + частично `PR-H04`
- `PR-H10` + `PR-H12` после стабилизации fusion contract
- `PR-H15` + `PR-H16` после появления первых hybrid eval outputs

## Что нельзя делать раньше времени

- не переводить live UI на новый pipeline, пока не зафиксирован `CritiqueReport` contract;
- не подключать LLM к текстам, пока нет deterministic critique core;
- не запускать глубокий pause reasoning, пока нет fallback path;
- не строить eval метрики до фиксации issue taxonomy;
- не распараллеливать PR с пересекающимся write scope без явного ownership.
- не обучать hybrid model до фиксации evidence taxonomy и rubric;
- не пускать neural signal в `live` раньше pause-only validation;
- не использовать `AVA` как итоговый source-of-truth для cinematic quality;
- не строить offloading как обязательный путь для базового UX.
