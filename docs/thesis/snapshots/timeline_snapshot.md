# Timeline Snapshot

Source: `diploma.md`
Last verified commit: `02bdf3ae0b711ed5e0b7a640cbf808196d304b62`

This is a grouped research/development timeline, not a full copy of `diploma.md`.

## initial camera/preproduction module

| Period | Summary | Evidence |
|---|---|---|
| 2025-11-22 | Early camera/preproduction slice with stage/detresnet context. | `diploma.md` heading: `stage + detresnet` |
| 2025-12-01 | Scene generator base slice appears. | `diploma.md` heading: `scene generator base` |
| 2026-01-28 | Performance-related slice and parser improvements. | `diploma.md` headings 2026-01-28 |

## Scene Generator base

| Period | Summary | Evidence |
|---|---|---|
| 2026-01-28 to 2026-03-25 | Rule-based parsing evolved toward more robust scene parsing, multiple actors/objects, and then beat-based structure after limitations of flat actions. | `diploma.md`, `shafinMultitool/SceneGeneratorModule/Models/SceneScript.swift`, `shafinMultitoolTests/SceneParserServiceTests.swift` |

## local LLM integration

| Period | Summary | Evidence |
|---|---|---|
| 2026-03-13 | Local LLM integration with llama.cpp and Qwen2.5-0.8B in SceneGeneratorModule. | `diploma.md`, `shafinMultitool/SceneGeneratorModule/Services/LLMParserService.swift`, `shafinMultitool/SceneGeneratorModule/Services/LlamaContext.swift` |
| 2026-03-23 | Inference optimization through GBNF and improved 3D planner. | `diploma.md`, `shafinMultitool/SceneGeneratorModule/Services/LLMParserService.swift` |
| 2026-04-09 | Qwen2.5-1.5B, GGUF Q4_K_M, state-aware prompt and expanded schema. | `diploma.md` |

## dataset/SFT

| Period | Summary | Evidence |
|---|---|---|
| 2026-03-24 | Synthetic SFT dataset generation and integration of fine-tuned SLM. | `diploma.md` |
| 2026-04-01 | Transition to contiguous chunk generation and semantic filtering. | `diploma.md` |
| 2026-04-20 | Benchmark of baseline Qwen3 vs SFT LoRA and preparation for v6/ORPO comparison. | `diploma.md`, `experiments/sc_benchmark/runs/sgv7_eval_logs/summary.json` |

## SG v7

| Period | Summary | Evidence |
|---|---|---|
| 2026-04-12 | SG v7 pipeline designed for local LLM fine-tuning. | `diploma.md`, `docs/SGv7pipeline/00-overview.md` |
| 2026-04-13 | Prompt 1/2: CIR contract and coverage. | `diploma.md`, `docs/SGv7pipeline/cir_contract/**` |
| 2026-04-13 | Prompt 3/4: deterministic graph generation and source paraphrase generation. | `diploma.md`, `graph_generator/**`, `source_generation/**` |
| 2026-04-13 | Prompt 5/6: augmentation and deterministic validator stack. | `diploma.md`, `augmentation/**`, `validators/**` |
| 2026-04-14 | Prompt 7/8/10: dataset split assembly, training harness, runtime feedback loop. | `diploma.md`, `dataset_builder/**`, `training/**`, `runtime_feedback/**` |
| 2026-04-15 to 2026-04-21 | Train-ready and quality-first hardening; iter3.1 prep eval and transfer failure fixed as evidence. | `diploma.md`, `docs/SGv7pipeline/09-eval-and-release.md` |

## v8

| Period | Summary | Evidence |
|---|---|---|
| 2026-04-22 | SG V8.0 introduced plan-to-compile benchmark route and local runner. | `diploma.md`, `docs/SGv8pipeline/v8/README.md` |
| 2026-04-22 | V8 hotfix compile path and updated comparisons. | `diploma.md`, `docs/SGv8pipeline/runs/v8_0_seed42/**` |

## v9

| Period | Summary | Evidence |
|---|---|---|
| 2026-05-01 | V9 slot/event benchmark fixed metrics and comparison. | `diploma.md`, `docs/SGv9pipeline/v9/README.md` |
| 2026-05-04 | V9 runtime hardening, live-smoke stabilization, repeated benchmark. | `diploma.md`, `docs/SGv9pipeline/runs/v9_0_seed42/**` |

## bundle/chunk-native pipeline

| Period | Summary | Evidence |
|---|---|---|
| 2026-04-22 | Chunk-native SceneBundle pipeline implemented for mixed screenplay/prose, append-only continuity and bundle-level eval scaffolding. | `diploma.md`, `shafinMultitool/SceneGeneratorModule/Services/SceneBundlePipeline.swift`, `shafinMultitool/SceneGeneratorModule/Models/SceneBundleContracts.swift`, `docs/SGv7pipeline/v1/**` |

## Camera Analysis

| Period | Summary | Evidence |
|---|---|---|
| 2026-04-19 | Camera Analysis v1 roadmap and domain/explainability contracts. | `diploma.md`, `docs/cameraanalysis/00-overview.md`, `03-domain-contracts.md`, `04-explainability-contract.md` |
| 2026-04-20 | Deterministic critique engine and later PR summary. | `diploma.md`, `shafinMultitool/Multitool2Module/Services/Critique/FrameCritiqueEngine.swift` |
| 2026-04-22 | Hybrid stage, evidence taxonomy and neural evidence wrapper. | `diploma.md`, `shafinMultitool/Multitool2Module/Services/Pipeline/NeuralEvidenceInferenceService.swift`, `docs/cameraanalysis/19-neural-evidence-domain-contract.md` |
| 2026-05-04 to 2026-05-05 | Semantic tips, VLM/evidence/provider/planner prompts and implement verify. | `diploma.md`, `shafinMultitool/Multitool2Module/Services/Recommendation/SemanticTipPlanner.swift`, `shafinMultitool/Multitool2Module/Services/Reasoning/VisualSemanticEvidenceCoordinator.swift` |

## live smoke / limitations

| Date | Result | Interpretation |
|---|---|---|
| 2026-04-26 | V8 real GGUF live smoke `passed=0/12`; model loaded and ran about 808 seconds. | Negative evidence: current V8 GGUF not reliable for complex live runtime. |
| 2026-05-04 | V9 live smoke reported `1/1 passed` after runtime hardening. | Positive but still needs final attached parity package before defense. |
| 2026-05-04 | Camera hybrid eval implemented but verdict `mobile_blocked` in smoke. | Neural Camera Analysis uplift is not yet a verified final claim. |
