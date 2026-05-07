# Runtime Architect Agent (2026-04-30)

## proposal
- Runtime selector is now explicitly implemented in `SceneBundlePipeline` with deterministic modes:
  - `v8_hotfix` (bypass V9 transforms),
  - `v9_bridge` (plan->event->verify->compile),
  - `v9_full` (event-provider hook + verifier + bounded retry + fallback).
- Guardrails are implemented in runtime and service layers:
  - cardinality constraints (`maxRows/maxActors/maxObjects/maxBeats`),
  - per-chunk wall-clock budget with hard fallback to V8 and reason `v9.runtime_budget_exceeded_fallback_v8`,
  - post-guard relation/action cleanup to keep compile safety.
- Reason provenance is standardized and persisted in dual form:
  - canonical reason code,
  - provenance-qualified code: `provider:*`, `v9_verifier:*`, `enricher:*`, `runtime_guardrail:*`.
- Patch-retry contract is effectively `max_retry=1` in `v9_full`:
  - one conditional retry branch only,
  - bounded by verifier-fixable reason set and runtime budget checks.
- Architecture remains migration-safe:
  - `v8_hotfix` path can fully bypass V9,
  - `v9_full` gracefully degrades to bridge behavior when event-provider is unavailable.

## risks
- **V9-Full semantic risk**: `v9_full` still seeds from plan-derived event table before provider override; quality gains remain partly bridge-like until provider consistently returns high-quality native event tables.
- **Retry policy ambiguity**: second `generateEventTable(...)` call is used as retry, but provider contract does not force patch-only delta behavior; different provider implementations may regenerate full tables.
- **Async parity gap**: runtime hook currently uses sync `generateEventTable(...)` in `makeDraft`; async event-provider path is not exercised in the async planner flow.
- **Budget tuning risk**: defaults (`80/120/180ms`) may be too tight for some devices/scenes, causing frequent fallback and hidden quality regression if not monitored.
- **Observability coupling**: provenance codes are emitted, but gate closure depends on eval/report consumers correctly separating structural recovery from semantic fidelity cost.

## required_tests
- **Mode routing**
  - `scene_generator_v9_runtime_mode=v8_hotfix` must bypass V9 transform and emit `runtime_guardrail:v9.runtime_mode_v8_hotfix`.
  - `v9_bridge` must execute deterministic bridge chain and emit `v9_verifier:v9.local_event_table_pipeline`.
  - `v9_full` with missing provider must emit `provider:v9.event_provider_unavailable_fallback_bridge`.
- **Guardrails**
  - Exceeding rows/actors/objects/beats must clamp deterministically and emit corresponding `runtime_guardrail:*` reason codes.
  - Artificially low chunk budget must trigger `v9.runtime_budget_exceeded_fallback_v8` and return V8 plan.
- **Patch-retry contract**
  - Verify at most one retry attempt per chunk (`v9.patch_retry_attempted` appears at most once).
  - Retry must run only for fixable verifier issues.
- **Provenance**
  - Each emitted reason from provider/verifier/enricher/guardrail has prefixed companion code.
- **Compile safety**
  - Guardrail-pruned plans still compile and preserve non-empty actionable beats when source contains valid actions.

## open_conflicts
- `v9_full` gate cannot be fully approved without async event-provider parity (`generateEventTableAsync`) wired into async parse path.
- Provider contract does not yet mandate patch-op semantics for retry calls; runtime currently assumes best-effort behavior.
- Live-vs-offline gap report generation is still outside these two files; runtime emits signals but evidence pipeline must confirm interpretation.
- Build environment still has external `SnapKit` dependency failure, so full workspace compile proof is blocked by unrelated infra.

## votes
- `contract_gate`: **PASS (conditional)**  
  Contract shape and runtime mode semantics are consistent with V9 spec; condition is documenting retry semantics as best-effort until provider contract is tightened.
- `runtime_gate`: **PASS (conditional)**  
  Selector, guardrails, fallback provenance, and max-retry=1 are implemented; condition is async event-provider parity and threshold validation on target devices.
- `demo_gate`: **BLOCK**  
  Blockers: no confirmed real-app parity evidence package from this runtime slice, and no validated live-vs-offline gap report consumption tied to provenance counters.

## blockers_for_v9_full
- Missing async-native event-provider wiring in runtime path (`generateEventTableAsync` not used).
- Retry path not contractually constrained to patch-only behavior at provider boundary.
- Demo evidence not yet proving actor-intent/target behavior parity under `v9_full` with fallback rates within acceptance.
