# 29. Augmentation Design Verify Final

## Цель

Повторно проверить [27-augmentation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/27-augmentation-design.md) после исправления замечаний из [28-augmentation-design-verify.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/28-augmentation-design-verify.md) и явно ответить:
- разделяет ли design safe/risky transforms исполнимо
- не ломает ли design semantics
- пригоден ли design для автоматической валидации
- готов ли design к реализации `04_noise_and_morphology.py`

## Проверка выполнена против

- [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/12-agent-prompts.md)
- [05-augmentation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/05-augmentation.md)
- [06-validation-and-critics.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/06-validation-and-critics.md)
- [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
- [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md)
- [27-augmentation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/27-augmentation-design.md)
- [28-augmentation-design-verify.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/28-augmentation-design-verify.md)

## Findings

Блокирующих findings не обнаружено.

Исправления закрыли три прежние design-дыры:
- источник `graph_constraints` теперь однозначно закреплен за persisted output Track 4, а augmentation больше не делает скрытый join или partial reconstruction
- output schema больше не расходится по `risk_flags`
- variant planning policy теперь задает explicit caps, composition rules и deterministic selection policy

## Verification Notes

### Upstream Contract And Input Materialization

Design теперь однозначно фиксирует integration boundary:
- Track 4 обязан persist-ить `graph_constraints` в accepted source variants
- Track 5 использует только этот persisted block и reject-ит contract violation при его отсутствии
- augmentation CLI не требует дополнительного CIR join

Это делает input contract исполнимым и снимает прежнюю неопределенность для implementer-а.

### Safe Vs Risky Boundary

Design корректно разделяет ownership:
- safe transforms разрешены только при сохранении anchors, ordinal bindings и critical action lemmas
- risky transforms требуют `--enable-risky`, полного `graph_constraints` и downstream semantic validation
- same-type marker ambiguity защищена отдельными ограничениями и reject policy

Такое разделение совместимо с [05-augmentation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/05-augmentation.md) и не конфликтует с Track 6.

### Automatic Validation Readiness

Design пригоден для автоматической валидации, потому что теперь явно зафиксированы:
- structural preconditions
- lexical invariants
- contract reject for missing `graph_constraints`
- canonical placement `risk_flags`
- deterministic planner behavior
- explicit reject taxonomy

Это дает implementer-у достаточный contract для `validate.py`, writer-а и CLI.

### Complexity Control

Variant planner теперь ограничивает growth:
- `core` capped at `1` augmented variant per parent
- `hard` capped at `2`
- `hard --enable-risky` capped at `3`, где risky не больше одного

Это согласуется с complexity-budget mindset для `qwen 1.5B` и убирает необходимость invent-ить sampling policy при реализации.

## Residual Risks

Неблокирующие риски остаются:
- later extension с richer `surface_slots` metadata может потребовать shared contract refinement между Track 4 и Track 5
- risky recipes все еще нужно будет аккуратно подтвердить smoke tests-ами на реальных hard fixtures до включения в train-eligible поток

Эти риски не блокируют переход к `implement`.

## Verdict

Текущий `Prompt 5 / design`:
- исполнимо разделяет safe/risky transforms
- не поощряет semantic drift
- пригоден для автоматической валидации
- готов к реализации `04_noise_and_morphology.py`

Итог `design verify`:
- contradictions found: `no`
- implementation-blocking gaps found: `no`
- ready for implementation: `yes`
