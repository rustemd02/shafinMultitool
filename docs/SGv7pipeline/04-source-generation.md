# 04. Source Generation

## Цель

Получать естественный русский source text из canonical graph, не ломая его смысл.

## Главный принцип

LLM здесь — paraphraser, а не source of truth для JSON.

## Виды source variants

На один graph рекомендуется генерировать 3-8 вариантов:
- `clean`
- `colloquial`
- `user_short`
- `user_noisy`
- `morphology_stress`
- `ordinal_stress`

## Что должен сохранять source text

- количество actors
- ключевую chronology
- наличие/роль marked object
- ordinal mapping `первый/второй`
- critical action semantics

## Что не должен делать source generator

- добавлять новые события
- придумывать лишние объекты
- заменять unsupported action на другой поддерживаемый action
- вставлять вымышленные диалоги
- терять beats

## Recommended prompt strategy

Prompt должен получать:
- canonical graph summary
- список обязательных semantic constraints
- список запрещённых трансформаций
- целевой style bucket

## Style buckets

### clean

Короткий и прямой русский текст без шумов.

### colloquial

Разговорные названия объектов:
- `комп`
- `ноут`
- `телик`

### user_short

Короткие пользовательские формулировки без литературности.

### user_noisy

- лишние пробелы
- смешение `актер/актёр`
- неполные конструкции

### morphology_stress

Специальные формы:
- `у компа`
- `около ноутбука`
- `возле стола`

## Quality gates

Каждый source variant должен пройти:
- lexical sanity
- semantic critic
- recoverability validator

## Что вынести отдельному агенту

- prompt templates для paraphrasing
- style buckets и target distributions
- dedup strategy для source variants
- запретительные правила для hallucinations
