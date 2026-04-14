# 32. Training Strategy Playbook

## Цель

Зафиксировать исполнимый training recipe для `qwen 1.5B` в `SG v7`, чтобы инженер мог:
- воспроизводимо запускать `phase1 -> phase2 -> phase3`
- сравнивать checkpoints по одним и тем же frozen eval-наборам
- контролировать hard-case oversampling без leakage и без contract drift
- принимать решение, когда нужен `preference tuning`, а когда сначала надо чинить данные или SFT

Этот документ закрывает design-часть `Track 8` из [11-implementation-backlog.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/11-implementation-backlog.md).

## Scope

Track 8 отвечает за:
- phase-wise SFT curriculum поверх уже собранных `SG v7` artifacts
- oversampling policy по `difficulty_bucket`, `critical_eval_tags` и provenance tiers
- reproducible checkpoint selection policy
- decision policy для optional preference tuning
- experiment manifests и ablation matrix

Track 8 не отвечает за:
- изменение runtime/train contract
- пересборку `train/val/test` splits
- переопределение eval metrics или release gate semantics
- repair target JSON вне уже утверждённого dataset pipeline

## Исходные зависимости

Training harness обязан опираться на уже зафиксированные source-of-truth артефакты:

- общий индекс пакета: [README.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/README.md)
- базовый training plan: [08-training-plan.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/08-training-plan.md)
- eval и release semantics: [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md)
- fixed decisions: [14-fixed-decisions.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/14-fixed-decisions.md)
- runtime failure seeds: [15-runtime-failure-examples.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/15-runtime-failure-examples.md)
- runtime/train contract: [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)
- dataset assembly design: [31-dataset-assembly-design.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/31-dataset-assembly-design.md)
- dataset builder package: [dataset_builder/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/dataset_builder)
- dataset builder CLI: [06_build_dataset_splits.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/dataset_builder/06_build_dataset_splits.py)

## Design Summary

Ключевые решения:
- все training phases используют один и тот же immutable dataset build из Track 7; phase-views materialize-ятся фильтрацией и weighted sampling, а не пересборкой splits
- `sft_val.jsonl` и `sft_test.jsonl` остаются frozen для всех SFT phases; их нельзя подменять "под фазу"
- `preference_*` artifacts не смешиваются с SFT раньше явного decision gate
- hard oversampling делается через sampler weights и phase manifests, а не через бесконтрольное дублирование строк в основном train JSONL
- выбор checkpoint-а происходит только после единообразного compare pass на synthetic held-out, hard held-out и real runtime eval
- если phase ухудшает `core` exact grounding, следующий phase запускать нельзя даже при росте hard metrics

## Input Artifacts

Минимальный набор входов для Track 8:

- `sft_train.jsonl`
- `sft_val.jsonl`
- `sft_test.jsonl`
- `split_manifest.json`
- `leakage_report.json`
- `preference_train.jsonl`
- `preference_val.jsonl`
- `preference_test.jsonl`
- `preference_manifest.json`
- frozen eval prompt sets и baseline metrics из Track 9

Track 8 должен валидировать перед стартом:
- `leakage_report.json` не содержит violations
- `contract_versions_present` в `split_manifest.json` состоит ровно из одного ожидаемого `contract_version`
- `preference_manifest.json` не содержит аномально высокий quarantine/drop rate
- `sft_*` messages уже совпадают с runtime/train contract section order из [18-runtime-train-contract.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/18-runtime-train-contract.md)

## Канонические Training Views

Track 7 уже materialize-ит packaging metadata, достаточную для phase filtering:
- `difficulty_bucket`
- `complexity_class`
- `train_eligibility`
- `correction_tier`
- `critical_eval_tags`
- `source_text_token_count`
- `target_json_token_count`
- `full_sequence_token_count`
- `recoverability_score`

Track 8 не должен заново изобретать семантические buckets. Он строит phase views поверх этих полей.

### Frozen Evaluation Sets

Для всех phases:
- основной regression gate: `sft_val.jsonl`
- финальный SFT compare: `sft_test.jsonl`
- runtime/generalization gate: frozen real runtime eval set из Track 9
- preference eval: `preference_val.jsonl` и `preference_test.jsonl`, но только если phase дошёл до preference tuning

Для `Phase 4` preference eval не является optional side report.
Track 8 обязан materialize-ить отдельный preference report по `preference_val/test`, иначе compare pass для `Phase 4` считается неполным.

### Training Pools

Training harness должен сначала materialize-ить четыре логических пула:

| Pool | Что входит | Правило допуска |
| --- | --- | --- |
| `core_anchor` | простые и средние `core` SFT cases | `difficulty_bucket=core`, `train_eligibility=direct_sft`, `correction_tier in {tier_a_human_gold, tier_b_deterministic_canonical}` |
| `hard_synthetic` | synthetic hard cases | `difficulty_bucket=hard`, `train_eligibility=direct_sft`, `correction_tier in {tier_a_human_gold, tier_b_deterministic_canonical}` |
| `real_corrected_strict` | реальные corrected cases, пригодные как gold | `correction_tier in {tier_a_human_gold, tier_b_deterministic_canonical}` и явный runtime provenance |
| `reviewed_merge_hard` | reviewed merge / promoted hard cases | `train_eligibility=hard_or_preference_only` и `correction_tier=tier_c_reviewed_merge` |

`tier_d_auto_repair_only` не допускается ни в один SFT pool.

### Complexity Gate For Phase Views

Перед sampling Track 8 обязан повторно фильтровать samples по budget metadata:

| View | Обязательные ограничения |
| --- | --- |
| `phase1_core_bootstrap` | `difficulty_bucket=core`, `complexity_class in {S, M}`, `full_sequence_token_count <= 420` |
| `phase2_mixed_sft` | `full_sequence_token_count <= 560`, `reviewed_merge_hard` ещё не включается |
| `phase3_hard_consolidation` | допускаются все hard samples в пределах hard budget; `tier_c_reviewed_merge` только через отдельный cap |
| `phase4_preference` | использует только preference pairs и не меняет сам contract |

Если metadata не хватает для budget-фильтра, build phase view должен завершаться ошибкой, а не молча ослаблять policy.

## Phase Recipe

### Preflight. Baseline Snapshot

До первого training run Track 8 обязан:
- зафиксировать `base checkpoint`
- сохранить hash training config и tokenizer setup
- сохранить frozen eval bundle version
- прогнать baseline metrics без обучения

Артефакты preflight:
- `experiments/baseline/config_snapshot.json`
- `experiments/baseline/eval_summary.json`
- `experiments/baseline/runtime_prompt_contract_ref.txt`

### Phase 1. Core Bootstrap SFT

Цель:
- стабилизировать canonical JSON
- закрепить exact section order
- убрать minimal-valid collapse на простых и средних сценах

Train view:
- только `core_anchor`
- только `complexity_class in {S, M}`
- без `reviewed_merge_hard`
- без preference pairs

Mix policy:
- `core_anchor=100%`

Внутренний reweighting:
- `critical_eval_tags` reweight не выше `1.5x`
- ни один tag не должен занимать больше `20%` effective epoch samples

Checkpoint gate для перехода в `Phase 2`:
- нет деградации `json_valid_rate` на `sft_val`
- нет деградации `beat_count_accuracy`
- нет деградации `action_recall`
- нет деградации `exact_marked_object_id_accuracy`
- нет деградации `ordinal_actor_binding_accuracy`
- нет деградации `target_resolution_accuracy`
- `average_target_length` на structured exact-match subset не падает более чем на `5%` относительно baseline snapshot

### Phase 2. Mixed SFT

Цель:
- ввести `hard` buckets без разрушения core structure
- научить модель выдерживать morphology, ordinals и multi-beat chronology

Train pools:
- `core_anchor`
- `hard_synthetic`
- `real_corrected_strict`

Базовый mix:
- `core_anchor=70%`
- `hard_synthetic=25%`
- `real_corrected_strict=5%`

Caps:
- `complexity_class=L` не выше `15%` effective epoch samples
- `complexity_class=L` не выше `15%` train tokens за epoch
- если оба cap-а конфликтуют, приоритет у token cap

Внутреннее oversampling правило:
- `marked_object_morphology`, `ordinal_cases`, `same_type_markers`, `unsupported_action_cases`, `three_beat_cases` могут усиливаться до `2.0x`
- суммарная доля всех oversampled critical tags не должна превышать `35%` effective epoch samples

Почему Phase 2 ещё не включает `tier_c_reviewed_merge`:
- на этом этапе модель должна сначала научиться держать structure на clean gold
- если рано добавить reviewed merge, `1.5B` начнёт копировать merge-специфичные компромиссы как норму

Checkpoint gate для перехода в `Phase 3`:
- core metrics не хуже лучшего checkpoint из `Phase 1` более чем на `0.5 pp`
- на hard held-out есть рост как минимум в двух bucket-группах из:
  - `marked_object_recall`
  - `exact_marked_object_id_accuracy`
  - `ordinal_actor_binding_accuracy`
  - `target_resolution_accuracy`
  - `chronology_phase_accuracy`
- `dangling_target_rate` не растёт

### Phase 3. Hard Consolidation SFT

Цель:
- добить реальные runtime failure patterns
- добавить reviewed hard data без потери canonical discipline

Train pools:
- `core_anchor`
- `hard_synthetic`
- `real_corrected_strict`
- `reviewed_merge_hard`

Базовый mix:
- `core_anchor=45%`
- `hard_synthetic=45%`
- `real_corrected_strict=8%`
- `reviewed_merge_hard=2%`

Caps:
- `reviewed_merge_hard` не выше `5%` hard slice по samples
- `reviewed_merge_hard` не выше `5%` hard slice по train tokens
- `reviewed_merge_hard` не выше `2%` total phase samples
- любой отдельный `critical_eval_tag` не выше `15%` train tokens
- `complexity_class=L` не выше `15%` effective epoch samples

Admission policy для `reviewed_merge_hard`:
- только records с явным human/tool review следом
- только если same `contract_version`, что и у SFT pools
- только если sample уже прошёл strict validators и попал в Track 7 legal preference/hard bucket

Checkpoint gate для выхода из SFT track:
- hard runtime prompts не деградируют
- `runtime_fallback_rate` падает или хотя бы не растёт
- улучшение на critical buckets устойчиво на двух независимых compare passes подряд

Определение независимого compare pass для `Phase 3`:
- `phase3_eval_interval_steps` фиксируется в phase config и не меняется внутри run; default: `1000` optimizer steps
- compare pass считается независимым только для distinct checkpoint-а с `global_step`, который отличается от предыдущего минимум на `phase3_eval_interval_steps`
- повторный eval того же checkpoint-а (same checkpoint id + same global_step) не считается новым pass
- все compare passes используют один и тот же frozen eval bundle, один и тот же decoding config и один и тот же report schema
- compare pass для `Phase 3` всегда означает checkpoint-level compare event внутри одного training run; это не eval rerun и не full experiment rerun
- compare events упорядочиваются строго по `global_step`; при равенстве `global_step` берётся только один event (первый materialized)

Определение comparator и `same sign improvement` для `Phase 3`:
- reference checkpoint фиксируется один раз на входе в `Phase 3`: `phase3_reference_checkpoint = Phase 2 winner`
- каждый pass сравнивается с одним и тем же `phase3_reference_checkpoint`, а не с "текущим лучшим"
- pass имеет `positive_sign`, если одновременно: нет regressions на release-critical metrics, `runtime_fallback_rate` не хуже reference, и есть improvement >= `0.3 pp` минимум в одном critical bucket metric
- два pass-а считаются `same sign improvement`, только если оба имеют `positive_sign` против одного и того же `phase3_reference_checkpoint`
- phase exit разрешён только после двух последовательных независимых pass-ов с `same sign improvement`

Deterministic rule для phase exit:
1. Идти по compare events в порядке `global_step`.
2. Вести счётчик `consecutive_positive_passes`, старт `0`.
3. Если event `positive_sign=true`, увеличить счётчик на `1`.
4. Если event `positive_sign=false`, сбросить счётчик в `0`.
5. Exit из `Phase 3` разрешён только когда `consecutive_positive_passes == 2`.
6. После получения exit-condition первый из двух pass-ов обязан быть минимум на `phase3_eval_interval_steps` раньше второго.
7. Compare runner обязан materialize для каждого event поля `positive_sign`, `independent_pass` и `consecutive_positive_passes` в `checkpoint_compare.md`; счётчик ведётся только по dedup-очереди после разрешения конфликтов по `global_step`.

### Phase 4. Optional Preference Tuning

Цель:
- уменьшить семантически бедные, но формально валидные ответы
- улучшить ranking между `good_json` и `bad_json`, не ломая syntax stability

Preference tuning можно запускать только если одновременно выполнены условия:
- лучший `Phase 3` checkpoint уже проходит numeric release thresholds из Track 9; если thresholds ещё не materialize-ены, `Phase 4` блокируется
- есть достаточно preference data:
  - `preference_train >= 1000`
  - `preference_val >= 100`
  - `preference_test >= 100`
  - суммарный `quarantined + dropped` rate в `preference_manifest.json` не выше `20%` от всех кандидатов
  - не менее `70%` admitted pairs происходят из `runtime_failure_reviewed_merge`
- лучший `Phase 3` checkpoint уже является phase-complete winner по SFT compare policy и используется как единственная стартовая точка для `Phase 4`

Preference tuning нельзя запускать, если:
- всё ещё есть частые syntax/grammar violations
- core metrics нестабильны между двумя соседними checkpoints
- preference data в основном состоит из слабых auto-repair pairs

Базовый policy:
- стартовать только от лучшего `Phase 3` checkpoint
- использовать меньший learning-rate, чем в SFT
- сравнивать preference-tuned модель не только по preference win-rate, но и по всем SFT/runtime metrics
- откатывать phase, если падают `exact_marked_object_id_accuracy`, `ordinal_actor_binding_accuracy` или `target_resolution_accuracy`

Preference-specific eval path для `Phase 4` обязателен:
- compare runner должен отдельно прогонять `preference_val` и `preference_test`
- обязательная метрика: `preference_pair_win_rate`
- обязательная secondary метрика: `preference_tie_rate`
- `Phase 4` candidate не может стать winner, если `preference_pair_win_rate` не вырос против лучшего `Phase 3` baseline-at-entry хотя бы на `3 pp`
- при этом release-critical SFT/runtime metrics не имеют права деградировать

## Oversampling Strategy

Hard oversampling для `1.5B` должен быть управляемым, а не агрессивным.

Правила:
- oversampling делается sampler weights, а не manual row duplication в canonical train artifacts
- базовая единица балансировки: `graph_family_key`, чтобы не раздувать near-duplicates одной family
- reweight по одному `critical_eval_tag` ограничен сверху
- один sample не должен появляться в epoch непропорционально часто только потому, что у него много tags сразу

Рекомендуемый weighting order:
1. base weight по `difficulty_bucket`
2. multiplier по `critical_eval_tags`
3. penalty для near-max complexity within phase budget
4. optional boost для `real_corrected_strict`

Рекомендуемые стартовые multipliers:

| Сигнал | Multiplier |
| --- | --- |
| `difficulty_bucket=core` в `Phase 1` | `1.0` |
| `difficulty_bucket=hard` в `Phase 2` | `1.6` |
| `difficulty_bucket=hard` в `Phase 3` | `2.0` |
| `real_corrected_strict` | `1.5` |
| `same_type_markers` | `1.4` |
| `marked_object_morphology` | `1.4` |
| `ordinal_cases` | `1.3` |
| `three_beat_cases` | `1.3` |
| `unsupported_action_cases` | `1.2` |
| `complexity_class=L` | max `0.8` unless explicitly targeted |

## Checkpoint Comparison Policy

Checkpoint comparison должен быть одинаковым для всех phases.

### Compare Inputs

Для каждого compare pass запускать:
- synthetic held-out
- hard held-out
- real runtime eval
- bucket reports из [09-eval-and-release.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/09-eval-and-release.md)
- для `Phase 4`: дополнительно `preference_val` и `preference_test` с отдельным ranking report

Все compare runs обязаны использовать:
- одинаковый runtime/train contract version
- одинаковый prompt formatter
- одинаковый decoding config
- одинаковый report schema

### Promotion Logic

Checkpoint считается `eligible` только если:
- нет contract drift
- `json_valid_rate` не деградировал против текущего best-on-track
- `marked_object_recall` не деградировал против текущего best-on-track
- `beat_count_accuracy` не деградировал против текущего best-on-track
- `action_recall` не деградировал против текущего best-on-track
- `described_action_precision` не деградировал против текущего best-on-track
- `exact_marked_object_id_accuracy` не деградировал против текущего best-on-track
- `ordinal_actor_binding_accuracy` не деградировал против текущего best-on-track
- `target_resolution_accuracy` не деградировал против текущего best-on-track
- `chronology_phase_accuracy` не деградировал против текущего best-on-track
- `llm_accept_rate` не деградировал против текущего best-on-track
- `llm_merge_rate` не вырос против текущего best-on-track
- `llm_reject_rate` не вырос против текущего best-on-track
- `dangling_target_rate` не вырос против текущего best-on-track
- `runtime_fallback_rate` не вырос против текущего best-on-track
- hard runtime prompts не ухудшились, то есть нет regression по bucket metrics для:
  - `ordinal_cases`
  - `marked_object_morphology`
  - `same_type_markers`
  - `unsupported_action_cases`
  - `three_beat_cases`
  - `exact_marker_identity_cases`
  - `reviewed_merge_cases`

Checkpoint считается `phase-complete winner` только если он уже `eligible` и дополнительно:
- даёт improvement хотя бы в одном critical bucket без regressions на release-critical metrics
- показывает `runtime_fallback_rate` строго ниже предыдущего phase winner-а или baseline checkpoint-а
- сохраняет `dangling_target_rate` не хуже предыдущего phase winner-а
- на real runtime eval не ухудшает hard prompt outcome summary

Из `eligible` checkpoints выбирать лучший в таком порядке:
1. больше critical buckets без деградации
2. выше средний score по hard/runtime fidelity metrics
3. ниже `runtime_fallback_rate`
4. ниже `dangling_target_rate`
5. меньший рост `average_target_length` при сопоставимом качестве

`train_loss` и `val_loss` не могут быть финальным критерием выбора checkpoint-а без bucket metrics.

### Required Compare Artifacts

После каждого phase должны materialize-иться:
- `checkpoint_table.json`
- `checkpoint_compare.md`
- `bucket_deltas.json`
- `promotion_decision.md`
- для `Phase 4`: `preference_eval.json`

`promotion_decision.md` обязан явно отвечать:
- какой checkpoint выбран
- почему rejected остальные
- нет ли regressions на core exact grounding
- разрешён ли следующий phase

`preference_eval.json` для `Phase 4` обязан явно содержать:
- `preference_pair_win_rate` на `val` и `test`
- `preference_tie_rate` на `val` и `test`
- baseline-at-entry checkpoint id
- delta против baseline-at-entry

## Ablation Plan

Минимальная матрица экспериментов:

| Experiment | Что меняется | Зачем |
| --- | --- | --- |
| `A0_baseline_frozen` | текущий baseline без дообучения | точка отсчёта |
| `A1_phase1_core_only` | только `Phase 1` | проверить bootstrap effect |
| `A2_phase1_core_plus_tag_reweight` | `Phase 1` + мягкий tag reweight | понять, нужен ли ранний emphasis на markers/ordinals |
| `A3_phase2_70_25_5` | базовый `Phase 2` mix | основной кандидат на mixed SFT |
| `A4_phase2_60_30_10` | более агрессивный hard mix | измерить предел без слома core |
| `A5_phase3_45_35_10_10` | базовый `Phase 3` с reviewed hard | основной hard-consolidation кандидат |
| `A6_phase3_without_tier_c` | `Phase 3`, но без `reviewed_merge_hard` | проверить, даёт ли `tier_c` реальную пользу |
| `A7_preference_tuning` | optional preference tuning поверх лучшего SFT | включать только после decision gate |

Правила ablation:
- менять только один фактор за эксперимент
- не пересобирать held-out sets между экспериментами
- все compare reports хранить рядом в единой experiment registry

## Risks

### 1. Hard oversampling ломает core stability

Симптом:
- hard metrics растут, но core exact grounding падает

Mitigation:
- держать `core_anchor` floor в `Phase 2` и `Phase 3`
- блокировать phase promotion при core regression

### 2. Preference tuning лечит ranking, но ломает syntax

Симптом:
- preference win-rate растёт, а `json_valid_rate` или exact ids падают

Mitigation:
- запускать preference tuning только после стабильного SFT
- сравнивать его против полного SFT/runtime eval, а не только pairwise reward

### 3. Reviewed merge становится новой "нормой"

Симптом:
- модель начинает усваивать merge-компромиссы вместо canonical gold discipline

Mitigation:
- ограничить `reviewed_merge_hard` жёстким cap
- не включать `tier_c` раньше `Phase 3`

### 4. Token budget quietly drifts upward

Симптом:
- `average_target_length` и `full_sequence_token_count` растут быстрее метрик

Mitigation:
- phase-level budget filters
- checkpoint tie-break по length growth

### 5. Evaluation noise hides regressions

Симптом:
- один compare pass показывает improvement, следующий нет

Mitigation:
- требовать устойчивость improvement минимум на двух compare passes подряд
- не выбирать checkpoint только по одной aggregated score

### 6. Training harness accidentally diverges from runtime contract

Симптом:
- prompt formatter в training harness отличается по section order или wording

Mitigation:
- training views должны использовать уже упакованные `messages`
- contract drift check запускать до каждого phase

## Implementation Handoff

Инженер Track 8 должен реализовать минимум:
- materializer phase views поверх `sft_train.jsonl` и `preference_train.jsonl`
- phase config schema с mix ratios, pool filters и oversampling caps
- checkpoint compare runner c frozen eval bundle
- experiment registry с config hash, input manifests и promotion decisions
- guardrails на contract version, leakage status и budget metadata presence

Рекомендуемые исполнимые артефакты:
- `training/phase_configs/phase1_core.yaml`
- `training/phase_configs/phase2_mix.yaml`
- `training/phase_configs/phase3_hard.yaml`
- `training/phase_configs/phase4_preference.yaml`
- `training/checkpoint_compare.py`
- `training/build_phase_view.py`
- `training/experiment_registry.py`

Минимальные тесты для будущей реализации:
- phase-view builder не пропускает `tier_d_auto_repair_only`
- `Phase 1` не включает `hard` records
- `Phase 3` respects `reviewed_merge_hard` cap
- compare runner отклоняет checkpoints с contract drift
- experiment registry фиксирует exact input manifests и config hash

## Open Questions

- нужен ли отдельный cold-start policy для периодов, когда runtime feedback corpus ещё не дорос до `1000/100/100` pairs и `Phase 4` по правилам остаётся заблокирован
- нужен ли отдельный short-run smoke phase перед полным `Phase 1`, если base checkpoint сильно отличается от текущего runtime parser behavior
- стоит ли для `real_corrected_strict` вводить отдельный per-origin cap, если один runtime cluster начинает доминировать в hard pool

## Definition Of Done

Design для `Prompt 8` считается готовым, когда:
- можно materialize-ить phase views без дополнительных архитектурных решений
- mix policy, oversampling caps и checkpoint promotion rules описаны явно
- есть исполнимый decision gate для preference tuning
- есть минимальная ablation matrix
- следующий агент видит этот документ из существующих индексных файлов пакета
