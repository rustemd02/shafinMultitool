# 01. Roadmap

## Phase 0. Baseline

Цель:
- заморозить текущую систему и измерить стартовые метрики

Задачи:
- сохранить текущий checkpoint и runtime prompt
- собрать frozen eval set из runtime logs
- определить ключевые buckets ошибок
- зафиксировать baseline metrics

Артефакты:
- `eval/baseline_prompts.jsonl`
- `eval/baseline_results.json`
- `eval/error_taxonomy.md`

## Phase 1. Data Architecture

Цель:
- спроектировать canonical graph-first pipeline

Задачи:
- зафиксировать runtime/train contract
- определить canonical intermediate representation
- определить pattern library
- определить complexity budget для 1.5B
- определить train/eval data contract

Артефакты:
- `contract/runtime_train_contract.md`
- `contract/fixtures.jsonl`
- schema для intermediate graph
- список scene patterns
- сложностные ограничения

## Phase 2. Data Generation

Цель:
- научиться автоматически генерировать правильный canonical data pool

Задачи:
- реализовать graph generator
- реализовать source generator/paraphraser
- реализовать morphology/noise augmenter
- реализовать semantic critic

Артефакты:
- `dataset_v7_graphs.jsonl`
- `dataset_v7_sources.jsonl`
- `dataset_v7_augmented.jsonl`

## Phase 3. Validation and Assembly

Цель:
- упаковать только recoverable и canonical samples

Задачи:
- schema validation
- graph consistency validation
- source-to-graph recoverability checks
- semantic stratified train/val/test split
- provenance-tier assignment для real corrected samples
- complexity-budget filtering

Артефакты:
- `dataset_v7_sft_train.jsonl`
- `dataset_v7_sft_val.jsonl`
- `dataset_v7_sft_test.jsonl`

## Phase 4. Training

Цель:
- обучить модель без избыточного drift

Задачи:
- phase-wise SFT
- hard-case oversampling
- optional preference tuning
- regression comparison against baseline

Артефакты:
- `checkpoints/v7_phase1`
- `checkpoints/v7_phase2`
- `checkpoints/v7_final`

## Phase 5. Runtime Feedback

Цель:
- сделать pipeline самоуточняющимся

Задачи:
- собирать runtime failures
- автоматически кластеризовать ошибки
- дообогащать hard buckets
- переобучать на инкрементальных версиях
- присваивать corrected targets явный provenance tier

Артефакты:
- `runtime_failures.jsonl`
- `hard_case_clusters.json`
- `dataset_v7_incremental_patch.jsonl`
