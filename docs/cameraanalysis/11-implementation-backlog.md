# 11. Implementation Backlog

## Цель

Перевести `Camera Analysis v1` в детерминированные треки и PR-юниты, которые можно безопасно отдавать отдельным AI-агентам.

## Track 0. Baseline Freeze

Задачи:
- описать текущий runtime flow;
- зафиксировать current signals;
- собрать baseline UX/screens/examples;
- перечислить existing failure modes.

Done definition:
- есть baseline note;
- есть frozen список current hint behaviors;
- есть список текущих пробелов, на которые будет меряться улучшение.

## Track 1. Domain Contracts

Задачи:
- описать `FrameFeatureSnapshot`;
- описать `SceneSemanticsReport`;
- описать `CritiqueReport`;
- описать `RecommendationPlan`;
- описать issue/strength taxonomy.

Done definition:
- есть markdown/spec;
- есть example JSON-like records;
- по контракту можно писать код без домысливания.

## Track 2. Explainability Contract

Задачи:
- описать `ExplainabilityTraceItem`;
- зафиксировать цепочку `observation -> interpretation -> recommendation`;
- задать contract для debug/eval/UI.

Done definition:
- любой issue и action можно объяснить trace-элементами;
- есть примеры trace для плохого и хорошего кадра.

## Track 3. Feature Aggregation

Задачи:
- собрать fast signals из текущего pipeline;
- ввести `FrameFeatureSnapshot`;
- нормализовать частично дублирующиеся signals;
- определить source priorities и defaults.

Done definition:
- есть единый snapshot builder;
- есть unit tests на агрегацию;
- нет дублирования логики по разным слоям.

## Track 4. Scene Semantics

Задачи:
- реализовать `PrimarySubjectResolver`;
- реализовать `SceneTypeClassifier`;
- реализовать `VisualDominanceAnalyzer`;
- реализовать `SemanticReadabilityAnalyzer`.

Done definition:
- система выдает `SceneSemanticsReport`;
- есть deterministic behavior на golden cases;
- confidence и fallback rules формализованы.

## Track 5. Critique Core

Задачи:
- реализовать `FrameCritiqueEngine`;
- реализовать strengths/issues detection;
- ввести severity/confidence model;
- описать affected regions.

Done definition:
- из snapshot и semantics строится валидный `CritiqueReport`;
- есть golden tests на issue detection.

## Track 6. Recommendation Layer

Задачи:
- реализовать `RecommendationPlanner`;
- приоритизировать действия;
- отличать `live` primary action от `pause` expanded actions;
- строить overlay annotations.

Done definition:
- есть deterministic `RecommendationPlan`;
- primary action стабилен и объясним;
- есть mapping issue -> action.

## Track 7. UI Integration

Задачи:
- адаптировать view model;
- добавить `live hint` нового типа;
- добавить expanded critique UI для pause;
- встроить overlay annotations;
- сохранить fallback на current suggestion engine.

Done definition:
- live и pause используют новый contract;
- UI не ломает текущий camera flow;
- fallback path работает.

## Track 8. LLM / Hybrid Reasoning

Задачи:
- ввести `ReasoningProvider` abstraction;
- подключить pause-only text refinement;
- ограничить LLM рамками structured critique;
- определить local/hybrid behavior.

Done definition:
- deterministic core работает без LLM;
- при наличии provider pause explanation улучшается, но не ломает contract;
- degradation path предусмотрен.

## Track 9. Evaluation

Задачи:
- собрать curated cinematic eval set;
- ввести quality metrics;
- реализовать report scripts;
- сравнивать baseline и new pipeline.

Done definition:
- есть repeatable eval;
- есть report по issues/actions/explanation faithfulness.

## Track 10. Runtime Feedback

Задачи:
- логировать runtime failures;
- собирать hard examples;
- пополнять backlog для следующих итераций;
- при необходимости экспортировать critique mismatches.

Done definition:
- failures не теряются;
- есть понятный формат записи runtime cases;
- новые hard cases можно быстро добавлять в eval set.

## Deterministic PR Pipeline

Ниже предложен порядок PR, каждый из которых должен быть:
- узким по write scope;
- проверяемым;
- интегрированным в существующую документацию;
- безопасным для реализации отдельным агентом.

### PR-001. Baseline Freeze

Цель:
- зафиксировать стартовое состояние camera coach.

Скоуп:
- только `docs/cameraanalysis/*` и read-only анализ текущего camera-модуля.

Артефакт:
- baseline notes;
- known failure modes;
- baseline state map.

Зависимости:
- нет.

### PR-002. Domain Contracts

Цель:
- создать source-of-truth для новых доменных структур.

Скоуп:
- новые domain model docs;
- при реализации кода только новые model files без UI wiring.

Артефакт:
- spec для `FrameFeatureSnapshot`, `SceneSemanticsReport`, `CritiqueReport`, `RecommendationPlan`.
- зафиксированный source-of-truth doc: [03-domain-contracts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/03-domain-contracts.md).
- реализация доменных типов: `shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift`.
- contract/fixtures tests: `shafinMultitoolTests/CameraAnalysisDomainContractsTests.swift`.

Зависимости:
- `PR-001` желательно, но не строго обязателен.

### PR-003. Explainability Contract

Цель:
- формализовать traceability всех рекомендаций.

Скоуп:
- docs;
- при кодовой реализации только explainability model/types.

Артефакт:
- explainability trace spec;
- examples;
- зафиксированный source-of-truth doc: [04-explainability-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/04-explainability-contract.md).
- test ideas.

Зависимости:
- `PR-002`.

### PR-004. Feature Snapshot Aggregator

Цель:
- собрать единый snapshot из текущих feature providers.

Скоуп:
- `Multitool2Module/Services/Pipeline/*`
- новые domain files под features

Не трогать:
- UI;
- LLM;
- expanded critique text.

Артефакт:
- builder/adapter для `FrameFeatureSnapshot`;
- unit tests.
- зафиксированный source-of-truth doc: [05-feature-snapshot-aggregator.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/05-feature-snapshot-aggregator.md).

Зависимости:
- `PR-002`.

### PR-005. Primary Subject Resolver

Цель:
- выбрать главный субъект кадра.

Скоуп:
- новые semantic analyzer files;
- tests;
- возможно частичное чтение текущих vision outputs.

Артефакт:
- deterministic `PrimarySubjectResolver`.

Зависимости:
- `PR-004`.

### PR-006. Scene Type Classifier

Цель:
- определить cinematic scene type `v1`.

Скоуп:
- новые classifier files;
- tests;
- без UI wiring.

Артефакт:
- `SceneTypeClassifier` с ограниченным `v1` scene catalog.

Зависимости:
- `PR-004`.

### PR-007. Critique Engine

Цель:
- превратить snapshot и semantics в strengths/issues.

Скоуп:
- new critique engine files;
- tests;
- без live UI.

Артефакт:
- `FrameCritiqueEngine`;
- `CritiqueReport`;
- issue taxonomy implementation.

Зависимости:
- `PR-003`, `PR-005`, `PR-006`.

### PR-008. Recommendation Planner

Цель:
- построить действия из critique.

Скоуп:
- planner files;
- tests;
- optional overlay annotation model.

Артефакт:
- `RecommendationPlanner`;
- `RecommendationPlan`.

Зависимости:
- `PR-007`.

### PR-009. Live Hint Adapter

Цель:
- вывести из нового plan-а один стабильный live hint.

Скоуп:
- `CameraViewModel`;
- `AnalysisPipeline`;
- lightweight presentation mapping;
- fallback на legacy suggestion path.

Артефакт:
- новый `LiveHint` flow;
- anti-flicker behavior;
- integration tests или smoke checks.

Зависимости:
- `PR-008`.

### PR-010. Pause Critique Card

Цель:
- показать expanded verdict в pause.

Скоуп:
- pause UI files;
- view model states;
- structured sections.

Артефакт:
- pause card / sheet;
- strengths/issues/actions presentation.

Зависимости:
- `PR-007`, `PR-008`.

### PR-011. Overlay Annotations

Цель:
- связать critique с визуальными подсказками на кадре.

Скоуп:
- overlay view files;
- overlay models;
- no LLM work.

Артефакт:
- arrows/highlight/regions tied to actions and issues.

Зависимости:
- `PR-008`.

### PR-012. Reasoning Provider Abstraction

Цель:
- подготовить систему к deep reasoning без захардкоженного provider-а.

Скоуп:
- protocol/adapter/coordinator files;
- no final heavy prompt tuning yet.

Артефакт:
- `ReasoningProvider`;
- pause coordinator integration points.

Зависимости:
- `PR-007`, `PR-008`.

### PR-013. Pause LLM Explanation

Цель:
- улучшить expanded explanation через controlled LLM layer.

Скоуп:
- provider implementation;
- prompt pack;
- pause-only integration.

Не трогать:
- deterministic core taxonomy;
- baseline issue logic.

Артефакт:
- optional text refinement/arbitration for pause.

Зависимости:
- `PR-012`, `PR-010`.

### PR-014. Eval Harness

Цель:
- сделать качество измеримым.

Скоуп:
- `docs/cameraanalysis/eval/*` или эквивалент;
- test fixtures;
- report script(s).

Артефакт:
- curated cases;
- metric definitions;
- baseline vs current report.

Зависимости:
- `PR-007` минимум, лучше после `PR-010`.

### PR-015. Runtime Feedback Loop Foundation

Цель:
- начать собирать реальные hard cases из использования.

Скоуп:
- logging/telemetry contracts;
- runtime failure record format;
- docs and collection hooks.

Артефакт:
- runtime feedback schema;
- minimal logging integration.

Зависимости:
- `PR-014` желательно, но можно запускать параллельно.

## Рекомендуемый порядок запуска AI-агентов

1. `PR-002`
2. `PR-003`
3. `PR-004`
4. `PR-005`
5. `PR-006`
6. `PR-007`
7. `PR-008`
8. `PR-010`
9. `PR-009`
10. `PR-011`
11. `PR-012`
12. `PR-013`
13. `PR-014`
14. `PR-015`

## Что можно запускать параллельно

- `PR-002` и `PR-003`
- `PR-005` и `PR-006`
- `PR-010` и `PR-011`
- `PR-014` и `PR-015`

## Что нельзя распараллеливать

- `PR-007` и `PR-008`, если они меняют один и тот же critique contract;
- `PR-009`, `PR-010`, `PR-011`, если у них общий write scope на одни и те же UI state files;
- `PR-012` и `PR-013`, если protocol и implementation проектируются одновременно без frozen abstraction.
