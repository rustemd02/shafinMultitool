# Implementation Snapshot

Last verified commit: `02bdf3ae0b711ed5e0b7a640cbf808196d304b62`

## Ключевые Swift-модули Scene Generator

| Файл | Назначение | Главы |
|---|---|---|
| `shafinMultitool/SceneGeneratorModule/Models/SceneScript.swift` | Public `SceneScript`, actors, objects, beats, diagnostics, keyword mappings. | ch3, ch4 |
| `shafinMultitool/SceneGeneratorModule/Models/ScenePlanning.swift` | `ScenePlanIR`, V9 slot catalog/event table/patch ops, provider protocols, router outcomes. | ch3, ch4 |
| `shafinMultitool/SceneGeneratorModule/Models/SceneBundleContracts.swift` | Bundle/chunk/document contracts and visual overlays. | ch4 |
| `shafinMultitool/SceneGeneratorModule/Services/SceneBundlePipeline.swift` | Runtime bundle-first pipeline and stitching. | ch3, ch4 |
| `shafinMultitool/SceneGeneratorModule/Services/LLMParserService.swift` | Local provider, llama.cpp/GGUF path, grammar strings for plan/event/patch outputs. | ch4 |
| `shafinMultitool/SceneGeneratorModule/Services/ScenePlanCompiler.swift` | Deterministic plan compiler. | ch3, ch4 |
| `shafinMultitool/SceneGeneratorModule/Services/SceneEventTableV9Service.swift` | V9 event verifier, repair, guardrails, compile-to-plan. | ch4, ch5 |
| `shafinMultitool/SceneGeneratorModule/Services/SceneParseCoordinator.swift` | Parse orchestration and routing. | ch3 |
| `shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift` | UI-facing state and invocation layer. | ch4 |
| `shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift` | AR scene presentation boundary. | ch4 |

## Ключевые Swift-модули Camera Analysis

| Файл | Назначение | Главы |
|---|---|---|
| `shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift` | Domain contracts: snapshots, semantics, critique, evidence, recommendations. | ch3, ch4 |
| `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` | Feature aggregation, semantics, live/pause presentation orchestration. | ch4 |
| `shafinMultitool/Multitool2Module/Services/Critique/FrameCritiqueEngine.swift` | Deterministic critique engine. | ch4, ch5 |
| `shafinMultitool/Multitool2Module/Services/Pipeline/NeuralEvidenceInferenceService.swift` | Neural evidence policy, request/outcome, provider execution. | ch4 |
| `shafinMultitool/Multitool2Module/Services/Pipeline/HybridFusionService.swift` | Fusion between deterministic critique and neural evidence. | ch4 |
| `shafinMultitool/Multitool2Module/Services/Recommendation/SemanticTipPlanner.swift` | Ranking and formatting semantic tips. | ch4 |
| `shafinMultitool/Multitool2Module/Services/Reasoning/VisualSemanticEvidenceCoordinator.swift` | Optional VLM visual evidence coordination. | ch4 |
| `shafinMultitool/Multitool2Module/Models/CoreMLWrappers/AestheticScorer.swift` | CoreML aesthetic scoring wrapper. | ch4 |
| `shafinMultitool/Multitool2Module/Models/CoreMLWrappers/DETRDetector.swift` | CoreML/DETR object detection wrapper. | ch4 |

## Ключевые Python/data/eval-модули

| Directory/File | Назначение | Главы |
|---|---|---|
| `docs/SGv7pipeline/graph_generator/**` | Deterministic graph/CIR generation. | ch4 |
| `docs/SGv7pipeline/source_generation/**` | Source text/paraphrase generation. | ch4 |
| `docs/SGv7pipeline/augmentation/**` | Morphology/noise augmentation. | ch4 |
| `docs/SGv7pipeline/validators/**` | Semantic critic and validate/pack layer. | ch4 |
| `docs/SGv7pipeline/dataset_builder/**` | Dataset splits and preference pairs. | ch4 |
| `docs/SGv7pipeline/training/**` | Phase views, compare checkpoints, experiment registry. | ch4, ch5 |
| `docs/SGv7pipeline/eval/**` | Eval harness, scoring, reporting. | ch5 |
| `docs/SGv7pipeline/runtime_feedback/**` | Runtime failure normalization/review/export. | ch4, ch5 |
| `docs/SGv8pipeline/v8/**` | Plan dataset/eval/compiler artifacts. | ch4, ch5 |
| `docs/SGv9pipeline/v9/**` | Event dataset/eval/compiler/verifier artifacts. | ch4, ch5 |
| `experiments/sc_benchmark/**` | Reusable scientific benchmark orchestrator and reports. | ch5 |
| `docs/cameraanalysis/eval/**` | Camera deterministic/hybrid eval harness. | ch5 |

## Тесты

| Test file | Проверяемая область |
|---|---|
| `shafinMultitoolTests/SceneParserServiceTests.swift` | Scene parser behavior. |
| `shafinMultitoolTests/SceneV8PipelineTests.swift` | V8/live dataset smoke path. |
| `shafinMultitoolTests/SceneBundlePipelineTests.swift` | Bundle/chunk/stitch/V9 coverage tests. |
| `shafinMultitoolTests/CameraAnalysisDomainContractsTests.swift` | Camera contracts. |
| `shafinMultitoolTests/FrameCritiqueEngineTests.swift` | Deterministic critique. |
| `shafinMultitoolTests/HybridFusionServiceTests.swift` | Fusion behavior. |
| `shafinMultitoolTests/NeuralEvidenceInferenceServiceTests.swift` | Neural evidence policy/outcomes. |
| `docs/SGv7pipeline/**/tests/*.py` | Offline pipeline package tests. |
| `docs/SGv8pipeline/v8/tests/*.py` | V8 data/eval/projection tests. |
| `docs/SGv9pipeline/v9/tests/*.py` | V9 data/eval/projection tests. |
| `docs/cameraanalysis/eval/tests/*.py` | Camera eval harness tests. |

## Что можно описывать в главе “Реализация”

1. Contract-first modelling: `SceneScript`, `ScenePlanIR`, V9 event table, Camera Analysis domain contracts.
2. Deterministic compiler/repair boundaries: compile, guardrails, reason codes.
3. Local inference integration: llama.cpp/GGUF provider and GBNF constraints.
4. Bundle/chunk native scene processing: normalizer, detector, segmenter, stitcher.
5. Camera Analysis: feature snapshots, semantics, critique, recommendations, neural evidence wrapper.
6. Eval harnesses as implementation artifacts, not only post-hoc analysis.
