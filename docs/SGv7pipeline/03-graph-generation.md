# 03. Graph Generation

## Цель

Сделать canonical scene graph главным источником истины. JSON не должен рождаться учителем как свободный текст; он должен рождаться программно.

## Что должен уметь graph generator

- создавать 1-3 actors
- создавать 0-2 objects
- создавать 1-3 beats как baseline
- создавать согласованные actions
- создавать валидные target ids
- создавать canonical marked object ids
- учитывать product-specific semantics

## Pattern classes

Минимальный обязательный набор:
- `dialogue_only`
- `dialogue_then_put_down_object`
- `dialogue_then_small_action`
- `enter_then_put_down_object`
- `open_then_pick_up_object`
- `pick_up_then_put_down_object`
- `toward_each_other`
- `toward_each_other_then_stop_near_marked_object`
- `toward_each_other_then_pass_by_marked_object`
- `toward_each_other_then_pass_by_object_then_second_runs`
- `stop_near_marked_object_then_first_described_action`
- `ordinal_first_second`
- `same_type_two_marked_objects`
- `unsupported_action_described_action`

Полная design-спецификация pattern library и target distributions зафиксирована в [20-pattern-library.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/20-pattern-library.md).

## Canonical design rules

### Actors

- ids всегда `actor_1`, `actor_2`, `actor_3`
- типы только из runtime schema
- `name` только когда имя явно нужно pattern-ом
- по умолчанию `name = null`

### Objects

- ids всегда canonical
- если объект размеченный, id должен быть `object_marked_<SHORTID>`
- если не размеченный, `object_1`, `object_2`
- object type должен быть из runtime-allowed set

### Beats

- один semantic phase = один beat
- не дробить каждое микро-действие в отдельный beat
- не сжимать multi-phase сцену в один beat без причины

### Actions

- только разрешённые `action.type`
- unsupported semantics всегда мапить в `described_action`
- все target ids должны существовать
- chronology должна быть детерминированной

## Canonical mappings

### Unsupported actions

Примеры:
- `курит`, `закуривает`, `начинает курить` -> `described_action`
- `кивает` -> `described_action`
- `жестикулирует` -> `described_action`

### Ordinal references

- `первый` -> `actor_1`
- `второй` -> `actor_2`

### Marked objects

- если pattern содержит marked object, id обязателен и стабилен
- same-type markers должны иметь разный `SHORTID`

## Ограничения по сложности

Core graphs:
- actors <= 3
- objects <= 2
- beats <= 3
- actions <= 5

Hard graphs:
- beats = 4 допустимо редко
- same-type marked objects допустимы только в hard bucket

## Что должен выдавать graph generator

Каждая запись:
- валидный `CIR` record, сериализуемый как одна JSONL-строка
- `pattern_name`
- `difficulty_bucket`
- `complexity_class`
- `graph_seed`
- `scene_graph`
- `semantic_tags`

`marked_object_spec` как отдельное top-level поле больше не нужен:
- marked object metadata живёт в `scene_graph.objects[*].marker_binding`
- exact bindings живут в `scene_graph.reference_bindings`

## Complexity Classes

Каждый graph должен получить explicit класс сложности:

### S

- actors <= 2
- objects <= 1
- beats <= 2
- actions <= 3

### M

- actors <= 2
- objects <= 2
- beats <= 3
- actions <= 5

### L

- actors <= 3
- objects <= 2
- beats <= 4
- actions <= 6

Правила:
- `core` должен состоять в основном из `S/M`
- `L` допустим только как редкий hard bucket
- если graph требует больше `L`, он не должен попадать в `SG v7` как стандартный train sample

## Вопросы для отдельного агента

- как описать промежуточный canonical graph schema
- как формально задать pattern library
- как генерировать graph combinations без дублей
- как отсекать слишком похожие графы

Статус:
- canonical graph schema закрыта в [19-canonical-intermediate-representation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/19-canonical-intermediate-representation.md)
- pattern library закрыта в [20-pattern-library.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/20-pattern-library.md)
- implementation design для deterministic graph generator закрыт в [21-graph-generator-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/21-graph-generator-design.md)
- executable implementation lives in [graph_generator/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/graph_generator)
- CLI entrypoint lives in [01_build_pattern_graphs.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/graph_generator/01_build_pattern_graphs.py)
