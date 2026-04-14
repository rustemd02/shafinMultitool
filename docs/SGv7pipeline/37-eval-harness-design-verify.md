# 37. Eval Harness Design Verify

## Цель

Проверить [36-eval-harness-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/36-eval-harness-design.md) в режиме `design verify` и явно ответить:
- действительно ли дизайн измеряет exact grounding, ordinal fidelity, beat/chronology fidelity и release readiness
- совместим ли дизайн с fixed decisions и runtime/train contract
- готов ли дизайн к `implement` без дополнительных архитектурных решений

Проверка выполнена против:
- [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/12-agent-prompts.md)
- [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md)
- [10-runtime-feedback-loop.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/10-runtime-feedback-loop.md)
- [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
- [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)
- [SceneParserService.swift](/Users/unterlantas/Documents/XCode/shafinMultitool/shafinMultitool/SceneGeneratorModule/Services/SceneParserService.swift)

Дополнительно был использован независимый reviewer-субагент; его findings совпали с локальной проверкой по release gate, runtime-policy mirror и completeness metric contract.

## Вердикт

Текущий дизайн сильный по структуре eval artifacts и coverage critical тематик, но **ещё не готов к реализации**.

Итог: `NOT_READY`.

## Findings

### 1. Release gate расходится с базовым release-контрактом

Серьезность: `critical`

Проблема:
- в [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md) требуется отсутствие деградации по core metrics, улучшение на critical buckets и снижение fallback rate
- в [36-eval-harness-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/36-eval-harness-design.md) Gate 1/3 проверяет только подмножество core metrics и допускает рост `runtime_fallback_rate`

Почему это блокирует implement:
- можно пропустить checkpoint с деградацией `beat_count_accuracy`, `action_recall`, `described_action_precision`
- можно пройти gate без реального improvement на critical buckets

Что исправить:
- синхронизировать release gate с полным core-set из `09`
- вернуть правило `fallback must decrease`
- сделать improvement на critical buckets обязательным release condition

### 2. Gate 2 неоперационален

Серьезность: `high`

Проблема:
- есть пороги по размеру bucket-а, но нет фиксированного списка metric checks и exact delta semantics

Почему это блокирует implement:
- implement-агенту придётся перепроектировать gate logic в коде

Что исправить:
- зафиксировать metric list для Gate 2
- прописать формулу delta
- добавить deterministic small-bucket rule

### 3. Runtime-policy mirror задан декларативно, но без decision matrix

Серьезность: `high`

Проблема:
- в дизайне есть требование повторять смысл runtime policy, но нет исполнимой таблицы решений `accept/merge/reject/fallback`

Почему это блокирует implement:
- высокий риск drift между Python eval harness и поведением runtime

Что исправить:
- добавить versioned decision table с входными сигналами и outcome
- формально зафиксировать mapping в отдельном блоке contract-а

### 4. Provenance real-runtime cases неполный относительно feedback-loop contract

Серьезность: `high`

Проблема:
- case schema не требует `gold_source` и `final_script_source`, хотя они обязательны в [10-runtime-feedback-loop.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/10-runtime-feedback-loop.md)
- отсутствует явный запрет использовать `tier_d_auto_repair_only` как gold для release eval

Почему это блокирует implement:
- возможна оценка на невалидном gold и некорректные release decisions

Что исправить:
- расширить `provenance` обязательными полями feedback-loop
- зафиксировать tier-policy для eval gold eligibility

### 5. Gate 0 покрывает не весь runtime/train contract

Серьезность: `high`

Проблема:
- drift-check есть для prompt/decode snapshot, но не зафиксирован для grammar и normalization policy из [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)

Почему это блокирует implement:
- сравнение baseline/candidate может быть контрактно некорректным при скрытом grammar drift

Что исправить:
- добавить grammar snapshot hash checks
- добавить normalization snapshot checks

### 6. Metric contract местами неполный

Серьезность: `medium`

Проблема:
- `llm_merge_rate` и `llm_reject_rate` не имеют явных формул
- `schema_valid_rate` и `canonical_parse_rate` упомянуты, но не определены как canonical metrics
- описание `chronology_phase_accuracy` использует не полностью операциональную нормализацию и требует явного правила построения predicted phase sequence

Почему это важно:
- разные реализации могут считать разные значения

Что исправить:
- дописать формулы и denominators для всех declared metrics
- зафиксировать deterministic normalization для predicted phase sequence

### 7. Top-3 failure clusters требуются, но кластеризация не формализована

Серьезность: `medium`

Проблема:
- release gate и report требуют cluster-based checks без явной deterministic clusterization policy

Почему это важно:
- release checks будут нереплицируемыми

Что исправить:
- зафиксировать cluster_id schema и mapping к taxonomy из [10-runtime-feedback-loop.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/10-runtime-feedback-loop.md)

### 8. Не задан список `chronology_sensitive_buckets`

Серьезность: `low`

Проблема:
- `action_recall` зависит от chronology-sensitive behavior, но набор buckets для этого режима не материализован

Почему это важно:
- возможен scorer drift в case-level evaluation

Что исправить:
- добавить explicit list `chronology_sensitive_buckets`

## Что уже хорошо

- дизайн явно уходит от syntax-only оценки и вводит semantic fidelity layer
- обязательные bucket metrics покрывают ключевые runtime failure темы
- предусмотрены case-level artifacts, bucket reports и A/B compare артефакты
- есть strong emphasis на prompt/decoding reproducibility и fail-fast на contract drift

## Минимальный набор правок для статуса Ready For Implement

1. Синхронизировать release gate с полным release-контрактом из [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md).
2. Формализовать Gate 2: metric set, delta rule, small-bucket behavior.
3. Добавить deterministic runtime-policy decision matrix для `accept/merge/reject/fallback`.
4. Доработать provenance для runtime eval cases по [10-runtime-feedback-loop.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/10-runtime-feedback-loop.md), включая tier restrictions.
5. Расширить Gate 0 grammar/normalization drift-checks по [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md).
6. Закрыть пробелы в metric definitions и зафиксировать deterministic clusterization policy.

## Итог

Текущий `Prompt 9 / design`:
- покрывает большую часть архитектурных требований Track 9
- но имеет несколько implement-blocking gaps в release semantics и executable metric contract
- **не готов к переходу в `implement` без дополнительного design pass**

Итог `design verify`:
- contradictions found: `yes`
- implementation-blocking gaps found: `yes`
- ready for implementation: `no`
