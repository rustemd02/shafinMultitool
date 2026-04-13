# 16. Codebase Entry Points

Этот документ нужен, чтобы агент не читал весь репозиторий, а быстро попадал в нужные точки входа.

## Goal

Сократить время на разведку кода и уменьшить риск неправильных выводов.

## Primary Files

### Dataset Generation

- [generate_dataset_v7.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v7.py)

Это canonical SG v7 entrypoint. Из него агентам важны:
- deterministic `CIR -> SceneScript` projection path
- validation boundary для `sg_v7_cir_v1`
- fail-fast поведение на `sample_id` drift и contract mismatch
- expected integration point для будущего graph-first dataset assembly

- [generate_dataset_v6.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v6.py)

Это legacy pre-SG-v7 генератор датасета. Из него агентам важны:
- train prompts
- JSON generation prompts
- validators
- filtering heuristics
- historical schema assumptions
- legacy repair/autocorrection behavior, который не является canonical для SG v7

### Runtime LLM Parsing

- [LLMParserService.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/LLMParserService.swift)

Важен для:
- runtime prompt format
- grammar
- repair logic
- marked object handling

### Parser Selection Policy

- [SceneParserService.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/SceneParserService.swift)

Важен для:
- accept / merge / reject policy
- interaction between LLM and rule-based
- diagnostics-driven fallback

### Runtime Schema

- [SceneScript.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Models/SceneScript.swift)

Важен для:
- actual app schema
- allowed types
- ids
- object/actor/action semantics

## Secondary Files

### Diagnostics

- [DiagnosticsCalculator.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/DiagnosticsCalculator.swift)

Важен для:
- current quality heuristics
- marked object diagnostics
- missing target detection

### Marked Object Matching

- [MarkedObjectMatcher.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/MarkedObjectMatcher.swift)

Важен для:
- mention detection
- lemmatization-based matching
- morphology-sensitive object grounding

### Spatial Planning

- [SpatialPlannerService.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/SpatialPlannerService.swift)

Важен для:
- object placement semantics
- actor path planning
- consequences of bad targets / bad beats

### AR Runtime Integration

- [SceneGeneratorViewModel.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift)
- [ARSceneContainer.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift)

Важны для:
- runtime logging
- AR frame handling
- marker placement
- final execution context

## Recommended Reading Order For Agents

### Design Agents

1. [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/README.md)
2. [00-overview.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/00-overview.md)
3. [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
4. [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)
5. [generate_dataset_v7.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v7.py)
6. [generate_dataset_v6.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v6.py) только если нужен legacy comparison

### Implementation Agents For Data Pipeline

1. [generate_dataset_v7.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v7.py)
2. [03-graph-generation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/03-graph-generation.md)
3. [04-source-generation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/04-source-generation.md)
4. [05-augmentation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/05-augmentation.md)
5. [06-validation-and-critics.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/06-validation-and-critics.md)
6. [generate_dataset_v6.py](/Users/unterlantas/Documents/XCode/shafinMultitool/generate_dataset_v6.py) только если нужно понять legacy behavior

### Runtime Alignment Agents

1. [LLMParserService.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/LLMParserService.swift)
2. [SceneParserService.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/SceneParserService.swift)
3. [SceneScript.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Models/SceneScript.swift)
4. [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)
5. [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)

## What Agents Usually Do Not Need

Обычно не нужно читать:
- весь iOS UI слой
- unrelated Pods / workspace files
- старые dataset generators `v2-v5`, если задача не про historical comparison

## Rule Of Thumb

Если агенту нужно больше 8-10 файлов, briefing скорее всего недостаточно сфокусирован.
