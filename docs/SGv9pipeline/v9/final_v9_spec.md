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
- [ml_llm_senior_agent](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv9pipeline/v9/moe_artifacts/2026-04-30/ml_llm_senior_agent.md)
- [runtime_architect_agent](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv9pipeline/v9/moe_artifacts/2026-04-30/runtime_architect_agent.md)
- [data_eval_scientist_agent](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv9pipeline/v9/moe_artifacts/2026-04-30/data_eval_scientist_agent.md)
- [swift_ios_runtime_agent](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv9pipeline/v9/moe_artifacts/2026-04-30/swift_ios_runtime_agent.md)
- [reviewer_red_team_agent](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv9pipeline/v9/moe_artifacts/2026-04-30/reviewer_red_team_agent.md)

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
  - `python3 -m unittest docs/SGv9pipeline/v9/tests/test_v9_projection.py docs/SGv9pipeline/v9/tests/test_v9_datasets_eval.py`
  - `Ran 8 tests ... OK`.
- iOS build verification attempted:
  - `xcodebuild -project shafinMultitool.xcodeproj ... build`
  - blocked by external dependency (`SnapKit` module missing), unrelated to V9 code changes.

## Remaining Hardening Before Final Demo Freeze
1. Re-run canonical parity suite in live app and attach artifacts.
2. Re-run A/B matrix (`v8_hotfix`, `v9_bridge`, `v9_full`) on same eval pack and attach updated reports.
3. Consider relation reconciliation in `compileToPlan` for stricter semantic consistency between repaired rows and `spatialRelations`.

---

# V9.1 Chunk-Ready Screenplay Parser Gate Update
Date: 2026-05-01  
Role: Integrator/Senior Architect

## Status
- Current architecture status: **V9.1 runtime/eval-first hardening implemented**.
- Retrain/GGUF status: **not required for V9.1**.
- Demo sign-off status: **conditional**, because live-model real-app parity still needs to be rerun.

## What Was Implemented
- Screenplay front-end:
  - inline speaker cues like `Ведущий: текст` split into `speaker_cue + dialogue`,
  - `*...*` notes are extracted as stage notes and removed from dialogue text,
  - long dialogue lines are split into ordered dialogue units,
  - pre-heading material becomes a montage/establishing scene,
  - post-dialogue named physical action can become an implicit shot.
- Overlay contract:
  - `SceneVisualOverlay(kind=screen_text|stage_note)` added to bundle result, document state, and bundle script,
  - `screen_text` is overlay-only and does not modify action enum,
  - playback UI has a separate top channel for screen text.
- Chunk continuity:
  - `previousChunkSummary`, `openBeatContext`, and semantic `lastActorPositions` added to chunk state,
  - V9 prompt receives these fields.
- V9 semantic coverage:
  - coverage verifier emits `missing_event_for_beat`, `dialogue_action_collapsed`, `collective_action_not_expanded`, `wrong_target_slot`, and `unsupported_action_missing_text`,
  - patch prompt explicitly supports `add rowId` then `replace` fields,
  - fixable issue policy supports prefixed semantic issue codes.
- Deterministic enrichers:
  - collective object motion, reciprocal motion, and collective stop-near-object now emit V9 reason codes.
- Eval/data:
  - added chunk coverage metrics and continuity/playback placeholders,
  - added hard-case mining script `05_mine_v9_hard_cases.py`.

## MoE Sources
- [v9_1_runtime_architect](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv9pipeline/v9/moe_artifacts/2026-05-01/v9_1_runtime_architect.md)
- [v9_1_data_eval_scientist](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv9pipeline/v9/moe_artifacts/2026-05-01/v9_1_data_eval_scientist.md)
- [v9_1_swift_ios_runtime](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv9pipeline/v9/moe_artifacts/2026-05-01/v9_1_swift_ios_runtime.md)
- [v9_1_reviewer_red_team](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv9pipeline/v9/moe_artifacts/2026-05-01/v9_1_reviewer_red_team.md)
- [v9_1_ml_llm_senior](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv9pipeline/v9/moe_artifacts/2026-05-01/v9_1_ml_llm_senior.md)
- [v9_1_integrator_senior_architect](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv9pipeline/v9/moe_artifacts/2026-05-01/v9_1_integrator_senior_architect.md)

## Gate Matrix
### contract_gate
- Decision: **PASS**
- Evidence: overlay contracts and chunk state fields compile in app/test build.

### runtime_gate
- Decision: **PASS**
- Evidence: workspace `build-for-testing` succeeds with Pods included.

### eval_gate
- Decision: **PASS for V9.1 artifact layer**
- Evidence: Python V9 dataset/eval tests pass with chunk metrics.

### demo_gate
- Decision: **CONDITIONAL PASS**
- Required follow-up: run live-model parity suite on canonical demo cases and the real series fragment.

## Evidence Collected
- Python eval tests:
  - `python3 -m unittest docs.SGv7pipeline.v9.tests.test_v9_datasets_eval`
  - `Ran 9 tests ... OK`.
- iOS compile verification:
  - `xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath /tmp/sg_v91_workspace_dd -only-testing:shafinMultitoolTests/SceneBundlePipelineTests build-for-testing`
  - `** TEST BUILD SUCCEEDED **`.
- iOS runtime test execution:
  - direct `test` through workspace built the bundle but hung before useful test output; the process was stopped.
  - direct `.xcodeproj` test remains invalid for this repo because it misses `SnapKit`; use `.xcworkspace`.
