# 11. Implementation Backlog

## Цель

Перевести весь `SG v7` в конкретные треки работ, которые можно отдавать отдельным AI-агентам.

## Track 0. Runtime / Train Contract

Задачи:
- зафиксировать exact runtime prompt format
- зафиксировать exact training prompt format
- описать canonical serializer
- описать grammar/GBNF contract
- описать decoding config и stop conditions
- собрать frozen fixtures и mismatch checks

Done definition:
- есть один source-of-truth contract
- есть versioned fixtures
- есть проверка на train/runtime drift

## Track 1. Canonical Data Contract

Задачи:
- описать intermediate graph schema
- описать final SFT schema
- описать preference pair schema

Done definition:
- есть markdown/spec
- есть example JSON
- есть validator contract

## Track 2. Pattern Library

Задачи:
- определить список pattern classes
- задать distributions
- задать hard buckets

Done definition:
- patterns описаны
- для каждого pattern есть canonical examples

## Track 3. Graph Generator

Задачи:
- создать deterministic graph builder
- добавить seed-based reproducibility
- добавить complexity controls

Done definition:
- генератор выдаёт валидные graph records

## Track 4. Source Generator

Задачи:
- сделать graph-to-text prompts
- сделать variant styles
- сделать paraphrase batch generation

Done definition:
- на один graph генерируется несколько source variants

## Track 5. Augmentation

Задачи:
- morphology transformations
- noisy user text transformations
- ordinal transformations

Done definition:
- есть отдельный augmenter
- transformations traceable metadata

## Track 6. Validators

Задачи:
- schema validator
- graph consistency validator
- recoverability validator
- semantic critic wrapper

Done definition:
- каждый sample получает pass/fail + reasons

## Track 7. Dataset Builder

Задачи:
- dedup
- balancing
- stratified split
- metadata packaging
- provenance-tier packaging
- complexity-budget packaging

Done definition:
- готовые `train/val/test` JSONL
- у каждого sample понятен provenance и budget profile

## Track 8. Training Harness

Задачи:
- phase configs
- curriculum configs
- oversampling configs
- checkpoint compare scripts

Done definition:
- можно воспроизводимо прогнать `phase1 -> phase2 -> phase3`

## Track 9. Eval Harness

Задачи:
- metric scripts
- bucket metrics
- A/B compare reports
- exact grounding and ordinal fidelity metrics

Done definition:
- автоматический eval report

## Track 10. Runtime Feedback

Задачи:
- логирование runtime failures
- clustering
- export corrected cases
- provenance assignment for corrected targets

Done definition:
- ошибки из приложения автоматически попадают обратно в dataset backlog

## Рекомендуемый порядок реализации

1. Track 0
2. Track 1
3. Track 2
4. Track 3
5. Track 6
6. Track 4
7. Track 5
8. Track 7
9. Track 9
10. Track 8
11. Track 10

## Что можно запускать параллельно

- Track 0 + Track 1
- Track 4 + Track 5
- Track 8 + Track 9

## Что нельзя делать раньше времени

- не запускать full retraining, пока не готов validator stack
- не запускать v7 training, пока не зафиксирован runtime/train contract
- не строить большой `v7`, пока не утверждён canonical contract
- не выпускать новую модель без frozen eval set
