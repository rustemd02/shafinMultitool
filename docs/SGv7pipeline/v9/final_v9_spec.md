# V9 Final Implementation Spec (Integrator)
Date: 2026-04-30  
Role: Integrator/Senior Architect

## Status
- Current architecture status: **V9-Full implemented (code path)**.
- Operational sign-off status: **conditional**, because live demo evidence must be re-collected after the latest runtime fixes.

## What Was Implemented
- Runtime selector is explicit and deterministic:
  - `v8_hotfix | v9_bridge | v9_full`
  - wired via `scene_generator_v9_runtime_mode` and API in `SceneParserService`.
- Guardrails + fallback:
  - limits on rows/actors/objects/beats,
  - per-chunk wall-clock budget,
  - fallback reason `v9.runtime_budget_exceeded_fallback_v8`.
- V9-Full model-native path:
  - provider event table hook used in runtime,
  - verifier + compiler pipeline retained,
  - patch-retry is patch-only and bounded (`max_retry=1`).
- Removed critical runtime defects:
  - `v8_hotfix` no longer receives V9 guardrail modifications,
  - provider patch ops are not double-applied,
  - retry no longer does full second event-table regenerate.
- Contract alignment hardening:
  - canonical wire key: `rowId`,
  - legacy decode compatibility: `rowID`.
- Eval/reporting hardening:
  - structural metrics are `*_structural_pass_rate`,
  - semantic metrics are gold-based `*_accuracy`,
  - degradation counters added,
  - live-vs-offline gap artifact generation added.

## Gate Matrix (MoE-Based)
Sources:
- [ml_llm_senior_agent](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/v9/moe_artifacts/2026-04-30/ml_llm_senior_agent.md)
- [runtime_architect_agent](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/v9/moe_artifacts/2026-04-30/runtime_architect_agent.md)
- [data_eval_scientist_agent](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/v9/moe_artifacts/2026-04-30/data_eval_scientist_agent.md)
- [swift_ios_runtime_agent](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/v9/moe_artifacts/2026-04-30/swift_ios_runtime_agent.md)
- [reviewer_red_team_agent](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/v9/moe_artifacts/2026-04-30/reviewer_red_team_agent.md)

### contract_gate
- Decision: **PASS (conditional hardening)**
- Rationale:
  - 2+ roles approve contract direction after `rowId` compatibility fix.
  - residual requirement: keep regression coverage to prevent key drift.

### data_gate
- Decision: **PASS**
- Rationale:
  - Data/Eval role confirms split hardening, duplicate ID fail-fast, corruption diversity, and summary separation.

### runtime_gate
- Decision: **PASS**
- Rationale:
  - Runtime + Swift roles confirmed fixes for blocker issues and bounded retry contract in code.

### eval_gate
- Decision: **CONDITIONAL PASS**
- Rationale:
  - Structural/semantic split + degradation counters + gap report are implemented.
  - required follow-up: rerun full benchmark pack after latest runtime fixes and attach outputs.

### demo_gate
- Decision: **CONDITIONAL PASS**
- Rationale:
  - Parity suite scaffolding/tests exist and runtime path is aligned.
  - required follow-up: collect fresh real-app parity evidence package.

## Evidence Collected
- Python V9 tests passed:
  - `python3 -m unittest docs/SGv7pipeline/v9/tests/test_v9_projection.py docs/SGv7pipeline/v9/tests/test_v9_datasets_eval.py`
  - `Ran 8 tests ... OK`.
- iOS build verification attempted:
  - `xcodebuild -project shafinMultitool.xcodeproj ... build`
  - blocked by external dependency (`SnapKit` module missing), unrelated to V9 code changes.

## Remaining Hardening Before Final Demo Freeze
1. Re-run canonical parity suite in live app and attach artifacts.
2. Re-run A/B matrix (`v8_hotfix`, `v9_bridge`, `v9_full`) on same eval pack and attach updated reports.
3. Consider relation reconciliation in `compileToPlan` for stricter semantic consistency between repaired rows and `spatialRelations`.
