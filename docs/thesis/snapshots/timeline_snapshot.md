# Timeline Snapshot

2026-09-17 current checkpoint: After retained failures: replay parity 3/3; annotation browser 7/runtime v1 browser 3; runtime v2 controls 7; real owner form available. Then DETR/AR controls 37/37, next-take RU/EN UI 2/2 and actual019 request 1/1. Archive 050524 build succeeds unsigned, release validation remains blocked by four components. Sources and limits: [EXECUTION_STATE](../../aegis/work/2026-09-03-gpt-5-6-pro-guidance/EXECUTION_STATE.md), [evidence map](../03_evidence_map.md). Quality/human/physical/production gates remain open; chapters 3/4/5/6 remain needs_update.

## Historical source-bound snapshots

## 2026-09-17 — integration and source-bound checkpoints

After the preservation commit, Cloud/grounding/intent/AR/privacy/annotation, marker/copy/coverage changes progressed through preserved failures97=92/5,39=34/5,9=8/1 and UI/mixed checkpoints. Marker10/geometry1 pass inside15=14/1, whose EN reset/done is not reached; later iPhone4/4 completes them. Exact recovery9/14 enables6=1/5 without file errors. The19=17/2 checkpoint qualifies11 coverage/integration,4 direction and2 complete RU/EN UI paths;180 is then mixed without KEEP with Vision unavailable. Subsequent CPU isolation1PASS and production-owner6=1/5 restore actual Vision execution, while all five recovered methods fail and180 returns good/KEEP. Corrected AR control completes three failed captures without prior SIGTRAP; The completed iPad Full Screen Settings procedure is0PASS/2FAIL with original selections restored; the application still reportsUIScene101 and its effective mode remains unknown. Fresh-read/identity instrumentation is applied; run014636 failed compilation with0 tests and the corrected repeat stopped before Xcode at the8GiB storage guard; iPad landscape remains open. Six scoped resource approvals leave four PENDING. Backend73/TLS, NIMA20 numerical rows and LASIESTA250 retain their boundaries; no current quality/physical/final Release acceptance. Spend$0. Chapters3/4/5/6 remain needs_update.

Applied-source followup (EV-RELEASE-CLOUD-DISCLOSURE-20260916 / EV-CA-PARTIAL-INTAKE-001): DETR release gate8 controls, both source notices and shell syntax pass; full-app negative controls await a fresh archive. Spatial intake15 controls/3 loader rejections and actual CLI byte parity preserve17 assisted confirmations and one research-only table→center request. Selected candidate/actuator/targets remain unknown; zero neural admission/fit/provider calls. Six approvals/four PENDING are unchanged.

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
