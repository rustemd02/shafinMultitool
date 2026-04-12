# 02. Pipeline Architecture

## Цель документа

Описать end-to-end архитектуру `SG v7`, чтобы можно было отдельно проектировать и реализовывать каждый компонент.

## Общая схема

```text
Runtime / Training Contract
  -> Pattern Library
Pattern Library
  -> Graph Generator
  -> Canonical Scene Graph
  -> Source Generator / Paraphraser
  -> Morphology / Noise Augmenter
  -> Semantic Critic
  -> Strict Validators
  -> Dataset Assembler
  -> SFT / Preference Sets
  -> Training
  -> Offline Eval
  -> Runtime A/B
  -> Failure Mining
  -> Back to Pattern Library / Hard Cases
```

## Основные модули

### 0. Runtime / Training Contract

Хранит exact source-of-truth для:
- runtime prompt format
- training prompt format
- grammar/GBNF
- canonical serializer
- decoding settings
- frozen fixtures

Этот модуль блокирует все остальные, если есть drift между train и runtime.

### 1. Pattern Library

Хранит канонические semantic patterns:
- movement patterns
- object grounding patterns
- ordinal reference patterns
- unsupported action patterns
- dialogue patterns

### 2. Graph Generator

Создаёт canonical scene graph:
- actors
- objects
- marked object ids
- beats
- actions
- relations

### 3. Source Generator

Порождает русский source text из canonical graph:
- clean version
- colloquial version
- noisy user-like version

### 4. Augmentation Layer

Делает controlled transformations:
- morphology
- synonym swaps
- punctuation noise
- whitespace noise
- lexical contractions

### 5. Semantic Critic

Проверяет, что source text всё ещё выражает исходный graph.

### 6. Validators

Проверяют:
- schema
- graph consistency
- id integrity
- action semantics
- source recoverability

### 7. Dataset Assembler

Формирует:
- core train
- hard train
- val
- test
- preference pairs

### 8. Runtime Feedback Miner

Собирает:
- user prompts
- raw LLM outputs
- reject reasons
- corrected target JSON

## Технические принципы

- один versioned contract определяет и train, и runtime serialization
- каждый модуль должен быть независимым CLI-скриптом
- все промежуточные артефакты должны быть сериализуемы в JSONL
- все random seeds должны быть фиксируемыми
- pipeline должен уметь инкрементально перегенерировать только отдельные buckets
- никакой silent autocorrection без traceable metadata

## Рекомендуемая структура папок

```text
sg_v7/
  patterns/
  generated/
    graphs/
    sources/
    augmented/
    filtered/
    final/
  eval/
  failures/
  scripts/
  configs/
```
