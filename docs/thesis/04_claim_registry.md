# Claim Registry

Last verified commit: `02bdf3ae0b711ed5e0b7a640cbf808196d304b62`

| Claim ID | Утверждение | Тип | Источник подтверждения | Где использовать | Статус |
|---|---|---|---|---|---|
| CL-LR-001 | Смартфоны являются значимым устройством для мобильного видеопроизводства. | litreview_claim | `docs/thesis/litreview.md`, sources [1], [2] inside litreview | theory | litreview_unchecked |
| CL-LR-002 | Обзор включает публикации 2020-2025 and selected 104 publications / 7 detailed works. | litreview_claim | `docs/thesis/litreview.md` | methodology | litreview_unchecked |
| CL-LR-003 | Для preproduction mobile AR solutions face dropped frames, heating and energy constraints. | litreview_claim | `docs/thesis/litreview.md` table 1/2 | theory, bridge | litreview_unchecked |
| CL-LR-004 | Existing shooting-stage tools often provide scores/classifications but lack explainable user recommendations. | litreview_claim | `docs/thesis/litreview.md` conclusion/table 5 | bridge, camera analysis | litreview_unchecked |
| CL-LR-005 | Automated editing is relevant context but current mobile solutions have quality/performance tradeoffs. | litreview_claim | `docs/thesis/litreview.md` montage section | theory, limitations | litreview_unchecked |
| CL-BR-001 | Практический проект отвечает на gap комплексности через preproduction + shooting assistance, но не реализует полный монтаж. | bridge_claim | EV-BUNDLE-001, EV-CA-001, litreview conclusion | brief, ch3, ch6 | partially_verified |
| CL-BR-002 | Scene Generator является практическим продолжением AR/previsualization темы litreview through structured scene generation. | bridge_claim | EV-SG8-001, EV-SG9-001, `shafinMultitool/SceneGeneratorModule/Views/ARSceneContainer.swift` | ch3 | verified |
| CL-BR-003 | Camera Analysis является практическим продолжением темы explainable shooting assistance. | bridge_claim | EV-CA-001, EV-CA-002, EV-CA-EVAL-001 | ch3, ch4, ch5 | verified |
| CL-BR-004 | Методология проекта должна быть отделена от методологии литературного обзора и опираться на benchmark/eval artifacts. | bridge_claim | EV-EVAL-001, `docs/thesis/snapshots/model_eval_snapshot.md`, `docs/thesis/snapshots/camera_analysis_snapshot.md` | ch5 | verified |
| CL-ARCH-001 | Архитектура разделяет model-generated intermediate artifacts and deterministic compilation/fallback. | architecture | EV-SG8-001, EV-SG9-001, EV-BUNDLE-001 | ch3 | verified |
| CL-ARCH-002 | `ScenePlanIR` является internal-only layer; public product contract remains `SceneScript`. | architecture | `docs/SGv8pipeline/v8/README.md`, `shafinMultitool/SceneGeneratorModule/Models/ScenePlanning.swift`, `shafinMultitool/SceneGeneratorModule/Models/SceneScript.swift` | ch3, ch4 | verified |
| CL-IMPL-001 | `SceneBundlePipeline` реализует bundle-first parsing with normalization, boundary detection, chunking, stitching and compilation. | implementation | EV-BUNDLE-001 | ch4 | verified |
| CL-IMPL-002 | `LLMParserService` contains local generation paths and GBNF grammars for ScenePlanIR/V9 outputs. | implementation | `shafinMultitool/SceneGeneratorModule/Services/LLMParserService.swift` | ch4 | verified |
| CL-DES-001 | SG v7 reduces teacher target noise by generating canonical semantics before textual variants and target JSON. | design_decision | EV-SG7-001, EV-SG7-002 | ch3, ch4 | verified |
| CL-DES-002 | V9 reduces model burden by asking the model for a compact slot/event table and compiling deterministically. | design_decision | EV-SG9-001, EV-MET-004 | ch3, ch5 | verified |
| CL-MET-001 | On SG v7 primary metrics, `v7` had `json_valid=98.85%`, `exact_marker_id=100.00%`, `ordinal_binding=98.26%`. | metric | `experiments/sc_benchmark/reports/v6_v7/combined_eval_base_v6_v7_v7_orpo.md` | ch5 | verified |
| CL-MET-002 | `v7_orpo` improved target_resolution from `6.32%` to `8.89%` and chronology from `4.58%` to `6.49%`, with lower structural stability. | metric | same combined report | ch5 | verified |
| CL-MET-003 | `v8_plan_sft` on seed42 reached `target_resolution=0.4684`, `chronology=0.1412`, `case_strict_success=0.0954`. | metric | `docs/SGv8pipeline/runs/v8_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md` | ch5 | verified |
| CL-MET-004 | `v8_plan_orpo_iter1` on seed42 reached `target_resolution=0.4803`, `action_recall=0.4741`, `case_strict_success=0.1031`. | metric | `docs/SGv8pipeline/runs/v8_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md` | ch5 | verified |
| CL-MET-005 | `v9_event_sft` on seed42 reached `json_valid=1.0000`, `target_resolution=0.9214`, `chronology=0.8702`, `case_strict_success=0.5076`. | metric | `docs/SGv9pipeline/runs/v9_0_seed42/benchmark_results_seed42/aggregate/scientific_report.md` | ch5 | verified |
| CL-MET-006 | V9 raw event table had `event_schema_valid_rate=1.0`, `event_actor_slot_accuracy=0.9691`, `event_target_slot_accuracy=0.9439`. | metric | `docs/SGv9pipeline/runs/v9_0_seed42/eval_artifacts/dataset_v9_event_sft_seed42.event_slice_summary.json` | ch5 | verified |
| CL-MET-007 | V8 live smoke with real GGUF model produced `passed=0/12`; this is an important negative result. | metric | `diploma.md` entry 2026-04-26 | ch5, ch6 | partially_verified |
| CL-MET-008 | V9 live smoke later succeeded as `1/1 passed` after runtime hardening. | metric | `diploma.md` entry 2026-05-04 | ch5 | partially_verified |
| CL-CA-001 | Camera Analysis v1 deterministic candidate improved issue/action/strength/fallback/explainability metrics vs legacy and got release status `pass`. | experiment | `docs/cameraanalysis/eval/out_v1/compare_report.json` | ch5 | verified |
| CL-CA-002 | Camera hybrid smoke cannot support final neural uplift claim because verdict is `mobile_blocked` and pause_execute_success_rate is `0.0`. | limitation | `docs/cameraanalysis/eval/out_hybrid_example/ablation_summary.json`, `mobile_system_metrics.json` | ch5, ch6 | verified |
| CL-LIM-001 | Full automated editing pipeline is not implemented in the current production runtime. | limitation | repository map, absence of montage module, litreview alignment | ch6 | partially_verified |
| CL-LIM-002 | Metrics from seed42 frozen eval bundle should not be generalized as universal model quality without additional seeds and live parity artifacts. | limitation | benchmark setup fields and single-seed reports | ch5, ch6 | verified |
| CL-LIM-003 | Claims from litreview remain unchecked unless separately verified against bibliography. | limitation | protected litreview policy | all | verified |
| CL-CONTR-001 | The main contribution is an evidence-first mobile prototype combining structured scene generation and explainable camera analysis. | contribution | EV-SG9-001, EV-BUNDLE-001, EV-CA-001, EV-CA-EVAL-001 | brief, conclusion | verified |
| CL-CONTR-002 | The project demonstrates that structured contracts and deterministic repair/compile layers can improve runtime reliability compared with direct JSON generation. | contribution | EV-MET-003, EV-MET-004 | ch5, conclusion | verified |
| CL-CONTR-003 | The project demonstrates an explainable critique architecture for camera analysis with measurable deterministic uplift over legacy suggestions. | contribution | EV-CA-EVAL-001 | ch5, conclusion | verified |
| CL-NEEDS-001 | Exact final page allocation after integrating litreview into diploma template is not known. | limitation | no template/source provided | planning | needs_source |
| CL-NEEDS-002 | Final bibliography compliance with university style is not verified. | litreview_claim | no style guide/source provided | final editing | needs_source |
