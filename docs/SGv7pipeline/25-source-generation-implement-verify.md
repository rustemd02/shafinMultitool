# 25. Source Generation Implement Verify

## Цель

Проверить реализацию Track 4 против:
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md)
- [24-source-generation-design-verify.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/24-source-generation-design-verify.md)
- [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/12-agent-prompts.md)

## Статус

Этот документ фиксирует findings для предыдущей ревизии реализации.

После него реализация была обновлена, чтобы:
- сделать ordinal requirements conditional по recoverability, а не unconditional
- добавить morphology-specific smoke coverage
- убрать искусственное принуждение named-dialogue fixture к ordinal wording

Для актуального итогового verdict смотри новый implement verify артефакт.

Фокус проверки:
- chronology
- marked objects
- ordinal references
- reject policy ownership
- smoke-test coverage

## Проверенные артефакты

- implementation package: [source_generation/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation)
- CLI: [02_generate_source_variants.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation/02_generate_source_variants.py)
- tests: [tests/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation/tests)

Проверка включала:
- code audit
- запуск `python3 -m unittest discover docs/SGv7pipeline/source_generation/tests -v`
- spot-check dialogue fixture against current cheap-filter policy

## Findings

### 1. Ordinal anchors сейчас требуются для любого graph с `ordinal_map`, даже когда recoverability уже обеспечивается другими surface cues

Серьёзность: `high`

Проблема:
- `extract_required_surface_anchors()` всегда превращает весь `ordinal_map` в обязательные surface tokens
- `evaluate_candidate_text()` затем требует наличие всех этих ordinal tokens в каждом accepted source variant
- это делает `первый/второй/третий` обязательными не только для truly ordinal-sensitive graphs, но и для диалоговых / named-actor cases, где binding уже recoverable через имена или exact dialogue

Почему это важно:
- design фиксирует более узкое правило: ordinals нужно сохранять, когда они нужны для recoverability, а не всегда
- текущая реализация системно толкает dataset к неестественным ordinal-heavy prompts
- для коротких диалоговых сцен это может подавлять более естественные colloquial/user-short forms и искажать train distribution

Где видно:
- [prompt_builder.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation/prompt_builder.py#L268)
- [prompt_builder.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation/prompt_builder.py#L399)
- [filters.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation/filters.py#L52)
- design requirement: [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L268)

Что нужно исправить:
- сделать required ordinals conditional, а не unconditional
- например, выводить `required_ordinal_tokens` только если:
- graph не имеет более сильных identity cues
- `must_preserve` или disambiguation policy явно требует ordinal anchor
- validator contract для данного pattern действительно опирается на ordinal wording

### 2. Smoke coverage не проверяет morphology-around-marked-object case, хотя это обязательный фокус и явный smoke requirement design-а

Серьёзность: `medium`

Проблема:
- smoke suite гоняет только три fixtures: described-action near marked object, pass-by/object/final-run и same-type markers
- morphology-specific graph input не тестируется
- это оставляет без automated coverage один из наиболее рискованных failure modes из Prompt 4

Почему это важно:
- special focus Prompt 4 прямо включает morphology around marked objects
- design handoff требует smoke test для graph с marked object в morphology form
- текущий suite не защитит от регрессии в alias/morphology surface checks

Где видно:
- [test_source_generator_cli.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/source_generation/tests/test_source_generator_cli.py#L20)
- design requirement: [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L696)
- Prompt 4 focus: [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/12-agent-prompts.md#L252)

Что нужно исправить:
- добавить morphology-stress fixture в smoke suite
- как минимум проверить, что accepted variant сохраняет marked-object grounding на косвенной форме вроде `у компа` / `около ноутбука`

## Что уже хорошо

- package/CLI реально существуют и исполняются
- Track 4 / Track 6 reject ownership в коде в целом совпадает с design
- same-type disambiguation checks реализованы
- tests зелёные и покрывают базовый path `clean/colloquial/user_short`
- accepted records содержат traceable metadata и `needs_semantic_critic=true`

## Verdict

Итог `implement verify`:
- implementation exists: `yes`
- prompt templates / batching / metadata / reject filters present: `yes`
- fully aligned with design and DoD: `not yet`

Текущее состояние:
- реализация близка к целевому состоянию
- но есть `2` заметных расхождения, одно из которых затрагивает actual data shape, а не только tests
