# Repository Map

Last verified commit: `02bdf3ae0b711ed5e0b7a640cbf808196d304b62`

| Директория | Назначение | Ключевые файлы | Связь с ВКР | Source-of-truth для claims |
|---|---|---|---|---|
| `docs/thesis/` | Thesis workspace around protected litreview. | `litreview.md`, `00_*`, `03_evidence_map.md`, `04_claim_registry.md` | Planning, writing workflow, claim verification. | yes for thesis process, no for technical facts unless linked. |
| `diploma.md` | Chronological research/development log. | entire file | Timeline, rationale, historical decisions, live smoke notes. | yes, but prefer code/eval for final metrics when available. |
| `docs/SGv7pipeline/` | SG v7 data/training/eval design and implementation. | `00-overview.md`, `02-pipeline-architecture.md`, `09-eval-and-release.md`, `18-runtime-train-contract.md`, subpackages | Practical chapters on data pipeline, training, eval. | yes |
| `docs/SGv7pipeline/cir_contract/` | CIR contracts and validators. | `cir_schema_v1.json`, `cir_serializer.py`, `cir_validator.py` | Canonical semantics and drift prevention. | yes |
| `docs/SGv7pipeline/graph_generator/` | Deterministic graph generation. | `builder.py`, `planner.py`, tests | SG v7 implementation. | yes |
| `docs/SGv7pipeline/source_generation/` | Source/paraphrase generation. | `prompt_builder.py`, `style_policy.py`, tests | SG v7 implementation. | yes |
| `docs/SGv7pipeline/augmentation/` | Controlled morphology/noise transforms. | `morphology.py`, `noise.py`, tests | Dataset robustness. | yes |
| `docs/SGv7pipeline/validators/` | Semantic critic and validate/pack. | `03_semantic_critic.py`, `05_validate_and_pack.py` | Data QA and provenance. | yes |
| `docs/SGv7pipeline/dataset_builder/` | Dataset split/preference builder. | `06_build_dataset_splits.py`, tests | Training data assembly. | yes |
| `docs/SGv7pipeline/training/` | Training phase views and checkpoint comparison. | `09_compare_checkpoints.py`, `10_register_experiment.py` | Training methodology. | yes |
| `docs/SGv7pipeline/eval/` | Eval harness. | `07_eval_local_model.py`, `scorer.py`, `reporter.py` | Experiment methodology. | yes |
| `docs/SGv7pipeline/runtime_feedback/` | Runtime failure normalization and export. | `normalize_runtime_feedback.py`, `export_real_runtime_eval_cases.py` | Dynamic improvement loop. | yes |
| `docs/SGv7pipeline/v1/` | Chunk-native data/eval layer. | `README.md`, `datasets.py`, `eval_artifacts.py` | Bundle/chunk pipeline experiments. | yes |
| `docs/SGv8pipeline/` | SG v8 plan/compile pipeline and run artifacts. | `v8/README.md`, `runs/v8_0_seed42/**` | V8 architecture and metrics. | yes |
| `docs/SGv9pipeline/` | SG v9 slot/event pipeline and run artifacts. | `v9/README.md`, `v9/final_v9_spec.md`, `runs/v9_0_seed42/**` | V9 architecture and metrics. | yes |
| `experiments/sc_benchmark/` | Scientific benchmark orchestrator and reusable assets. | `README.md`, `run_scientific_benchmark.py`, `reports/v6_v7/**` | Experiment chapter. | yes |
| `docs/cameraanalysis/` | Camera Analysis design/eval docs. | `00-overview.md`, `03-domain-contracts.md`, `04-explainability-contract.md`, `23-hybrid-eval-harness.md` | Architecture/implementation of shooting assistant. | yes |
| `docs/cameraanalysis/eval/` | Camera eval harness and outputs. | `out_v1/compare_report.json`, `out_hybrid_example/ablation_summary.json`, `out_hybrid_example/hybrid_metrics.json`, `out_hybrid_example/explainability_agreement.json`, `out_hybrid_example/mobile_system_metrics.json` | Experiment chapter. | yes |
| `shafinMultitool/SceneGeneratorModule/` | iOS runtime Scene Generator. | models/services/views listed in implementation snapshot | Practical implementation. | yes |
| `shafinMultitool/Multitool2Module/` | iOS Camera Analysis/preproduction module. | domain contracts, pipeline, critique, recommendation, CoreML wrappers | Practical implementation. | yes |
| `shafinMultitoolTests/` | XCTest coverage for app behavior. | Scene and Camera Analysis tests | Verification and behavior claims. | yes |
| `docs/uml/` | UML/supporting diagrams if present. | directory contents not inspected in depth | Optional diagrams. | possible source after review |
| `llama.cpp/` | Local dependency area with its own `AGENTS.md`. | `llama.cpp/AGENTS.md` | Local LLM runtime context. | no direct thesis claims unless cited carefully |
