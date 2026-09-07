# M5-026 — response validation evidence

Status: CLOSED on the current store.

## Delivered

- `shafinMultitool/SceneGeneratorModule/Services/SceneResponseValidator.swift`:
  explicit post-compile validation before any generator output reaches
  project state — empty beats/actions, duplicate entity IDs, dangling
  actor/object/target/holding/relation references, unresolved or
  invalid marked bindings, beat source-order violations. Returns
  ordered typed issues (empty = valid); repairs nothing.
- `SceneParseCoordinator.finalize` + `finalizeAsync`: both accept
  paths (local and remote) run the validator on the compiled script.
  Invalid outputs fall back to the rule-based result with typed
  `response_invalid:<issue>` trace reasons and a
  `fallbackRuleOnly` route — never silently repaired, never
  partially committed. Valid outputs pass through unchanged.
- `shafinMultitoolTests/SceneResponseValidatorTests.swift`: 10
  adversarial fixtures (empty beats/actions, dangling actor/target/
  holding/relation, duplicates, unresolved marked binding, order
  violation) — 10/10 PASS on permitted iPhone 17e.

## Verification

- New suite 10/10 + coordinator regression (ParseRequestFence 7/7 +
  ParserService 14/14): 31/31 PASS on permitted iPhone 17e
  (`/private/tmp/m5026-reg.xcresult`, `/private/tmp/m5026-tests.xcresult`).
- Full pipeline suites show 4 failures, all proven pre-existing on
  the clean tree via stash-baseline: `testDemoScenario...` (2
  assertions, V9 bundle path untouched by this task) and the 2
  registered heading-normalization cases from the M1 ledger. The
  two preservation stashes were untouched (pop verified).

## Boundaries

Repair policy itself is M5-027; long-form chunking is M5-028; the
compile proof is M5-029. This task only guarantees invalid outputs
cannot reach project state.
