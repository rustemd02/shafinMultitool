# 12. Agent Prompts

Этот файл содержит готовые промпты для AI-агентов по `Camera Analysis v1`.

## Важно

Для задач реализации агентам почти всегда нужно дополнительно дать:
- конкретную цель;
- границы ответственности;
- входные файлы;
- ожидаемый артефакт;
- критерий готовности;
- номер PR из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/11-implementation-backlog.md).

## Общий режим работы

Для всех промптов ниже агент должен работать в одном из 4 режимов:
- `design`
- `design verify`
- `implement`
- `implement verify`

В начало конкретного промпта добавляй:
- `Режим: design`
- `Режим: design verify`
- `Режим: implement`
- `Режим: implement verify`

## Рекомендуемый порядок запуска

Для contract-sensitive задач использовать:
- `design -> design verify -> implement -> implement verify`

Это обязательно рекомендуется для:
- domain contracts
- explainability contract
- critique engine
- recommendation planner
- reasoning provider
- eval harness

Для локальных и низкорисковых задач допустим цикл:
- `design -> implement -> implement verify`

Это обычно подходит для:
- локальных UI задач
- overlay tasks
- baseline docs
- runtime logging scaffolding

## Prompt 1. Domain Contract Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/cameraanalysis/README.md
- docs/cameraanalysis/00-overview.md
- docs/cameraanalysis/01-roadmap.md
- docs/cameraanalysis/11-implementation-backlog.md
- docs/cameraanalysis/13-agent-briefing-template.md

Контекст:
Прочитай:
- docs/cameraanalysis/camera-analysis-requirements-draft.md
- docs/cameraanalysis/camera-analysis-v1-architecture.md
- docs/cameraanalysis/02-pipeline-architecture.md

Дополнительно изучи текущий код:
- shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift
- shafinMultitool/Multitool2Module/Services/Suggestion/SuggestionEngine.swift

Задача:
Спроектируй и/или реализуй source-of-truth контракты для нового explainable camera pipeline.

Что нужно сделать:
- описать или реализовать `FrameFeatureSnapshot`
- описать или реализовать `SceneSemanticsReport`
- описать или реализовать `CritiqueReport`
- описать или реализовать `RecommendationPlan`
- перечислить invariants и примеры

Ограничения:
- не ломать текущий UI
- не внедрять LLM logic
- не придумывать слишком широкий scene catalog

Ожидаемый результат:
- design doc или code patch для domain contracts
- examples
- test plan
- обновление index/backlog docs при появлении новых артефактов

Definition of done:
- `design`: по контракту можно писать critique core без домысливания
- `design verify`: перечислены пробелы, противоречия и готовность к реализации
- `implement`: введены типы/модели/fixtures/tests без UI wiring
- `implement verify`: проверено, что реализация соответствует design docs и не конфликтует с current pipeline
```

## Prompt 2. Explainability Contract Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/cameraanalysis/README.md
- docs/cameraanalysis/11-implementation-backlog.md
- docs/cameraanalysis/13-agent-briefing-template.md

Контекст:
Прочитай:
- docs/cameraanalysis/camera-analysis-requirements-draft.md
- docs/cameraanalysis/camera-analysis-v1-architecture.md

Задача:
Спроектируй explainability contract для camera analysis v1.

Что нужно сделать:
- определить структуру `ExplainabilityTraceItem`
- зафиксировать цепочку `observation -> interpretation -> recommendation`
- дать 5-8 примеров trace для плохих и хороших кадров
- предложить, как trace использовать в debug/eval/UI

Ограничения:
- trace должен быть пригоден и для deterministic core, и для optional LLM layer
- trace не должен зависеть от конкретной модели или endpoint

Ожидаемый результат:
- markdown design doc
- trace examples
- invariants
- интеграция результата в index documents пакета

Definition of done:
- `design`: critique engine и planner могут ссылаться на trace как на source-of-truth
- `implement`: если вводятся типы, они пригодны для serialization/tests/debug
```

## Prompt 3. Feature Snapshot Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/cameraanalysis/README.md
- docs/cameraanalysis/11-implementation-backlog.md
- docs/cameraanalysis/13-agent-briefing-template.md

Контекст:
Прочитай:
- docs/cameraanalysis/02-pipeline-architecture.md
- docs/cameraanalysis/camera-analysis-v1-architecture.md

Дополнительно изучи текущий код:
- shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift
- shafinMultitool/Multitool2Module/Models/Vision/VisionTracking.swift
- shafinMultitool/Multitool2Module/Models/Vision/HorizonEstimator.swift
- shafinMultitool/Multitool2Module/Models/Lighting/LightingEstimator.swift
- shafinMultitool/Multitool2Module/Models/CoreMLWrappers/AestheticScorer.swift

Задача:
Реализуй `Feature Snapshot Aggregator` для нового explainable pipeline.

Что нужно сделать:
- собрать текущие fast signals в единый snapshot
- определить defaults и confidence behavior
- минимизировать дублирование текущей логики
- покрыть поведение unit tests

Ограничения:
- не внедрять новый UI
- не менять scene semantics
- не добавлять LLM code

Ожидаемый результат:
- code patch
- tests
- короткий note по integration points

Definition of done:
- одинаковые входные сигналы дают детерминированный snapshot
- aggregator можно использовать как вход для subject resolver и critique engine
```

## Prompt 4. Scene Semantics Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/cameraanalysis/README.md
- docs/cameraanalysis/11-implementation-backlog.md
- docs/cameraanalysis/13-agent-briefing-template.md

Контекст:
Прочитай:
- docs/cameraanalysis/02-pipeline-architecture.md
- docs/cameraanalysis/camera-analysis-v1-architecture.md

Дополнительно изучи текущий код:
- существующие vision/object detection outputs в `Multitool2Module`

Задача:
Спроектируй и/или реализуй scene semantics слой `v1`.

Что нужно сделать:
- реализовать `PrimarySubjectResolver`
- реализовать `SceneTypeClassifier`
- предложить confidence rules
- покрыть golden cases тестами

Ограничения:
- ограниченный cinematic scene catalog
- deterministic behavior first
- без UI wiring

Ожидаемый результат:
- design doc или code patch
- tests
- список supported scene types

Definition of done:
- semantics layer стабильно выдает `SceneSemanticsReport`
- ошибки и fallback rules документированы
```

## Prompt 5. Critique Engine Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/cameraanalysis/README.md
- docs/cameraanalysis/11-implementation-backlog.md
- docs/cameraanalysis/13-agent-briefing-template.md

Контекст:
Прочитай:
- docs/cameraanalysis/camera-analysis-v1-architecture.md
- docs/cameraanalysis/02-pipeline-architecture.md
- docs/cameraanalysis/05-feature-snapshot-aggregator.md
- docs/cameraanalysis/03-domain-contracts.md
- docs/cameraanalysis/04-explainability-contract.md
- docs/cameraanalysis/06-scene-semantics-layer.md
- docs/cameraanalysis/07-critique-engine.md

PR-контекст (обязательно):
- PR: `PR-007. Critique Engine`
- зависимости: `PR-003`, `PR-005`, `PR-006`
- source-of-truth для `PR-007`: `docs/cameraanalysis/07-critique-engine.md`
- если есть конфликт трактовок, приоритет по зонам ответственности:
  - critique rules, thresholds, degraded policy, test matrix: `07-critique-engine.md`
  - domain поля и типы `CritiqueReport/FrameIssue/FrameStrength/FixTypeV1`: `03-domain-contracts.md`
  - trace/link semantics (`TraceLink.refId`, stage/source invariants): `04-explainability-contract.md`
  - semantics assumptions и upstream fallback behavior: `06-scene-semantics-layer.md`

Дополнительно изучи текущий код:
- shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift
- shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift
- shafinMultitool/Multitool2Module/Services/Suggestion/SuggestionEngine.swift

Задача:
Спроектируй и/или реализуй deterministic `FrameCritiqueEngine`.

Что нужно сделать:
- определить issue detection rules
- определить strength detection rules
- ввести severity/confidence
- зафиксировать verdict aggregation (`good/mixed/needs_fix`) и `verdictConfidence`
- зафиксировать summary templates (`shortVerdict`, `whyGood`, `whyProblematic`)
- зафиксировать `affectedRegion`, `suggestedFixTypes`, `fallbackUsed/degraded mode`
- зафиксировать deterministic sorting/id policy (`issues`, `strengths`, trace seeds)
- зафиксировать deterministic catalog:
  - `rationaleTemplateKey` для каждого issue/strength
  - обязательные `evidence keys` для каждого issue/strength
- связать findings с explainability trace:
  - обязательно:
    - для каждого существующего `issue` должен быть trace-link `issue`
    - для каждого существующего `strength` должен быть trace-link `strength`
    - `summary` trace-link обязателен всегда
  - совместимость с downstream links: `action`/`summary` и `refId` resolution rules
- зафиксировать degraded mode contract:
  - trigger rules
  - allowed issue subset
  - non-good verdict floor
  - confidence cap
- покрыть tests:
  - logic golden tests
  - contract tests
  - determinism tests
  - calibration tests (включая ambiguity boost behavior)

Ограничения:
- LLM не источник истины для issues
- issue taxonomy должна оставаться ограниченной и объяснимой
- не выходить за текущие contracts `IssueTypeV1`, `StrengthTypeV1`, `FixTypeV1`
- без UI wiring

Ожидаемый результат:
- design doc или code patch
- test suite
- invariants and edge cases
- explicit mapping `rule -> rationaleTemplateKey -> required evidence keys`

Write scope (для implement):
- `shafinMultitool/Multitool2Module/Services/Critique/*` (или эквивалентный новый critique-модуль)
- `shafinMultitool/Multitool2Module/Models/CameraAnalysis/*` только при contract-safe изменениях
- `shafinMultitoolTests/*Critique*` и/или `shafinMultitoolTests/CameraAnalysis*`
- без правок UI слоев

Definition of done:
- `design`: спецификация implement-ready для `PR-007` с явными rules, thresholds, fallback, trace-seeds и тест-матрицей
- `design verify`: проверены противоречия с `03/04/05/06/07`, перечислены residual risks и readiness verdict
- `implement`: для golden cases engine выдает воспроизводимый `CritiqueReport` c валидными `affectedRegion/suggestedFixTypes/fallbackUsed`
- `implement`: verdict aggregation и summary templates детерминированы и соответствуют source-of-truth
- `implement`: deterministic id/sort и trace-seeds соблюдаются, `refId`-линки валидны
- `implement verify`: все issues и strengths имеют traceable rationale, summary trace присутствует, и контракты не конфликтуют с planner/explainability слоями
- `implement verify`: degraded mode trigger/restrictions валидированы, а contract/determinism/calibration tests покрывают invariants и edge cases
```

## Prompt 6. UI Integration Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/cameraanalysis/README.md
- docs/cameraanalysis/11-implementation-backlog.md
- docs/cameraanalysis/13-agent-briefing-template.md

Контекст:
Прочитай:
- docs/cameraanalysis/camera-analysis-requirements-draft.md
- docs/cameraanalysis/camera-analysis-v1-architecture.md

Дополнительно изучи текущий код:
- shafinMultitool/Multitool2Module/ViewModels/CameraViewModel.swift
- shafinMultitool/Multitool2Module/UI/Overlay/OverlayView.swift
- связанные overlay/pause UI файлы

Задача:
Встроить новый critique contract в live и pause UI без слома текущего camera flow.

Что нужно сделать:
- подключить новый live hint
- добавить expanded pause critique card
- встроить overlay annotations
- сохранить fallback path на legacy suggestions

Ограничения:
- не перепроектировать core contracts
- не ломать capture flow
- минимизировать write scope за пределами camera UI module

Ожидаемый результат:
- code patch
- verification steps
- UI state notes

Definition of done:
- live и pause используют новый pipeline
- fallback path остается рабочим
- UI не мерцает и не перегружает экран
```

## Prompt 7. Reasoning / LLM Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/cameraanalysis/README.md
- docs/cameraanalysis/11-implementation-backlog.md
- docs/cameraanalysis/13-agent-briefing-template.md

Контекст:
Прочитай:
- docs/cameraanalysis/camera-analysis-v1-architecture.md
- docs/cameraanalysis/02-pipeline-architecture.md
- docs/cameraanalysis/09-reasoning-provider.md

Дополнительно изучи:
- critique and recommendation contracts
- pause UI contract

PR-контекст (обязательно):
- PR: `PR-012/PR-013`
- source-of-truth для reasoning boundary: `docs/cameraanalysis/09-reasoning-provider.md`
- обязательные policy points:
  - `ReasoningProvider` только для `pause` (live-path без provider)
  - optional reasoning trace append-only и без `action` links
  - сбой provider не равен hard legacy fallback (работает deterministic baseline)

Задача:
Спроектируй и/или реализуй `ReasoningProvider` и pause-only LLM explanation layer.

Что нужно сделать:
- определить provider abstraction
- определить input/output contract для LLM
- сохранить explainability и deterministic fallback
- ограничить LLM usage pause-режимом

Ограничения:
- не отдавать модели роль source-of-truth для raw issues
- должен существовать graceful degradation path

Ожидаемый результат:
- design doc или code patch
- prompt/interface sketch
- failure handling rules

Definition of done:
- без provider система работает как раньше
- с provider расширенный pause text улучшается, но не ломает core contract
```

## Prompt 8. Eval Agent

```text
Обязательный префикс:
Прочитай как базовый контекст:
- docs/cameraanalysis/README.md
- docs/cameraanalysis/11-implementation-backlog.md
- docs/cameraanalysis/13-agent-briefing-template.md

Контекст:
Прочитай:
- docs/cameraanalysis/00-overview.md
- docs/cameraanalysis/camera-analysis-requirements-draft.md
- docs/cameraanalysis/camera-analysis-v1-architecture.md

Задача:
Спроектируй и/или реализуй eval harness для camera analysis v1.

Что нужно сделать:
- определить quality metrics
- предложить format golden cases
- собрать baseline vs current comparison format
- предложить curated cinematic eval buckets

Ограничения:
- metrics должны измерять и detection, и explanation usefulness
- evaluation не должна зависеть только от субъективного human prose review

Ожидаемый результат:
- design doc или scripts/fixtures
- metric definitions
- example report

Definition of done:
- можно воспроизводимо прогнать eval
- есть понятный report по strengths/issues/actions/explanation faithfulness
```

## Hybrid Stage Prompts

Этот раздел нужен для следующего этапа: `deterministic + neural evidence + optional gated offloading`.

Главный принцип для всех hybrid prompts:
- не проектировать black-box judge;
- не просить модель напрямую генерировать source-of-truth critique;
- использовать нейросеть для structured evidence, scoring и reranking.

## Prompt 9. Hybrid Research Framing Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/README.md
- docs/cameraanalysis/02-pipeline-architecture.md
- docs/cameraanalysis/01-roadmap.md
- docs/cameraanalysis/11-implementation-backlog.md
- docs/cameraanalysis/13-agent-briefing-template.md

PR-контекст:
- PR: `PR-H01`
- название: `Thesis and Hybrid Scope Freeze`

Задача:
Сформулируй research framing hybrid stage.

Что нужно сделать:
- зафиксировать hybrid thesis
- разделить responsibilities deterministic vs neural
- перечислить 4-6 проверяемых hypotheses
- перечислить 5-8 главных risks
- связать это с mobile-first и explainability

Ограничения:
- не предлагать end-to-end black-box judge как целевую архитектуру

Ожидаемый результат:
- design doc
- thesis-ready summary
- explicit scope boundaries

Definition of done:
- по документу понятно, зачем нужен hybrid stage и что именно будет проверяться
```

## Prompt 10. Evidence Taxonomy Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/03-domain-contracts.md
- docs/cameraanalysis/07-critique-engine.md
- docs/cameraanalysis/02-pipeline-architecture.md
- docs/cameraanalysis/11-implementation-backlog.md

PR-контекст:
- PR: `PR-H02`
- название: `Evidence Taxonomy Contract`

Задача:
Спроектируй evidence taxonomy для hybrid stage.

Что нужно сделать:
- перечислить evidence heads
- определить scoring axes
- связать evidence с issue/action taxonomy
- определить confidence semantics
- разделить heads для `live` и `pause`

Ограничения:
- evidence heads должны быть интерпретируемыми
- не подменять evidence свободным текстом

Ожидаемый результат:
- markdown contract
- mapping examples
- invariants

Definition of done:
- taxonomy можно использовать для dataset schema, runtime contract и fusion layer
```

## Prompt 11. Dataset and Labeling Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/02-pipeline-architecture.md
- docs/cameraanalysis/01-roadmap.md
- docs/cameraanalysis/11-implementation-backlog.md
- docs/cameraanalysis/10-eval-harness.md

PR-контекст:
- PR: `PR-H03`
- название: `Dataset Schema and Labeling Guide`

Задача:
Спроектируй dataset schema и labeling protocol для hybrid camera analysis.

Что нужно сделать:
- описать dataset entity schema
- описать source buckets: public / curated / runtime hard cases
- определить annotator guide
- определить disagreement resolution
- предложить minimal starter dataset

Ограничения:
- учитывать cinematic framing и shot intent
- labels должны быть совместимы с explainable critique system

Ожидаемый результат:
- schema doc
- labeling guide
- example records
- QA checklist

Definition of done:
- другой человек может начать разметку без домысливания
```

## Prompt 12. AVA Policy Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/02-pipeline-architecture.md
- docs/cameraanalysis/11-implementation-backlog.md

PR-контекст:
- PR: `PR-H04`
- название: `AVA Usage Policy and Pretraining Design`

Задача:
Определи безопасную и научно честную роль `AVA`.

Что нужно сделать:
- описать где AVA полезен
- описать где AVA вреден
- предложить pretraining strategy
- предложить domain adaptation strategy
- перечислить safeguards against misuse

Ограничения:
- не использовать AVA как финальную истину о cinematic quality

Ожидаемый результат:
- policy doc
- pretraining note
- risk list

Definition of done:
- по документу понятно, как использовать AVA без архитектурной ошибки
```

## Prompt 13. Hybrid Model Architecture Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/02-pipeline-architecture.md
- docs/cameraanalysis/01-roadmap.md
- docs/cameraanalysis/11-implementation-backlog.md

PR-контекст:
- PR: `PR-H05`
- название: `Hybrid Model Architecture Spec`

Задача:
Спроектируй compact neural evidence model для iPhone.

Что нужно сделать:
- выбрать realistic backbone
- определить input strategy
- определить output heads
- определить training objectives
- определить latency/size targets
- определить Core ML assumptions

Ограничения:
- mobile-first
- no giant multimodal model
- outputs are structured evidence only

Ожидаемый результат:
- architecture spec
- deployment assumptions
- ablation plan

Definition of done:
- можно переходить к runtime contract и inference wrapper без домысливания
```

## Prompt 14. Neural Evidence Contract Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/03-domain-contracts.md
- docs/cameraanalysis/02-pipeline-architecture.md
- docs/cameraanalysis/11-implementation-backlog.md

PR-контекст:
- PR: `PR-H06`
- название: `Neural Evidence Domain Contract`

Задача:
Спроектируй и/или реализуй runtime contract для neural evidence outputs.

Что нужно сделать:
- описать или реализовать `NeuralEvidenceSnapshot`
- задать fields, ranges и confidence semantics
- зафиксировать serialization requirements
- покрыть invariants tests

Ограничения:
- контракт не должен зависеть от конкретного backbone
- контракт должен быть пригоден и для on-device, и для offloaded critic

Ожидаемый результат:
- markdown contract и/или code patch
- examples
- tests

Definition of done:
- contract пригоден для fusion and eval without guesswork
```

## Prompt 15. On-Device Inference Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/02-pipeline-architecture.md
- docs/cameraanalysis/11-implementation-backlog.md
- docs/cameraanalysis/13-agent-briefing-template.md
- relevant pipeline files

PR-контекст:
- PR: `PR-H07`
- название: `On-Device Inference Wrapper`

Задача:
Реализуй on-device neural evidence path без fusion logic.

Что нужно сделать:
- подключить mockable inference provider
- реализовать cadence policy для `live` и `pause`
- описать fallback behavior
- покрыть wrapper tests

Ограничения:
- не менять final critique logic
- не внедрять server path
- не делать neural layer обязательной для base UX

Ожидаемый результат:
- code patch
- tests
- integration note

Definition of done:
- runtime может получать neural evidence безопасно и отключаемо
```

## Prompt 16. Hybrid Fusion Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/07-critique-engine.md
- docs/cameraanalysis/02-pipeline-architecture.md
- docs/cameraanalysis/11-implementation-backlog.md
- relevant model and pipeline files

PR-контекст:
- PR: `PR-H09`
- название: `Hybrid Fusion Layer`

Задача:
Спроектируй и/или реализуй explainable fusion between deterministic critique core and neural evidence.

Что нужно сделать:
- определить weighting policy
- определить when neural evidence changes confidence/ranking
- сохранить explainability trace
- покрыть golden и degraded cases

Ограничения:
- preserve deterministic fallback
- не превращать fusion в black box

Ожидаемый результат:
- fusion design or code patch
- tests
- before/after examples

Definition of done:
- влияние neural evidence можно объяснить и повторить на тестах
```

## Prompt 17. Offloading Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/02-pipeline-architecture.md
- docs/cameraanalysis/11-implementation-backlog.md
- docs/cameraanalysis/13-agent-briefing-template.md

PR-контекст:
- PR: `PR-H12`
- название: `Offloading Contract`

Задача:
Спроектируй gated offloading для deep critique path.

Что нужно сделать:
- определить trigger policy
- определить payload schema
- определить privacy boundaries
- определить role of remote critic
- определить fallback path

Ограничения:
- offline-first behavior обязателен
- server не source-of-truth для base UX

Ожидаемый результат:
- contract doc
- payload examples
- safety/fallback section

Definition of done:
- offloading можно внедрять без риска для baseline UX
```

## Prompt 18. Hybrid Eval Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/10-eval-harness.md
- docs/cameraanalysis/02-pipeline-architecture.md
- docs/cameraanalysis/11-implementation-backlog.md

PR-контекст:
- PR: `PR-H14`
- название: `Hybrid Eval Harness`

Задача:
Расширь eval pipeline для hybrid stage.

Что нужно сделать:
- ввести hybrid metrics
- ввести ablation comparisons
- ввести explainability agreement metrics
- описать mobile system metrics
- подготовить report template

Ограничения:
- не сводить успех системы к одному aesthetic score

Ожидаемый результат:
- eval design or code patch
- metric definitions
- report examples

Definition of done:
- можно сравнить deterministic-only и hybrid repeatable способом
```

## Semantic Screen Tips Stage Prompts

Этот раздел ведет систему к исходной продуктовой цели:

`человек ставит кадр -> приложение понимает контекст -> на экране появляются конкретные семантические подсказки, как сделать картинку красивее`.

Примеры целевого результата:
- `Добавь слабый фоновый свет справа: волосы сливаются с темным фоном.`
- `Сдвинь камеру чуть правее: герою не хватает пространства взгляда.`
- `Отойди на полшага назад: лицо зажато краями кадра.`
- `Убери яркое пятно за головой: фон спорит с главным объектом.`
- `Кадр уже читается хорошо: лицо отделено от фона, свет мягкий.`

Главное правило для всех prompts ниже:
- VLM помогает увидеть семантические причины;
- deterministic pipeline остается source-of-truth для финального issue/action contract;
- UI показывает короткие actionable tips, а не свободный длинный ответ модели;
- live остается быстрым, pause получает глубокий разбор.

## Prompt 19. Semantic Tip Taxonomy Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/README.md
- docs/cameraanalysis/03-domain-contracts.md
- docs/cameraanalysis/04-explainability-contract.md
- docs/cameraanalysis/07-critique-engine.md
- docs/cameraanalysis/08-ui-integration.md
- docs/cameraanalysis/15-evidence-taxonomy-contract.md
- docs/cameraanalysis/19-neural-evidence-domain-contract.md
- docs/cameraanalysis/21-hybrid-fusion-layer.md
- docs/cameraanalysis/13-agent-briefing-template.md

PR-контекст:
- PR: `PR-S01`
- название: `Semantic Tip Taxonomy and Action Catalog`
- режим рекомендуется: `design -> design verify -> implement`

Задача:
Спроектируй и/или реализуй закрытый каталог семантических подсказок, который связывает визуальные причины кадра с конкретными действиями пользователя.

Главная продуктовая цель:
- пользователь видит не абстрактную оценку, а конкретное экранное действие:
  - `смести камеру чуть правее`
  - `добавь слабый фоновый свет`
  - `опусти камеру ниже`
  - `отодвинь героя от фона`
  - `сдвинь предмет правее`
  - `убери объект, который спорит с лицом`
  - `оставь кадр как есть`

Что нужно сделать:
- определить `SemanticTipType` / `SemanticActionType`;
- определить `VisualProblemType` и `VisualStrengthType` для screen tips;
- определить entity-aware слой для подсказок:
  - `targetEntityKind`
  - `targetEntityRole`
  - `targetEntityRef`
  - `targetEntityDisplayLabel`
  - optional `secondaryEntityRef`
  - optional `secondaryEntityDisplayLabel`
  - `actionFrame` (`move_camera | move_subject | move_object | adjust_light | wait`)
  - optional `direction`
- связать tip taxonomy с существующими `IssueTypeV1`, `StrengthTypeV1`, `FixTypeV1`;
- зафиксировать формат короткого live-текста и расширенного pause-текста;
- определить приоритеты tips: что показывать первым, что скрывать, что объединять;
- явно покрыть не только свет и framing, но и:
  - композицию;
  - перспективу и высоту камеры;
  - глубину кадра и separation;
  - конфликтующие объекты/предметы в фоне и переднем плане;
  - repositioning субъекта;
  - repositioning props/objects inside the frame;
  - timing / wait cues для очистки кадра;
- добавить примеры для портрета, диалога, предмета, темного фона, пересвеченного фона, плохого separation, tight framing, clutter, flat image, object merge, distracting prop, cleaner angle, camera height mismatch;
- описать positive tips: когда система говорит, что кадр уже хорош.

Минимальные action families, которые каталог обязан рассмотреть:
- camera reframing:
  - `shift_frame_left/right/up/down`
  - `step_back`
  - `step_closer`
  - `lower_camera`
  - `raise_camera`
  - `change_camera_angle`
  - `level_horizon`
- subject staging:
  - `rotate_subject_toward_light`
  - `move_subject_left/right`
  - `move_subject_away_from_background`
  - `turn_subject_for_cleaner_profile`
- object / prop staging:
  - `move_object_left/right`
  - `move_object_forward/back`
  - `remove_distracting_object`
  - `reposition_prop_for_balance`
- lighting:
  - `add_front_fill_light`
  - `add_background_light`
  - `add_rim_light`
  - `add_side_light`
  - `remove_background_hotspot`
- timing / scene cleanup:
  - `simplify_background`
  - `wait_for_background_clearance`
  - `keep_current_setup`

Если часть action families окажется слишком широкой для `v1`, агент обязан:
- явно перечислить, что входит в `v1`;
- явно перечислить, что откладывается;
- объяснить, почему это не ломает исходную цель screen tips.

Ограничения:
- не добавлять свободный произвольный текст как source-of-truth;
- не раздувать taxonomy до сотен случаев, но и не оставлять ее слишком бедной для реальных cinematic prompts;
- подсказка должна быть actionable: пользователь должен понять, что физически сделать;
- каждая подсказка должна иметь explainability chain `observation -> interpretation -> recommendation`;
- каталог должен уметь давать советы не только про камеру, но и про:
  - свет;
  - положение субъекта;
  - положение предметов/объектов;
  - очистку кадра;
  - глубину/слойность;
- display label не должен быть свободной галлюцинацией:
  - high-confidence person -> `герой | человек | лицо | персонаж`
  - high-confidence object -> конкретное имя объекта, только если оно подтверждено detector/VLM/entity layer
  - medium/low-confidence object -> `предмет`, `объект справа`, `яркий объект на фоне`
- агент обязан зафиксировать policy, когда tip говорит `смести камеру`, а когда `сдвинь героя` или `сдвинь предмет`;
- не трогать VLM provider и UI wiring в этом PR, кроме contract-safe типов/tests.

Ожидаемый результат:
- markdown contract или code patch;
- каталог не меньше `18-30` meaningful screen tips и не меньше `20` candidate actions, если агент не докажет более компактный состав;
- mapping `evidence -> issue/strength -> semantic tip -> UI copy`;
- mapping `evidence -> issue/strength -> semantic tip -> semantic action -> physical user move`;
- examples/golden cases;
- test plan или unit tests для mapping.

Обязательные coverage buckets:
- look space / edge pressure / tight framing
- weak subject prominence
- background competition / clutter
- subject-background separation
- dark merge / silhouette merge
- bright hotspot behind subject
- flat frame / weak depth
- camera too high / too low for cleaner composition
- distracting prop near face or subject contour
- off-balance object placement in object-centric shot
- object merge behind subject head/shoulder contour
- subject/object naming confidence and safe label fallback
- good frame / do-not-overcoach path

Write scope для implement:
- `docs/cameraanalysis/*` для source-of-truth документа;
- `shafinMultitool/Multitool2Module/Models/CameraAnalysis/*` для новых contract-safe типов;
- `shafinMultitoolTests/*CameraAnalysis*` для contract/mapping tests;
- без UI файлов и без provider/network code.

Definition of done:
- `design`: по каталогу можно строить экранные подсказки без домысливания;
- `design verify`: выявлены дубли, конфликтующие tips и missing mappings;
- `implement`: типы/fixtures/mapping tests добавлены и не ломают существующие contracts;
- каждая tip имеет reason, action, priority, supported modes (`live`, `pause`) и fallback behavior;
- каталог покрывает camera, light, subject staging и object/prop staging, а не только framing/light;
- для object-centric shots есть хотя бы базовые советы вида `сдвинь предмет`, `убери отвлекающий объект`, `перебалансируй композицию`.
- entity-aware contract позволяет безопасно materialize-ить текст вида `сдвинь цветок правее` или fallback `сдвинь предмет правее`, если имя ненадежно.
```

## Prompt 20. VLM Evidence Contract Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/09-reasoning-provider.md
- docs/cameraanalysis/15-evidence-taxonomy-contract.md
- docs/cameraanalysis/19-neural-evidence-domain-contract.md
- docs/cameraanalysis/21-hybrid-fusion-layer.md
- docs/cameraanalysis/22-offloading-contract.md
- docs/cameraanalysis/12-agent-prompts.md

PR-контекст:
- PR: `PR-S02`
- название: `VLM Visual Semantic Evidence Contract`
- режим рекомендуется: `design -> design verify -> implement`

Задача:
Спроектируй контракт, по которому VLM/remote critic возвращает не финальный совет, а структурированные визуальные evidence для semantic tips.

Что нужно сделать:
- определить `VLMVisualEvidenceRequest`;
- определить `VLMVisualEvidenceResponse`;
- определить allowed fields: subject readability, background separation, lighting relation, clutter, depth, face visibility, frame intent, mood preservation;
- определить entity-aware fields в response:
  - `primaryEntityRef`
  - `primaryEntityKind`
  - `primaryEntityDisplayLabelCandidate`
  - `primaryEntityLabelConfidence`
  - optional `secondaryEntityRef`
  - optional `secondaryEntityKind`
  - optional `secondaryEntityDisplayLabelCandidate`
  - relation types вроде `competes_with`, `merges_with`, `blocks`, `pulls_attention_from`
- определить allowed `suggestedActionIds`, совместимые с `PR-S01`;
- определить safe naming policy: когда VLM может предложить `цветок`, `ваза`, `лицо`, а когда обязан вернуть generic label;
- определить confidence и uncertainty semantics;
- определить forbidden behavior: VLM не может invent-ить новые issue/action ids и не может переписывать deterministic taxonomy;
- определить validation errors и fallback behavior;
- дать JSON examples для хорошего/плохого кадра.

Ограничения:
- VLM работает только в `pause` или offloaded deep analysis;
- live path не должен зависеть от VLM;
- response должен быть machine-validated;
- свободный текст допускается только как secondary explanation, не как decision source;
- VLM не может навязывать display label без confidence и без entity grounding;
- response должен позволять planner-у строить templates вида `сдвинь {target}` / `убери {secondary}` / `отодвинь {target} от фона`;
- privacy/offloading boundaries должны быть совместимы с `22-offloading-contract.md`.

Ожидаемый результат:
- contract doc или Swift/Python schema sketch;
- request/response examples;
- validation rules;
- prompt skeleton for VLM;
- failure matrix.

Write scope для implement:
- `docs/cameraanalysis/*`;
- optional new model types under `Models/CameraAnalysis/*`;
- optional tests for decoding/validation;
- без реального network client и без UI.

Definition of done:
- контракт можно отдать VLM provider agent без дополнительных вопросов;
- invalid VLM output fail-closed возвращает deterministic-only critique;
- entity-aware labels and refs в ответе достаточно формализованы для template-based user copy;
- response объясняет визуальные причины, но не становится финальным product verdict.
```

## Prompt 21. Pause VLM Provider Prototype Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/09-reasoning-provider.md
- docs/cameraanalysis/22-offloading-contract.md
- docs/cameraanalysis/23-hybrid-eval-harness.md
- docs/cameraanalysis/19-neural-evidence-domain-contract.md
- docs/cameraanalysis/20-on-device-inference-wrapper.md
- docs/cameraanalysis/13-agent-briefing-template.md

Дополнительно изучи код:
- shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift
- shafinMultitool/Multitool2Module/Services/Reasoning/*
- shafinMultitool/Multitool2Module/Models/CameraAnalysis/*

PR-контекст:
- PR: `PR-S03`
- название: `Pause VLM Evidence Provider Prototype`
- режим рекомендуется: `implement`

Задача:
Реализуй отключаемый prototype provider для pause-only VLM evidence path.

Что нужно сделать:
- добавить protocol/facade для `VisualSemanticEvidenceProvider`;
- реализовать `MockVLMVisualEvidenceProvider` для tests/demo;
- подготовить место для `RemoteVLMVisualEvidenceProvider`, но не делать его обязательным;
- подключить provider в pause path после deterministic snapshot/semantics и до fusion/planner;
- передавать и возвращать entity-aware payload:
  - refs
  - label candidates
  - label confidence
  - object/person relation hints
- обеспечить timeout/cancel/fallback;
- логировать provider status для eval/debug;
- не менять live path.

Ограничения:
- если provider unavailable/invalid/timeout, UI должен получить deterministic critique;
- provider не может напрямую менять `CritiqueReport` без validation/fusion layer;
- provider не может напрямую публиковать user-facing final label без planner validation/safe fallback policy;
- не отправлять реальные изображения на сервер без explicit config flag;
- не смешивать text reasoning provider из `PR-012/PR-013` с visual evidence provider.

Ожидаемый результат:
- code patch;
- mock provider;
- integration tests на success/timeout/invalid/fallback;
- короткая integration note.

Write scope:
- `shafinMultitool/Multitool2Module/Services/Reasoning/*` или новый соседний `Services/VisualEvidence/*`;
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift`;
- `shafinMultitool/Multitool2Module/Models/CameraAnalysis/*`;
- tests under `shafinMultitoolTests/*CameraAnalysis*`;
- без UI redesign.

Definition of done:
- pause path может получить structured VLM evidence через mock provider;
- live path не вызывает provider;
- deterministic fallback сохраняется при любой ошибке provider;
- entity-aware response доходит до planner без потери refs/confidence;
- tests доказывают, что provider не является source-of-truth.
```

## Prompt 22. Semantic Fusion and Tip Planner Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/07-critique-engine.md
- docs/cameraanalysis/08-ui-integration.md
- docs/cameraanalysis/15-evidence-taxonomy-contract.md
- docs/cameraanalysis/19-neural-evidence-domain-contract.md
- docs/cameraanalysis/21-hybrid-fusion-layer.md
- docs/cameraanalysis/23-hybrid-eval-harness.md

Дополнительно изучи код:
- shafinMultitool/Multitool2Module/Services/Critique/*
- shafinMultitool/Multitool2Module/Services/Recommendation/*
- shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift
- shafinMultitool/Multitool2Module/Models/CameraAnalysis/*

PR-контекст:
- PR: `PR-S04`
- название: `Semantic Tip Fusion and Planner`
- режим рекомендуется: `design verify -> implement`

Задача:
Связать deterministic critique, neural/VLM evidence и каталог tips в финальный список экранных семантических рекомендаций.

Что нужно сделать:
- реализовать `SemanticTipPlanner` или расширить существующий `RecommendationPlanner`;
- принимать deterministic `CritiqueReport`, `RecommendationPlan`, `SceneSemanticsReport`, optional VLM evidence;
- выбирать 1 primary tip для live и 2-4 expanded tips для pause;
- учитывать conflict policy: VLM может reinforce/soften/rerank, но не invent;
- materialize-ить entity-aware tip output:
  - выбрать `actionFrame`: camera / subject / object / light / wait
  - выбрать `targetEntityRef` и safe `targetEntityDisplayLabel`
  - optional `secondaryEntityDisplayLabel` для конфликтов типа `объект за головой`
  - выбрать generic fallback, если конкретное имя ненадежно
- сохранять explainability trace для каждой tip;
- добавлять positive tip, если кадр хороший;
- обеспечивать stable sorting и anti-flicker behavior.

Ограничения:
- не генерировать свободный текст без catalog template;
- не показывать пользователю больше одной live tip одновременно;
- не предлагать физически невозможные действия;
- не давать lighting advice, если evidence low-confidence и deterministic signals противоречат ему;
- planner обязан различать:
  - когда корректнее двигать камеру;
  - когда корректнее двигать субъекта;
  - когда корректнее двигать предмет/prop;
- planner не должен материалize-ить tip `сдвинь цветок` без достаточного entity confidence;
- не трогать network/offload provider.

Ожидаемый результат:
- code patch;
- unit tests/golden cases;
- mapping examples;
- trace validation.

Write scope:
- `shafinMultitool/Multitool2Module/Services/Recommendation/*`;
- `shafinMultitool/Multitool2Module/Services/Critique/*` только при необходимости;
- `shafinMultitool/Multitool2Module/Models/CameraAnalysis/*`;
- `shafinMultitoolTests/*Recommendation*` и `*CameraAnalysis*`.

Definition of done:
- для типовых кадров planner выдает конкретные context-aware tips;
- VLM evidence может менять приоритет, но не ломает deterministic fallback;
- каждый user-facing tip имеет trace и linked issue/strength/action;
- planner умеет строить entity-aware copy с safe fallback labels;
- live/pause режимы различаются по объему, но используют один contract.
```

## Prompt 23. Semantic Tips UI Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/08-ui-integration.md
- docs/cameraanalysis/13-agent-briefing-template.md
- docs/cameraanalysis/12-agent-prompts.md

Дополнительно изучи код:
- shafinMultitool/Multitool2Module/ViewModels/CameraViewModel.swift
- shafinMultitool/Multitool2Module/UI/Overlay/OverlayView.swift
- shafinMultitool/Multitool2Module/UI/Overlay/SuggestionChip.swift
- любые существующие pause critique / overlay files

PR-контекст:
- PR: `PR-S05`
- название: `Semantic Tips On-Screen UI`
- режим рекомендуется: `implement`

Задача:
Показать semantic tips на экране: короткая подсказка в live, расширенные контекстные советы в pause/expanded verdict.

Что нужно сделать:
- пробросить semantic tips из pipeline/view model;
- live: показывать одну короткую подсказку с actionable текстом;
- tap по live tip открывает расширенное объяснение, если доступно;
- pause: показывать 2-4 tips с reason/action format;
- поддержать entity-aware user copy:
  - `сдвинь цветок правее`
  - `убери вазу из-за лица`
  - `смести героя левее`
  - fallback: `сдвинь предмет`, `убери объект справа`
- добавить визуальные annotations, если tip связан с region/direction;
- добавить empty/good-frame state;
- сохранить fallback на legacy suggestions.

Ограничения:
- live UI не должен перегружать экран;
- не показывать длинный VLM текст поверх preview;
- не запускать VLM из tap-handler напрямую;
- UI не должен показывать сырые internal ids вроде `primarySubject` или `object_1`;
- pause sheet/card не должен конфликтовать с уже существующим pause critique flow;
- не менять camera capture flow.

Ожидаемый результат:
- code patch;
- UI smoke steps;
- screenshots или manual QA notes, если возможно;
- accessibility labels для tips/actions.

Write scope:
- `CameraViewModel.swift`;
- `OverlayView.swift`;
- `SuggestionChip.swift`;
- pause critique presentation files;
- tests/previews только если они уже используются в проекте.

Definition of done:
- пользователь видит конкретную подсказку на live preview;
- в pause пользователь видит semantic explanation: почему кадр хорош/плох и что сделать;
- если semantic tips недоступны, старый hint path продолжает работать;
- entity labels в UI читаются естественно и при низкой confidence корректно деградируют до generic wording;
- UI не мерцает и не показывает contradictory tips.
```

## Prompt 24. VLM-Labeled Dataset Capture Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/16-dataset-schema-and-labeling-guide.md
- docs/cameraanalysis/17-ava-usage-policy-and-pretraining-design.md
- docs/cameraanalysis/23-hybrid-eval-harness.md
- docs/cameraanalysis/15-evidence-taxonomy-contract.md
- docs/cameraanalysis/19-neural-evidence-domain-contract.md

PR-контекст:
- PR: `PR-S06`
- название: `VLM-Labeled Semantic Tip Dataset`
- режим рекомендуется: `design -> implement`

Задача:
Подготовить dataset loop, где VLM используется как teacher для сбора примеров semantic tips, а не как runtime dependency.

Что нужно сделать:
- определить record schema для кадра, deterministic snapshot, VLM evidence, final tip, human override;
- добавить entity-aware dataset fields:
  - target entity refs
  - target/secondary labels
  - label confidence
  - human-corrected display label
  - actionFrame
- добавить export/import формат для hard cases;
- добавить поля для privacy/provenance;
- подготовить starter fixtures 10-20 synthetic/demo cases без реальных приватных изображений;
- описать review workflow: VLM suggestion -> human accept/edit/reject;
- связать records с eval harness.

Ограничения:
- не хранить raw private images без явного consent/provenance;
- VLM labels не становятся gold без review;
- object/person labels тоже не становятся gold без review;
- dataset должен быть совместим с future on-device distillation.

Ожидаемый результат:
- dataset schema doc или fixtures/scripts;
- examples;
- QA checklist;
- eval compatibility note.

Write scope:
- `docs/cameraanalysis/*`;
- `docs/cameraanalysis/eval/*` для fixtures/scripts, если нужно;
- без app runtime changes.

Definition of done:
- можно начать собирать пары `frame -> evidence -> semantic tip`;
- records пригодны для eval и будущего обучения lightweight модели;
- records сохраняют entity-aware action targets и human-corrected labels;
- provenance/privacy поля обязательны и проверяемы.
```

## Prompt 25. On-Device Semantic Distillation Agent

```text
Обязательный префикс:
Прочитай:
- docs/cameraanalysis/18-hybrid-model-architecture-spec.md
- docs/cameraanalysis/19-neural-evidence-domain-contract.md
- docs/cameraanalysis/20-on-device-inference-wrapper.md
- docs/cameraanalysis/23-hybrid-eval-harness.md
- docs/cameraanalysis/16-dataset-schema-and-labeling-guide.md

PR-контекст:
- PR: `PR-S07`
- название: `On-Device Semantic Evidence Distillation Plan`
- режим рекомендуется: `design`

Задача:
Спроектируй путь от VLM teacher к компактной on-device модели, которая предсказывает semantic evidence для подсказок без постоянного VLM/offloading.

Что нужно сделать:
- выбрать distillation targets из `PR-S01/S02`;
- отдельно определить, какие entity-aware targets дистиллируются:
  - entity kind
  - relation/conflict type
  - label confidence class
  - action frame choice (`camera`, `subject`, `object`, `light`, `wait`)
- определить training labels и loss;
- определить minimal model/backbone assumptions;
- определить Core ML conversion path;
- определить latency/memory targets для iPhone;
- определить eval: teacher agreement, human-reviewed tip accuracy, mobile metrics;
- описать rollback/fallback.

Ограничения:
- не проектировать giant VLM on-device;
- модель предсказывает evidence heads, а не финальный свободный текст;
- финальная человекочитаемая формулировка продолжает строиться template-based planner-ом;
- deterministic planner остается финальным decision layer.

Ожидаемый результат:
- design doc;
- training/eval plan;
- model size/latency assumptions;
- staged implementation backlog.

Definition of done:
- понятно, как заменить часть pause VLM calls компактной локальной моделью;
- есть понятный путь thesis narrative: heavy VLM teacher -> dataset -> distilled mobile evidence model -> semantic screen tips;
- entity-aware labels и target selection не требуют свободной генерации текста на устройстве;
- план не требует менять пользовательский UI contract.
```

## Recommended Execution Order for Semantic Tips

1. `PR-S01` Semantic Tip Taxonomy
2. `PR-S02` VLM Evidence Contract
3. `PR-S04` Semantic Fusion and Tip Planner
4. `PR-S05` Semantic Tips UI
5. `PR-S03` Pause VLM Provider Prototype
6. `PR-S06` VLM-Labeled Dataset Capture
7. `PR-S07` On-Device Semantic Distillation Plan

Практическая логика порядка:
- сначала закрываем язык подсказок и контракты;
- затем делаем planner и UI, чтобы подсказки появились на экране даже без VLM;
- потом подключаем VLM как усилитель pause-разбора;
- после этого собираем dataset и проектируем distillation.
