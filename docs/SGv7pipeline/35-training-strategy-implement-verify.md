# 35. Training Strategy Implement Verify

## Цель

Проверить текущую реализацию Track 8 (`training harness`) против:
- [32-training-strategy-playbook.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/32-training-strategy-playbook.md)
- [34-training-strategy-design-verify-final.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/34-training-strategy-design-verify-final.md)
- DoD `Prompt 8 / implement verify` из [12-agent-prompts.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/12-agent-prompts.md)

Реализация проверена по артефактам:
- [training/phase_view.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/phase_view.py)
- [training/checkpoint_compare.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/checkpoint_compare.py)
- [training/experiment_registry.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/experiment_registry.py)
- [training/config.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/config.py)
- [training/tests/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/tests)

Дополнительно был использован reviewer-субагент для независимого audit pass; findings ниже подтверждены обоими проходами.

## Findings

### Medium

1. `real_corrected_strict` пока не проверяет explicit runtime provenance.

Где:
- [phase_view.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/phase_view.py:72)

Проблема:
- `_is_real_corrected_strict` допускает `tier_a_human_gold` и fallback через `promoted_from_manual_review`, но не требует явного runtime-origin поля.

Почему это важно:
- по policy для данного пула нужен трассируемый runtime source; иначе strict-пул может включать неточно происхождённые записи.

Рекомендация:
- в `packaging_metadata` фиксировать явный provenance/origin и делать фильтр `real_corrected_strict` зависимым от него.

2. `Phase 4` corpus thresholds объявлены, но не enforce-ятся на этапе materialization.

Где:
- [phase_view.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/phase_view.py:333)
- [config.py](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/training/config.py:23)

Проблема:
- конфиг содержит `phase4_min_preference_*`, но `build_phase_view` просто materialize-ит preference train set и не блокирует запуск при недостаточном объёме/качестве корпуса.

Почему это важно:
- optional preference tuning может стартовать на слабом корпусе, что противоречит phase-entry policy в playbook.

Рекомендация:
- добавить preflight validator для `phase4_preference`, который читает preference manifest/counts и валидирует entry thresholds до materialization/compare.

## Проверка тестов

Локально выполнено:

```bash
python3 -m unittest docs/SGv7pipeline/training/tests/test_phase_view.py docs/SGv7pipeline/training/tests/test_checkpoint_compare.py docs/SGv7pipeline/training/tests/test_experiment_registry.py
```

Результат: `OK (9 tests)`.

Тесты подтверждают корректность текущих compare/phase-view изменений, но пока не покрывают:
- provenance-gate для `real_corrected_strict`
- preflight блокировку `phase4_preference` по corpus thresholds.

## Verdict

Итог `implement verify`:
- contradictions/design-implementation drift found: `yes` (2 medium gaps)
- implementation-blocking gaps found: `no`
- ready for implement verify acceptance: `conditionally yes` (после закрытия двух medium пунктов — `yes`)

## Residual Risks

Неблокирующие остаточные риски:
- без explicit runtime provenance возможен drift в составе strict real-corrected пула
- без phase4 preflight checks возможны нестабильные preference-эксперименты на недостаточном корпусе
- frozen eval bundle/report schema пока предполагаются процессно и не зафиксированы отдельным machine-readable полем compare-артефактов.
