# Integrator/Senior Architect Agent (2026-04-30)

## proposal
- Принять текущую реализацию как `V9-Full implemented` с условным operational sign-off.
- Зафиксировать единый canonical wire contract:
  - `rowId` (encode),
  - `rowID` (legacy decode only).
- Считать runtime path закрытым после трёх исправлений:
  - чистый `v8_hotfix`,
  - patch-only retry в `v9_full`,
  - отсутствие double-apply patch ops.
- Для release/demo freeze требовать до-пакет evidence:
  - live parity suite,
  - A/B matrix (`v8_hotfix` / `v9_bridge` / `v9_full`),
  - refreshed aggregate report.

## risks
- Остаточный риск semantic drift:
  - `compileToPlan` пока использует `originalPlan.spatialRelations` без полного reconciliation с repaired event semantics.
- Остаточный риск false confidence:
  - без live parity evidence нельзя объявлять unconditional demo readiness.
- Инфраструктурный риск:
  - в текущем окружении сборка блокируется внешним `SnapKit` dependency gap.

## required_tests
- Python:
  - `python3 -m unittest docs/SGv9pipeline/v9/tests/test_v9_projection.py docs/SGv9pipeline/v9/tests/test_v9_datasets_eval.py`
- Swift unit (targeted):
  - runtime mode API roundtrip,
  - budget fallback reason emission,
  - fixable-only verifier policy.
- Integration:
  - benchmark rerun + live-vs-offline gap artifact.
- Demo:
  - canonical parity suite with actor/target intent checks.

## open_conflicts
- Reviewer insists on stricter semantic-evidence threshold prior to unconditional PASS.
- Runtime team marks demo gate conditional PASS pending live runs.
- Integrator resolves conflict by setting demo/eval as conditional PASS in final spec.

## gate_votes
- `contract_gate`: **PASS (conditional hardening)**
- `data_gate`: **PASS**
- `runtime_gate`: **PASS**
- `eval_gate`: **CONDITIONAL PASS**
- `demo_gate`: **CONDITIONAL PASS**
