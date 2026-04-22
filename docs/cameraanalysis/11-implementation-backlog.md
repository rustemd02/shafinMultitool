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
- deterministic `VisualDominanceAnalyzer`.
- deterministic `SemanticReadabilityAnalyzer`.
- зафиксированный source-of-truth doc: [06-scene-semantics-layer.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/06-scene-semantics-layer.md).

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
- сборка итогового `SceneSemanticsReport` (`SceneSemanticsAnalyzer` facade).
- зафиксированный source-of-truth doc: [06-scene-semantics-layer.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/06-scene-semantics-layer.md).

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
- зафиксированный source-of-truth doc: [07-critique-engine.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/07-critique-engine.md).

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
- зафиксированный source-of-truth doc: [08-ui-integration.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/08-ui-integration.md).

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
- зафиксированный source-of-truth doc: [08-ui-integration.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/08-ui-integration.md).

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
- зафиксированный source-of-truth doc: [08-ui-integration.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/08-ui-integration.md).

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
- зафиксированный source-of-truth doc: [09-reasoning-provider.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/09-reasoning-provider.md).

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
- зафиксированный source-of-truth doc: [09-reasoning-provider.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/09-reasoning-provider.md).

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

## Hybrid Tracks

## Track 11. Hybrid Thesis and Scope Freeze

Задачи:
- зафиксировать research framing hybrid stage;
- разделить deterministic и neural responsibilities;
- определить target hypotheses и risks.

Done definition:
- есть explicit hybrid thesis;
- boundaries rules vs neural зафиксированы;
- есть список проверяемых гипотез.

## Track 12. Evidence Taxonomy and Rubric

Задачи:
- определить evidence heads;
- определить scoring axes;
- определить rubric-driven labeling basis;
- связать axes с issues/actions.

Done definition:
- taxonomy пригодна для data labeling, runtime outputs и eval;
- evidence heads интерпретируемы;
- mapping к issues/actions зафиксирован.

## Track 13. Dataset and Labeling Protocol

Задачи:
- определить dataset schema;
- определить annotator guide;
- определить disagreement/adjudication rules;
- определить minimal starter set and hard-case policy.

Done definition:
- по документу можно начинать разметку без домысливания;
- есть example records;
- есть QA rules для labels.

## Track 14. Neural Model Design

Задачи:
- определить compact mobile-capable backbone;
- определить input/output policy;
- определить AVA usage policy;
- определить losses and deployment constraints.

Done definition:
- архитектура модели пригодна для Core ML;
- outputs ограничены structured evidence;
- роль `AVA` ограничена и не вводит в заблуждение.

## Track 15. On-Device Hybrid Runtime

Задачи:
- подключить inference wrapper;
- сначала ввести pause-only neural evidence path;
- затем fusion and reranking;
- затем optional live gating.

Done definition:
- neural path отключаем и безопасен;
- pause hybrid path работает без мутации core contracts;
- live gating контролируется cadence/thermal policy.

## Track 16. Gated Offloading

Задачи:
- определить remote critic contract;
- определить trigger rules;
- определить payload schema;
- определить privacy/fallback policy.

Done definition:
- offloading не ломает offline-first mode;
- remote critic bounded and optional;
- payload и failure policy формализованы.

## Track 17. Hybrid Evaluation and Demo

Задачи:
- расширить eval для hybrid stage;
- собрать ablations;
- логировать hybrid runtime disagreements;
- подготовить defense demo.

Done definition:
- есть hybrid vs deterministic comparison;
- есть thesis-ready report;
- есть demo scenarios и explainable before/after cases.

## Hybrid PR Pipeline

### PR-H01. Thesis and Hybrid Scope Freeze

Цель:
- зафиксировать hybrid research framing.

Скоуп:
- только `docs/cameraanalysis/*`

Артефакт:
- thesis note
- layer boundary note
- hypothesis list
- зафиксированный source-of-truth doc: [14-hybrid-research-framing.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/14-hybrid-research-framing.md)

Зависимости:
- completed deterministic `v1` doc package

### PR-H02. Evidence Taxonomy Contract

Цель:
- зафиксировать neural evidence heads и scoring axes.

Скоуп:
- docs

Артефакт:
- evidence taxonomy
- mapping to issue/action taxonomy
- confidence semantics
- зафиксированный source-of-truth doc: [15-evidence-taxonomy-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/15-evidence-taxonomy-contract.md)

Зависимости:
- `PR-H01`

### PR-H03. Dataset Schema and Labeling Guide

Цель:
- подготовить data foundation для hybrid stage.

Скоуп:
- docs
- optional eval schema artifacts

Артефакт:
- dataset schema
- labeling guide
- adjudication rules

Зависимости:
- `PR-H02`

### PR-H04. AVA Usage Policy and Pretraining Design

Цель:
- формально определить безопасную роль `AVA`.

Скоуп:
- docs only

Артефакт:
- AVA policy
- pretraining strategy
- risk register

Зависимости:
- `PR-H03`

### PR-H05. Hybrid Model Architecture Spec

Цель:
- определить compact mobile model и outputs.

Скоуп:
- docs
- optional interface stubs

Артефакт:
- backbone choice
- output heads
- latency/size assumptions
- loss design

Зависимости:
- `PR-H02`, `PR-H04`

### PR-H06. Neural Evidence Domain Contract

Цель:
- ввести runtime contract для neural outputs.

Скоуп:
- `Models/CameraAnalysis/*`
- tests
- docs

Артефакт:
- `NeuralEvidenceSnapshot`
- invariants
- serialization/tests

Зависимости:
- `PR-H05`

### PR-H07. On-Device Inference Wrapper

Цель:
- подключить on-device neural evidence provider без fusion logic.

Скоуп:
- inference service files
- pipeline hooks
- tests

Артефакт:
- wrapper
- mock path
- cadence policy

Зависимости:
- `PR-H06`

### PR-H08. Pause-Only Neural Evidence Path

Цель:
- сначала безопасно ввести neural evidence в `pause`.

Скоуп:
- `AnalysisPipeline`
- tests

Артефакт:
- pause-local neural evidence path
- merged hybrid snapshot
- fallback behavior

Зависимости:
- `PR-H07`

### PR-H09. Hybrid Fusion Layer

Цель:
- слить deterministic critique core и neural evidence.

Скоуп:
- fusion service
- critique/ranking adaptation
- tests

Артефакт:
- fusion policy
- weighting rules
- calibration policy

Зависимости:
- `PR-H08`

### PR-H10. Neural Reranker

Цель:
- улучшить приоритетность рекомендаций.

Скоуп:
- planner integration
- tests

Артефакт:
- reranking policy
- reprioritization logic

Зависимости:
- `PR-H09`

### PR-H11. Live Neural Gating

Цель:
- аккуратно использовать neural evidence в `live`.

Скоуп:
- `AnalysisPipeline`
- `CameraViewModel`
- optional UI state hooks

Артефакт:
- low-frequency live neural path
- thermal/latency guardrails

Зависимости:
- `PR-H09`

### PR-H12. Offloading Contract

Цель:
- описать optional deep critic path.

Скоуп:
- docs
- provider abstraction
- payload types

Артефакт:
- `DeepCriticProvider`
- payload schema
- gate policy

Зависимости:
- `PR-H09`

### PR-H13. Server / Teacher Critic Prototype

Цель:
- получить richer deep-analysis path.

Скоуп:
- optional server-facing abstraction or mock

Артефакт:
- teacher/richer critic prototype
- degradation policy

Зависимости:
- `PR-H12`

### PR-H14. Hybrid Eval Harness

Цель:
- мерить hybrid stage отдельно от deterministic baseline.

Скоуп:
- `docs/cameraanalysis/eval/*`
- reports

Артефакт:
- hybrid metrics
- ablations
- comparison reports

Зависимости:
- `PR-H09`

### PR-H15. Hybrid Runtime Telemetry

Цель:
- собирать hard cases и hybrid disagreements.

Скоуп:
- telemetry/logging schema
- optional export hooks

Артефакт:
- runtime logging format
- disagreement logging

Зависимости:
- `PR-H11`, `PR-H14`

### PR-H16. Thesis Demo Bundle

Цель:
- подготовить защиту и demo narrative.

Скоуп:
- docs
- demo assets or scripts

Артефакт:
- before/after cases
- ablation summary
- committee-ready demo script

Зависимости:
- `PR-H14`, `PR-H15`

## Hybrid Detailed DoD

### Global hybrid DoD

Работа считается завершенной только если:
- deterministic и neural responsibilities явно разделены;
- offline-first path не ломается;
- outputs нейросети интерпретируемы;
- есть eval-ready metrics and fixtures;
- вклад PR можно объяснить комиссии за 30-60 секунд.

### Data / rubric DoD

- dataset schema формализована;
- labels совместимы с issue/action taxonomy;
- AVA policy не маскирует domain gap;
- есть adjudication rules and quality checks.

### Model design DoD

- backbone mobile-capable;
- outputs are structured evidence only;
- есть latency/size target;
- есть deployment assumptions for Core ML.

### Runtime DoD

- neural path можно отключить без поломки UX;
- pause hybrid path не мутирует unexpectedly shared core state;
- live neural path throttled and guarded;
- fallback logic явно задана.

### Fusion DoD

- fusion policy explainable;
- neural layer не становится black-box source-of-truth;
- есть tests на conflict, low-confidence и degraded cases.

### Offloading DoD

- offloading optional;
- payload schema и privacy boundaries заданы;
- remote unavailability не ломает base experience.

### Eval / thesis DoD

- есть comparison `deterministic only` vs `hybrid`;
- есть system metrics for mobile;
- есть ablation story;
- есть demo-ready before/after explanation.
