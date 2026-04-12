# 17. How To Operate With Codex

Этот документ описывает практический workflow: как запускать новый чат в Codex и как давать агентам правильный контекст.

## Главный принцип

Один чат = одна конкретная задача.

Все SG v7 артефакты нужно держать внутри дерева `docs/SGv7pipeline`.
Если агент создаёт новый markdown-документ, он должен класть его в `docs/SGv7pipeline` или в тематическую подпапку внутри этого каталога, а не рядом в корне репозитория.
Если для трека нужна своя группа файлов, агент должен создать для неё отдельную подпапку внутри `docs/SGv7pipeline`, например:
- `docs/SGv7pipeline/contracts/`
- `docs/SGv7pipeline/patterns/`
- `docs/SGv7pipeline/validators/`
- `docs/SGv7pipeline/cir_contract/`

Правило для агентных deliverables:
- новые `.md` артефакты по SG v7 создавать только внутри `docs/SGv7pipeline/...`
- рядом с ними можно создавать schema/examples/tests/scripts, если они относятся к тому же пакету
- результат обязательно должен быть доступен из существующего индексного документа пакета

Не пытайтесь в одном новом чате одновременно:
- спроектировать весь `SG v7`
- написать код генератора
- переделать training harness
- придумать eval

Гораздо лучше разбивать работу на узкие треки.

## Рекомендуемый Workflow

Базовый безопасный цикл для `SG v7`:
- `design -> design verify -> implement -> implement verify`

Это особенно важно там, где ошибка в проектировании потом дорого переходит в код и датасет.

### Шаг 1. Выберите один трек

Примеры:
- runtime/train contract
- canonical contract
- graph generator design
- augmentation strategy
- validator stack
- eval harness

### Шаг 2. Соберите briefing packet

В новый чат дайте:
- 1 конкретную цель
- 3-6 релевантных документов из `docs/SGv7pipeline`
- 1-5 релевантных исходников
- 1-3 failure examples, если задача связана с quality/runtime
- contract doc, если задача касается prompt/serializer/eval/runtime alignment

### Шаг 3. Ограничьте scope

Сразу напишите:
- какие файлы агент может менять
- что он не должен трогать
- какой именно режим нужен: `design`, `design verify`, `implement` или `implement verify`

### Шаг 4. Зафиксируйте expected output

Примеры:
- `markdown spec`
- `implementation plan`
- `code patch`
- `validator design`
- `prompt pack`

### Шаг 5. Проверяйте результат не "на глаз", а по DoD

Definition of done должна быть в самом prompt.

### Шаг 6. Для критичных задач делайте `design verify` до `implement`

Если задача затрагивает:
- schema
- canonical mapping rules
- runtime/train contract
- validators
- eval metrics
- dataset split policy

то не переходите сразу к коду после `design`.
Сначала сделайте отдельный `design verify`-чат, который проверит дизайн на:
- внутренние противоречия
- несоответствие fixed decisions
- нереализуемые места
- неполный DoD

Только после этого запускайте `implement`.
После реализации делайте отдельный `implement verify`-чат.

## Универсальный стартовый промпт для нового чата

```text
Прочитай и используй как основной контекст:
- docs/SGv7pipeline/README.md
- docs/SGv7pipeline/14-fixed-decisions.md
- docs/SGv7pipeline/16-codebase-entry-points.md
- docs/SGv7pipeline/13-agent-briefing-template.md
- docs/SGv7pipeline/18-runtime-train-contract.md

Проект:
- локальная модель: qwen 1.5B
- домен: Scene Generator JSON parsing
- текущий генератор датасета: generate_dataset_v6.py
- целевое направление: SG v7 graph-first pipeline

Работай только в рамках этой задачи:
<вставь конкретную задачу>

Обязательно прочитай:
<вставь список нужных документов>
<вставь список нужных файлов кода>

Что нужно сделать:
<вставь конкретный список deliverables>

Что не нужно делать:
- не расширяй scope за пределы задачи
- не меняй unrelated code
- не пересматривай fixed decisions без явной необходимости

Ожидаемый результат:
<design doc / patch / review / prompt pack>

Definition of done:
<критерии готовности>
```

## Пример 1. Новый чат для design-задачи

```text
Режим: design

Прочитай:
- docs/SGv7pipeline/README.md
- docs/SGv7pipeline/03-graph-generation.md
- docs/SGv7pipeline/14-fixed-decisions.md
- docs/SGv7pipeline/16-codebase-entry-points.md
- generate_dataset_v6.py

Задача:
Спроектируй deterministic graph generator для SG v7.

Что нужно сделать:
- предложить intermediate graph schema
- предложить module structure
- предложить seed/reproducibility strategy
- предложить graph dedup logic
- составить implementation backlog

Ожидаемый результат:
- markdown design doc

Definition of done:
- инженер может начать реализацию без домысливания
```

## Пример 2. Новый чат для implementation-задачи

```text
Режим: implement

Прочитай:
- docs/SGv7pipeline/05-augmentation.md
- docs/SGv7pipeline/06-validation-and-critics.md
- docs/SGv7pipeline/14-fixed-decisions.md
- generate_dataset_v6.py

Задача:
Реализуй первый черновик morphology/noise augmenter для SG v7.

Файлы, которые можно менять:
- generate_dataset_v6.py
- новые файлы рядом с ним, если это действительно нужно

Что нужно сделать:
- выделить augmentation layer
- добавить morphology transforms для marked objects
- добавить noisy user text transforms
- добавить metadata для каждого transform

Ожидаемый результат:
- code patch
- краткий список проверок

Definition of done:
- augmentation layer можно вызвать отдельно от основной генерации
```

## Пример 3. Новый чат для design-verify задачи

```text
Режим: design verify

Прочитай:
- docs/SGv7pipeline/06-validation-and-critics.md
- docs/SGv7pipeline/15-runtime-failure-examples.md
- design docs по validator stack

Задача:
Проведи design review validator stack для SG v7.

Фокус:
- логические противоречия
- semantic gaps
- false assumptions
- recoverability logic
- готовность к реализации

Ожидаемый результат:
- findings first
- file references
- residual risks
```

## Пример 4. Новый чат для implement-verify задачи

```text
Режим: implement verify

Прочитай:
- docs/SGv7pipeline/06-validation-and-critics.md
- docs/SGv7pipeline/15-runtime-failure-examples.md
- изменённые файлы генератора/валидаторов

Задача:
Проведи implementation review изменений в validator stack для SG v7.

Фокус:
- bugs
- semantic regressions
- false positives / false negatives
- recoverability logic
- соответствие дизайну

Ожидаемый результат:
- findings first
- file references
- residual risks
```

## Пример 5. Новый чат для contract-alignment задачи

```text
Режим: design

Прочитай:
- docs/SGv7pipeline/README.md
- docs/SGv7pipeline/14-fixed-decisions.md
- docs/SGv7pipeline/18-runtime-train-contract.md
- docs/SGv7pipeline/15-runtime-failure-examples.md
- generate_dataset_v6.py
- LLMParserService.swift
- SceneParserService.swift

Задача:
Зафиксируй exact runtime/train contract для SG v7 и найди все места drift между dataset generation и runtime parsing.

Что нужно сделать:
- сравнить prompt structure
- сравнить serializer assumptions
- сравнить grammar/allowed enums
- предложить frozen fixtures
- перечислить mismatch risks

Ожидаемый результат:
- contract audit
- список необходимых изменений

Definition of done:
- понятно, что именно должно быть одинаковым в train и runtime
```

## Что прикладывать к агенту в зависимости от задачи

### Для design

- docs
- 1 главный исходник
- fixed decisions

### Для implementation

- docs
- конкретные исходники
- allowed write scope
- failure examples
- contract doc, если затрагиваются prompt/grammar/serializer

### Для review

- docs
- diff или изменённые файлы
- критерии качества
- указание, это `design verify` или `implement verify`

## Частые ошибки при запуске новых чатов

- давать слишком большой scope
- не прикладывать fixed decisions
- не забывать contract doc для runtime/train alignment задач
- не указывать allowed files
- не давать real failure examples
- не описывать expected output
- просить "сделай всё"

## Рекомендуемая тактика

- сначала design chats
- для критичных треков сразу после них verify-design chats
- сначала contract-alignment chat, если меняется prompt/grammar/serializer
- потом narrow implementation chats
- потом verify-implementation chats
- потом интеграционный чат

## Когда какой цикл использовать

### Предпочтительный цикл

- `design -> design verify -> implement -> implement verify`

Использовать для:
- `runtime/train contract`
- canonical contract
- graph generator
- validator stack
- dataset assembly rules
- eval/release gate

### Упрощённый цикл

- `design -> implement -> implement verify`

Использовать для:
- локальных augmentation tasks
- небольших генераторных utility scripts
- точечных prompt/template refinements без смены contract-а

## If You Want Parallel Work

Параллельно безопасно запускать:
- design по graph generator
- design по validators
- design по eval

Небезопасно одновременно без координации:
- два implementation-чата в один и тот же файл
- redesign schema + implementation training harness в одном проходе
