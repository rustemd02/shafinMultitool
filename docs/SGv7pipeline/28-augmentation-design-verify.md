# 28. Augmentation Design Verify

## Цель

Проверить [27-augmentation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/27-augmentation-design.md) в режиме `design verify` и явно ответить:
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

## Вердикт

Текущий design полезен и почти доведен до implementable состояния, но **еще не готов к реализации без дополнительного design pass**.

Сильные стороны документа:
- граница между safe и risky transforms в целом выбрана правильно
- morphology rules хорошо ограничены whitelist-driven policy и не поощряют "умное" свободное склонение
- ownership финальной semantic validation корректно вынесен в Track 6
- traceability intent и reject taxonomy в целом совпадают с задачами Track 5

Но остаются две implement-blocking gaps и одно заметное schema-level противоречие.

## Findings

### 1. Input contract требует `graph_constraints`, но design не фиксирует, откуда augmentation гарантированно их получает

Серьезность: `high`

Проблема:
- [27-augmentation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/27-augmentation-design.md) делает `graph_constraints` частью минимального input record
- тот же документ допускает, что эти поля "могут быть частично восстановлены из CIR"
- но в recommended API augmentation-модуля нет ни `cir_jsonl`, ни `graph_jsonl`, ни explicit join-step
- upstream Track 4 output contract тоже не обещает записывать `graph_constraints` как persisted поля variant-а

Почему это блокирует реализацию:
- implementer не знает, должен ли `04_noise_and_morphology.py` работать только по source JSONL
- implementer не знает, кто отвечает за materialization `allowed_aliases`, `must_keep_lemmas` и `same_type_marker_conflict`
- без этого нельзя детерминированно строить slots и safe/risky gating

Где видно:
- [27-augmentation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/27-augmentation-design.md)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md)

Что нужно исправить:
- выбрать один вариант и зафиксировать его явно:
- вариант A: Track 4 обязан persist-ить `graph_constraints` в output JSONL
- вариант B: augmentation CLI принимает дополнительный CIR/graph input и сам делает deterministic join
- после выбора нужно обновить и input contract, и public API

### 2. В output schema противоречиво описано, где живет `risk_flags`

Серьезность: `medium`

Проблема:
- example output кладет `risk_flags` внутрь `validation`
- traceable metadata contract отдельно требует top-level поле `risk_flags`

Почему это важно:
- это уже schema-level contradiction внутри одного design-doc
- writer, validator и downstream packager будут по-разному ожидать структуру record-а
- такие расхождения быстро превращаются в silent metadata drift

Где видно:
- output example в [27-augmentation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/27-augmentation-design.md)
- metadata contract в [27-augmentation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/27-augmentation-design.md)

Что нужно исправить:
- выбрать одну canonical схему:
- либо `risk_flags` как top-level field
- либо `risk_flags` только внутри `validation`
- и синхронизировать с output example и writer contract

### 3. Не зафиксирована variant planning policy: сколько augmented variants делать на один parent variant и как ограничивать combinatorial growth

Серьезность: `high`

Проблема:
- design описывает catalog, safety rules и noise budget
- flow допускает "one or more transforms"
- но не фиксирует, сколько augmented variants должен выпускать Track 5 на один parent record
- также не зафиксировано, делаем ли мы:
- один variant на один transform
- один mixed variant по seed
- несколько variants per parent для `core` и `hard`

Почему это блокирует реализацию:
- без variant planning policy невозможно реализовать deterministic planner, не invent-нув product policy
- combinatorial explosion здесь реальный риск, особенно при сочетании morphology + ordinal + punctuation noise
- отсутствие явного cap конфликтует с complexity-budget mindset для `qwen 1.5B`

Где видно:
- [27-augmentation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/27-augmentation-design.md)

Что нужно исправить:
- зафиксировать `max_augmented_variants_per_parent`
- зафиксировать, разрешены ли multi-transform variants в `core`
- зафиксировать deterministic selection policy по seed и difficulty bucket

## Что уже хорошо

- safe/risky boundary в целом совместима с [05-augmentation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/05-augmentation.md)
- design уважает fixed decisions по `marked objects`, `first/second` и `described_action`
- whitelist-driven morphology хорошо защищает от semantic drift
- post-augmentation validation ownership разумно разделен между Track 5 и Track 6

## Минимальный набор правок для статуса Ready For Implement

Перед переходом к `implement` нужно закрыть ровно эти вопросы:

1. Зафиксировать единственный источник `graph_constraints` для augmentation input.
2. Свести output schema к одной canonical форме, особенно по `risk_flags`.
3. Добавить variant planning policy с explicit cap и deterministic selection rules.

## Итог

Текущий `Prompt 5 / design`:
- правильно задает общую архитектуру augmentation layer
- в целом разделяет safe/risky transforms
- не поощряет явный semantic drift
- **еще не готов к реализации без дополнительного design pass**

Итог `design verify`:
- contradictions found: `yes`
- implementation-blocking gaps found: `yes`
- ready for implementation: `no`
