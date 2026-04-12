# 00. Overview

## Проблема

Текущий `dataset v6` и runtime-инференс дают несколько системных проблем:
- маленькая модель схлопывает сцену в минимально валидный JSON
- теряются `beats`
- теряются `marked objects`
- путаются `первый/второй`
- unsupported actions деградируют в `talk` или пропадают
- synthetic teacher может сам вносить шум в ground truth

## Почему `v6` уже недостаточно

Сильные стороны `v6`:
- хороший schema-level validator
- много realistic chunks
- нормальное покрытие dialogue и бытовых сцен

Ограничения `v6`:
- teacher-generated JSON всё ещё может содержать систематические ошибки
- не хватает graph-first canonical generation
- не хватает stress coverage для hard runtime failures
- train/inference alignment всё ещё неполный
- не хватает отдельного active learning loop по реальным логам

## Что такое `SG v7`

`SG v7` — это не просто новый датасет, а полный автоматический pipeline:
0. runtime/train contract
1. programmatic graph generation
2. source generation/paraphrasing
3. hard augmentation
4. semantic critic
5. strict validation
6. split assembly
7. SFT + optional preference tuning
8. runtime feedback loop

## Ограничения модели `qwen 1.5B`

Pipeline должен учитывать:
- ограниченную capacity на длинную структуру
- склонность к under-parsing
- склонность к шаблонным ответам при uncertainty
- повышенный риск ошибок на optional fields и длинных multi-beat сценах
- чувствительность к train/inference mismatch

Поэтому в `SG v7` обязательно должны быть:
- exact runtime/train contract
- formal complexity budget
- provenance policy для real corrected samples

## Цели качества

Pipeline должен улучшить:
- `marked object recall`
- `beat count accuracy`
- `action recall` на hard actions
- `described_action` precision
- `dangling target rate`
- runtime `fallback rate`

## Не-цели

- не делать универсальную сценовую модель для всех возможных screenplay жанров
- не обучать модель богатой cinematography-разметке любой ценой
- не расширять schema без крайней необходимости
- не увеличивать dataset только ради размера
