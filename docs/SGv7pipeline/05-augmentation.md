# 05. Augmentation

## Цель

Добавить трудные пользовательские формы, не разрушая target graph.

## Почему augmentation нужен отдельно

Если шум и морфология делаются прямо на этапе source generation, сложнее контролировать recoverability. Лучше сначала получить clean/colloquial text, а потом применять controlled transformations.

## Типы augmentation

### 1. Morphology augmentation

Примеры:
- `комп` -> `компа`, `компу`, `компом`
- `ноутбук` -> `ноутбука`
- `около X`, `у X`, `возле X`, `рядом с X`

### 2. Orthography variation

- `актер` / `актёр`
- `еще` / `ещё`

### 3. User noise

- двойные пробелы
- trailing spaces
- отсутствие точки
- короткие телеграфные конструкции

### 4. Lexical alternation

- `идут навстречу` / `идут друг к другу`
- `останавливаются у` / `замирают возле`

### 5. Ordinal stress

- `первый актер`
- `первый актёр`
- `первый`
- `второй`

## Что нельзя аугментировать

- ids в target JSON
- chronology beats
- critical semantic anchors
- required object grounding

## Hard buckets, которые должны появиться

- `marked_object_morphology`
- `ordinal_reference_noise`
- `same_type_marker_disambiguation`
- `unsupported_action_user_wording`
- `beat_count_fragility`

## Автопроверки после augmentation

- source всё ещё выражает исходный graph
- mention marker сохраняется
- ordinal reference не потеряна
- critical action не заменена на другой смысл

## Что вынести отдельному агенту

- morphology rule library
- noisy user text transformations
- augmentation safety checks
- target distribution по augmentation types
