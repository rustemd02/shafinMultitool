# 23. Source Generation Design Review

## Цель

Проверить [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md) в режиме `design verify` и явно ответить:
- есть ли противоречия
- есть ли пробелы, блокирующие реализацию
- готов ли дизайн `Prompt 4` к реализации

## Статус

Этот review фиксирует замечания к предыдущей ревизии [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md).

После него design-doc был обновлён, чтобы:
- развести ownership между Track 4 и Track 5
- назначить owner-а для semantic hard reject
- добавить same-type marker disambiguation policy
- зафиксировать persisted source-text normalization policy

Для нового итогового verdict нужен отдельный повторный `design verify`, но этот документ остаётся полезным как исторический список найденных рисков.

Проверка выполнена против:
- [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/12-agent-prompts.md)
- [04-source-generation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/04-source-generation.md)
- [05-augmentation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/05-augmentation.md)
- [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
- [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)

## Вердикт

Текущий design **не готов к реализации без дополнительных решений**.

Основа у документа сильная:
- есть ясный prompt pack
- есть style buckets
- есть variant count policy
- есть quality checklist

Но в текущем виде остаются несколько design-level дыр, из-за которых инженер всё ещё будет вынужден самостоятельно принимать важные архитектурные решения по границе ответственности, reject ownership и disambiguation policy.

## Findings

### 1. Track 4 повторно забирает на себя часть Track 5, хотя сам документ и `05-augmentation.md` требуют обратного

Серьёзность: `high`

Проблема:
- design summary говорит, что risky morphology/noise variation должна уходить в Track 5
- rationale section тоже утверждает, что unsafe variation надо выносить в augmentation
- при этом variant policy в Track 4 всё равно делает `user_noisy`, `morphology_stress` и `ordinal_stress` штатными outputs source generator-а

Почему это важно:
- [05-augmentation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/05-augmentation.md) прямо фиксирует, что шум и морфология лучше делать после clean/colloquial source, иначе хуже контролируется recoverability
- реализация не поймёт, какие hard buckets принадлежат base paraphrase layer, а какие augmentation layer
- появится дублирование логики между `02_generate_source_variants.py` и будущим augmentation модулем

Где видно:
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L48)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L83)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L355)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L365)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L375)
- [05-augmentation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/05-augmentation.md#L7)

Что нужно исправить:
- либо оставить в Track 4 только `clean`, `colloquial`, `user_short`
- либо явно объявить, что `morphology_stress`, `ordinal_stress`, `user_noisy` в первой версии принадлежат Track 4, а Track 5 занимается только post-generation transforms другого типа
- граница должна быть одна и недвусмысленная

### 2. Hard reject taxonomy описана как обязательная, но в дизайне нет исполнимого механизма, кто именно её применяет

Серьёзность: `high`

Проблема:
- hard reject включает semantic claims: новая причина действия, потеря chronology, потеря marked object, semantic replacement unsupported action
- но конкретные pre-critic checks покрывают только cheap lexical heuristics
- design summary отправляет semantic critic downstream, а не в `02_generate_source_variants.py`

Почему это важно:
- инженер по реализации всё ещё не знает, должен ли source generator сам вызывать critic/validator до acceptance
- без этого hard reject rules останутся только prose-обещанием
- это нарушает definition of done Prompt 4, потому что reject policy формально перечислена, но не сделана исполнимой

Где видно:
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L57)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L450)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L476)
- [06-validation-and-critics.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/06-validation-and-critics.md#L31)

Что нужно исправить:
- выбрать один из двух вариантов:
- вариант A: `02_generate_source_variants.py` включает semantic critic в acceptance loop и именно он применяет hard rejects
- вариант B: source generator делает только lexical/format reject, а semantic hard reject официально принадлежит Track 6
- после выбора нужно переписать terminology так, чтобы ownership reject policy был однозначным

### 3. Same-type marked object disambiguation остаётся недоопределённой, хотя это один из зафиксированных failure cases

Серьёзность: `medium`

Проблема:
- документ запрещает заменять same-type markers общим словом
- document показывает `preferred_aliases` и `morphology_examples`
- но не определяет, как prompt-builder заставляет модель различать два размеченных объекта одного типа, если alias-ы пересекаются или один referent должен быть сохранён точно

Почему это важно:
- [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md) фиксирует exact marker identity loss как отдельный failure pattern
- [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md) требует различать same-type marked objects по exact id, а не только по type
- без explicit wording policy source generation может снова сделать ambiguous text, который потом уже не recoverable для `qwen 1.5B`

Где видно:
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L289)
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L431)
- [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md#L78)
- [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md#L95)

Что нужно исправить:
- добавить explicit disambiguation policy для случаев с 2+ marked objects одного типа
- зафиксировать, когда source обязан использовать alias, уточняющий атрибут или relative cue
- добавить отдельный smoke test и reject reason для `same_type_marker_disambiguation_loss`

### 4. Для сохраняемого `source_text` не зафиксирована policy нормализации, хотя runtime/train contract требует единых правил

Серьёзность: `medium`

Проблема:
- документ определяет нормализацию только для dedup key
- но не определяет, в каком виде accepted `source_text` хранится в dataset artifacts
- это особенно критично при `user_noisy`, где часть шума может быть бессмысленно уничтожена или, наоборот, попасть в train вопреки runtime normalization

Почему это важно:
- [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md) требует единой normalization policy до подачи текста в модель
- если source generator сохранит один формат, а training/runtime preprocessing будет применять другой, появится drift

Где видно:
- [22-source-generation-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/22-source-generation-design.md#L510)
- [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md#L143)

Что нужно исправить:
- добавить `source_text_normalization_policy`
- отдельно зафиксировать:
- что хранится в accepted JSONL
- что нормализуется только для dedup
- какой шум разрешён как train artifact, а какой существует только как transient generation noise

## Что уже хорошо

- prompt contract достаточно конкретен для template implementation
- variant count policy в целом совместима с [04-source-generation.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/04-source-generation.md)
- anti-hallucination intent правильный и хорошо согласуется с runtime failure examples
- implementation handoff уже почти доведён до исполнимого состояния

## Минимальный набор правок для статуса Ready For Implement

Перед переходом к `implement` нужно закрыть ровно эти вопросы:

1. Явно развести responsibilities между Track 4 и Track 5.
2. Назначить owner-а для semantic hard reject:
   - либо Track 4
   - либо Track 6.
3. Добавить explicit policy для same-type marked object disambiguation.
4. Зафиксировать persisted source-text normalization policy.

После этого design можно считать готовым к реализации.

## Итог

Текущий `Prompt 4 / design`:
- хорошо продвинут
- полезен как foundation
- **ещё не готов к implement без дополнительного design pass**

То есть вердикт `design verify`:
- contradictions found: `yes`
- implementation-blocking gaps found: `yes`
- ready for implementation: `no`
