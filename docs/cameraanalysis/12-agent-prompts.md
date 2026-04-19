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

Дополнительно изучи:
- domain contracts
- explainability contract
- semantics layer artifacts

Задача:
Спроектируй и/или реализуй deterministic `FrameCritiqueEngine`.

Что нужно сделать:
- определить issue detection rules
- определить strength detection rules
- ввести severity/confidence
- связывать issues с explainability trace
- покрыть logic golden tests

Ограничения:
- LLM не источник истины для issues
- issue taxonomy должна оставаться ограниченной и объяснимой

Ожидаемый результат:
- design doc или code patch
- test suite
- invariants and edge cases

Definition of done:
- для golden cases critique engine выдает воспроизводимый `CritiqueReport`
- все issues и strengths имеют traceable rationale
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

Дополнительно изучи:
- critique and recommendation contracts
- pause UI contract

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
