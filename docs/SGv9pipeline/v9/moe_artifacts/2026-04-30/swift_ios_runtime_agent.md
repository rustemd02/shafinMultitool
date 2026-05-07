# Swift/iOS Runtime Agent — V9-Full Audit (re-check, 2026-04-30)

## proposal
- Re-check подтверждает, что три критичных runtime-фикса действительно применены:
  - `rowId/rowID` совместимость добавлена на уровне `Codable` + grammar + decode-normalization.
  - `v8_hotfix` больше не загрязняется V9 guardrails (guardrails применяются только при `runtimeMode != .v8Hotfix`).
  - `applyV9Full` перешёл на patch-retry через `generateEventPatchOps(...)`, без второго `generateEventTable(...)`, и без double-apply provider patch ops.
- С текущим состоянием runtime-путь согласуется с V9-Full контрактом заметно лучше, чем в предыдущем аудите.

## risks
- Blocker-level рисков по ранее найденным 3 пунктам больше не вижу.
- Остаются неблокирующие runtime-риски:
  - retry сейчас получает `verifierIssues` как reason-code набор (а не детальные row-level diagnostics), из-за чего patch-качество может быть ниже на сложных кейсах.
  - в `applyV9Full` после `retryClamp` reason codes clamp-этапа не добавляются в агрегат (диагностическая неполнота, не функциональный блокер).
  - для release-signoff всё ещё нужен отдельный live parity прогон (runtime корректность ≠ подтверждённая продуктовая стабильность).

## required_tests
- Unit (обязательные для закрытия runtime части):
  - `SceneV9EventTable.EventRow` и `SceneV9PatchOps.PatchOp` корректно декодируют и `rowId`, и `rowID`.
  - `v8_hotfix` путь не добавляет `v9.max_*_guardrail_applied` при эквивалентном входе.
  - `v9_full` retry использует `generateEventPatchOps`, а не повторный `generateEventTable`.
  - provider `patchOps` не применяется второй раз в pipeline.
- Integration:
  - parity matrix: `v8_hotfix vs v9_bridge vs v9_full` на одном eval-pack.
  - стресс на длинных multi-beat input с проверкой `v9.runtime_budget_exceeded_fallback_v8`.
- Demo/Live:
  - parity suite на канонических сценариях с проверкой actor-target intent на playback.

## open_conflicts
- MoE-level conflict закрыт частично: runtime теперь patch-driven, но качество patch зависит от granularity verifier input (codes vs row-level issues).
- Gate-конфликт остаётся только на evidence-уровне: нужны свежие benchmark/live отчёты после этих фиксов.

## gate_vote
- `runtime_gate`: **PASS** (fixes verified in code).
- `eval_gate`: **CONDITIONAL PASS** (runtime prerequisites закрыты; нужен rerun метрик после фиксов).
- `demo_gate`: **CONDITIONAL PASS** (архитектурно ок; требуется live parity evidence на канонических playback кейсах).
