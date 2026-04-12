# 15. Runtime Failure Examples

Этот файл нужен как компактный reference-набор реальных failure patterns, которые `SG v7` обязан улучшить.

Цель:
- давать агентам не только стратегию, но и конкретные симптомы
- использовать эти примеры как seed для hard-case generation
- использовать эти примеры как smoke-test после изменений

## Example 1. Beat Collapse + Unsupported Action Loss

### Source

`2 актёра идут навстречу друг другу, останавливаются у компа, первый актер начинает курить сигарету`

### Marked Objects

- `комп`, `type=generic`, `id=object_marked_<SHORTID>`

### What Went Wrong

- LLM вернула только `1 beat`
- потерялась фаза `остановка у объекта` как отдельный beat
- потерялось действие `начинает курить`
- вместо meaningful action появился шаблонный `talk`

### Why This Matters

Это показывает сразу три ключевых слабости:
- beat collapse
- unsupported action loss
- minimal valid JSON fallback

### What Good Output Should Preserve

- 2 actors
- marked object grounding
- separate chronology for movement -> stop near object -> described action
- canonical mapping `курить` -> `described_action`

## Example 2. Marked Object Mention In Morphological Form

### Source

`2 актёра идут навстречу друг другу, останавливаются около ноутбука`

### Failure Pattern

- object mention в косвенной форме
- модель может потерять object grounding
- pipeline может искусственно восстановить объект, но не восстановить правильную semantics beats/actions

### What Good Output Should Preserve

- marked object recall
- `stop/approach` near object
- no object loss despite morphology

## Example 3. Multi-Beat Motion + Role Shift

### Source

`2 актёра идут навстречу друг другу, проходят мимо ноутбука, второй начинает бежать`

### Failure Pattern

- оба актёра получают одинаковые `walk`
- пропадает момент, где второй начинает бежать
- chronology и beat structure упрощаются

### What Good Output Should Preserve

- toward-each-other semantics
- pass-by-object semantics
- later motion escalation for actor_2
- no early rewrite of actor_2 from the first beat without cause

## Example 4. Same-Type Marked Object Ambiguity

### Source

Сцена с двумя размеченными объектами одного `type`, где source явно указывает на один из них.

### Failure Pattern

- downstream matching по `type`
- exact `object_marked_*` identity теряется
- placement идёт к "первому подходящему" marker-у

### What Good Output Should Preserve

- exact marked object id end-to-end
- no fallback to type-only matching if exact marker is known

## Example 5. LLM Acceptability Drift

### Pattern

LLM выдаёт формально валидный, но semantically poor JSON:
- actors есть
- beats есть
- objects почти пустые
- action graph бедный

### Why This Matters

Такие ответы опасны, потому что выглядят приемлемо на schema-level, но ведут к плохому поведению в AR.

### What Good Policy Should Preserve

- reject or merge poor LLM outputs
- prioritize semantic completeness over minimal validity

## How To Use This File

Агентам можно давать этот файл:
- при разработке hard buckets
- при проектировании validators
- при проектировании eval harness
- при формировании release gate

## Future Extension

Со временем этот файл должен стать кратким индексом, а полный runtime failure archive — отдельным JSONL/CSV артефактом.
