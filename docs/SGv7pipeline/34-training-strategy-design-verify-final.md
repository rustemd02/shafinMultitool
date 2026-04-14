# 34. Training Strategy Design Verify Final

## Цель

Повторно проверить [32-training-strategy-playbook.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/32-training-strategy-playbook.md) после исправления замечаний из [33-training-strategy-design-verify.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/33-training-strategy-design-verify.md) и явно ответить:
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
- [33-training-strategy-design-verify.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/33-training-strategy-design-verify.md)

## Findings

Блокирующих findings не обнаружено.

Проверка подтвердила:
- promotion gate теперь синхронизирован с release-critical metrics из [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md)
- для `Phase 2` явно зафиксирован ceiling по `complexity_class=L` и по samples, и по tokens
- activation gate для `Phase 4` теперь numeric и не требует ручной интерпретации
- length-based collapse check в `Phase 1` заменён на baseline-relative threshold
- `Phase 3` reviewed-merge cap теперь согласован с upstream правилом `<= 5%` от `hard`
- `Phase 4` получил обязательный preference-specific eval path
- двухпроходный stability rule теперь формализован через distinct checkpoints и scheduled eval interval

## Verification Notes

### Release Logic Alignment

Design теперь требует, чтобы `eligible` checkpoint:
- не деградировал по `json_valid_rate`
- не деградировал по `marked_object_recall`, `beat_count_accuracy`, `action_recall`, `described_action_precision`
- не деградировал по `exact_marked_object_id_accuracy`, `ordinal_actor_binding_accuracy`, `target_resolution_accuracy`, `chronology_phase_accuracy`
- не ухудшал `llm_accept_rate`, `llm_merge_rate`, `llm_reject_rate`
- не ухудшал `dangling_target_rate` и `runtime_fallback_rate`
- не ухудшал hard runtime prompts по critical bucket metrics

Это делает compare policy совместимой с release semantics, а `phase-complete winner` поверх этого добавляет requirement на реальное улучшение, а не просто отсутствие деградации.

### Complexity Budget Compliance

`Phase 2` теперь фиксирует:
- `complexity_class=L <= 15%` effective epoch samples
- `complexity_class=L <= 15%` train tokens
- явный приоритет token cap при конфликте ceilings

Это закрывает дыру, из-за которой sampler мог бы случайно выйти за complexity budget `1.5B`.

### Preference Tuning Readiness

`Phase 4` теперь gated численно:
- `preference_train >= 1000`
- `preference_val >= 100`
- `preference_test >= 100`
- `quarantined + dropped <= 20%`
- `runtime_failure_reviewed_merge >= 70%` от admitted pairs
- numeric release thresholds из Track 9 уже materialized и лучший `Phase 3` checkpoint их проходит

Из-за этого запуск preference tuning больше не зависит от неформального `close to release gate`.

Дополнительно `Phase 4` теперь имеет исполнимый eval path:
- compare runner обязан прогонять `preference_val` и `preference_test`
- winner определяется только при росте `preference_pair_win_rate`
- `preference_eval.json` фиксирует ranking result отдельно от SFT/runtime reports

### Reviewed Merge Budget Alignment

`Phase 3` больше не конфликтует с Track 7 balancing policy:
- `reviewed_merge_hard` capped at `<= 5%` of hard slice
- добавлен отдельный total-phase cap
- baseline mix больше не раздувает reviewed merge выше upstream hard budget

### Stability Rule

Двухпроходный stability rule теперь операционален:
- compare pass привязан к distinct checkpoint с новым `global_step`
- соседние passes должны быть разделены как минимум одним scheduled eval interval
- одинаковый eval bundle и report schema фиксируют сравнимость

### Implementation Readiness

После правок design даёт implementer-у:
- phase filters
- mix ratios
- explicit caps
- release-compatible compare logic
- numeric `Phase 4` gate
- concrete handoff для `training/build_phase_view.py`, phase configs и compare runner

Для `Track 8` больше не остаётся implement-blocking архитектурных решений.

## Residual Risks

Неблокирующие риски остаются:
- cold-start период с маленьким preference corpus всё ещё потребует отдельного policy, если команда захочет запускать `Phase 4` раньше
- для двух-pass stability rule в `Phase 3` в реализации нужно будет аккуратно зафиксировать, какие compare runs считаются независимыми повторениями
- при реальной эксплуатации может понадобиться отдельный per-origin cap для доминирующих runtime clusters, но это уже tuning detail, а не design gap

Эти риски не блокируют переход к `implement` для `Track 8`.

## Verdict

Текущий `Prompt 8 / design`:
- соответствует ограничениям `1.5B`
- уважает complexity budget
- совместим с release logic
- готов к реализации

Итог `design verify`:
- contradictions found: `no`
- implementation-blocking gaps found: `no`
- ready for implementation: `yes`
