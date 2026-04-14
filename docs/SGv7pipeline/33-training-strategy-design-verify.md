# 33. Training Strategy Design Verify

## Цель

Проверить [32-training-strategy-playbook.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/32-training-strategy-playbook.md) в режиме `design verify` и явно ответить:
- соответствует ли training recipe ограничениям `qwen 1.5B`
- уважает ли design complexity budget
- совместим ли checkpoint selection policy с release logic
- готов ли design к реализации `Track 8`

Проверка выполнена против:
- [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/12-agent-prompts.md)
- [08-training-plan.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/08-training-plan.md)
- [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md)
- [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
- [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)
- [31-dataset-assembly-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/31-dataset-assembly-design.md)

Дополнительно был использован независимый reviewer-субагент для второго мнения; его findings совпали с основными локальными выводами по release gate, `L`-budget и activation criteria для preference tuning.

## Вердикт

Текущий design сильный по общей структуре curriculum и хорошо привязан к уже существующим dataset artifacts, но **ещё не готов к реализации без дополнительного design pass**.

Сильные стороны документа:
- phase-wise curriculum в целом совпадает с [08-training-plan.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/08-training-plan.md)
- design уважает fixed decisions по `graph-first`, canonical JSON и train/runtime contract
- training recipe опирается на реальные артефакты Track 7, а не на абстрактные будущие датасеты
- oversampling policy в целом совместима с complexity-budget mindset для `1.5B`

Но остаются один release-level blocking gap, два implement-level gaps и один заметный неформализованный gate.

## Findings

### 1. Promotion gate слабее release logic и может пропускать чекпоинт, который формально не готов к выпуску

Серьезность: `high`

Проблема:
- в [32-training-strategy-playbook.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/32-training-strategy-playbook.md) checkpoint становится `eligible`, если не деградируют только:
  - `json_valid_rate`
  - `exact_marked_object_id_accuracy`
  - `ordinal_actor_binding_accuracy`
  - `target_resolution_accuracy`
- но [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md) требует более строгий gate:
  - нет деградации на core metrics в целом
  - не растёт `dangling_target_rate`
  - падает `runtime_fallback_rate`
  - hard runtime prompts не ухудшаются
  - улучшаются critical buckets

Почему это блокирует реализацию:
- implementer Track 8 не сможет детерминированно выбрать победивший checkpoint по правилам, согласованным с release logic
- текущий recipe допускает ситуацию, где checkpoint проходит internal promotion, но не проходит release semantics пакета

Что нужно исправить:
- поднять missing release-critical metrics из tie-breaker в hard promotion gate
- явно зафиксировать, какие метрики обязательны для phase promotion, а какие используются только для ranking между уже допустимыми checkpoints

### 2. Для `Phase 2` не зафиксирован явный cap на `complexity_class=L`

Серьезность: `high`

Проблема:
- [08-training-plan.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/08-training-plan.md) явно задаёт для `Phase 2` правило: `L` не более `10-15%`
- в [32-training-strategy-playbook.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/32-training-strategy-playbook.md) для `Phase 2` есть token-level budget и oversampling guidance, но нет явного hard cap на долю `L`
- понижающий multiplier для `complexity_class=L` появляется только в общей weighting table и не гарантирует реальный ceiling

Почему это блокирует реализацию:
- sampler можно реализовать по-разному и случайно выйти за complexity budget для `1.5B`
- implementer будет вынужден сам придумать policy, хотя Prompt 8 требует recipe без домысливания

Что нужно исправить:
- зафиксировать в `Phase 2` явный cap на долю `L` samples или tokens
- указать, ceiling считается по rows, по tokens или по обоим измерениям

### 3. Activation gate для preference tuning всё ещё частично субъективен

Серьезность: `medium`

Проблема:
- документ говорит `minimum 1000 train pairs либо другой заранее утверждённый lower bound`
- там же используется формулировка `baseline SFT checkpoint ... проходит release gate либо близок к нему`
- обе формулировки не дают implementer-у исполнимого численного правила

Почему это важно:
- Trigger для `Phase 4` останется зависимым от ручной интерпретации
- разные агенты или инженеры смогут запускать preference tuning по разным критериям и получать несопоставимые results

Что нужно исправить:
- выбрать один numeric lower bound по числу train pairs
- заменить `близок к release gate` на явный threshold set по ключевым метрикам или на бинарное правило `passed/not passed`

### 4. В `Phase 1` collapse-check сформулирован неоперационально

Серьезность: `low`

Проблема:
- gate использует формулировку `average_target_length не падает так, чтобы это указывало на collapse`
- это полезная intuition, но не machine-checkable критерий

Почему это важно:
- policy становится неоднозначной в automation
- implementer может выбрать разные эвристики и получить разные decisions на одинаковых runs

Что нужно исправить:
- заменить формулировку на concrete baseline-relative threshold
- либо убрать её из mandatory gate и оставить как warning-only indicator

## Что уже хорошо

- phase decomposition `Phase 1 -> Phase 2 -> Phase 3 -> Phase 4` соответствует базовому curriculum из [08-training-plan.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/08-training-plan.md)
- design правильно запрещает раннее смешивание `preference_*` с SFT и не делает preference tuning частью базового path
- `tier_c_reviewed_merge` допущен только поздно и под cap, что совпадает с provenance policy из [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
- training views строятся поверх Track 7 artifacts и тем самым уважают leakage boundary из [31-dataset-assembly-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/31-dataset-assembly-design.md)
- contract drift risk распознан явно и mitigated через reuse готовых `messages`

## Минимальный набор правок для статуса Ready For Implement

Перед переходом к `implement` нужно закрыть ровно эти вопросы:

1. Синхронизировать checkpoint promotion gate с release logic из [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md).
2. Добавить явный `Phase 2` cap для `complexity_class=L`.
3. Зафиксировать numeric activation rule для `Phase 4 preference tuning`.
4. Формализовать либо удалить субъективный length-based collapse check в `Phase 1`.

## Residual Risks

Неблокирующие риски остаются даже после этих правок:
- понадобится аккуратно определить, считается ли cap по `L` в samples, в tokens или в обоих измерениях
- для двух-pass stability rule в `Phase 3` нужно будет отдельно описать, какие compare runs считаются независимыми повторениями
- при небольшой initial preference corpus может понадобиться отдельный policy для cold-start периода, но это уже можно решать без перепроектирования всего Track 8

Эти риски не мешают переходу к `implement`, если blocking gaps выше будут закрыты.

## Итог

Текущий `Prompt 8 / design`:
- в целом соответствует ограничениям `1.5B`
- правильно использует Track 7 artifacts как source of truth для training views
- частично покрывает release logic, но пока не доводит его до исполнимого hard gate
- **ещё не готов к реализации без дополнительного design pass**

Итог `design verify`:
- contradictions found: `yes`
- implementation-blocking gaps found: `yes`
- ready for implementation: `no`
