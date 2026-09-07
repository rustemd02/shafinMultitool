# M5-027 — semantic repair boundary evidence

Status: CLOSED on the current store.

## Delivered

- `shafinMultitool/SceneGeneratorModule/Services/SceneRepairBoundary.swift`:
  the frozen registry classifying every deterministic transformation
  the pipeline/compiler may apply. All 66 production note codes are
  registered as syntax-safe normalizations (ID/order/format fixes,
  type-preserving downgrades with notes, collective expansions over
  declared rosters, verbatim text recovery, diagnostic-only flags);
  the forbidden set is empty by construction — every production
  repair preserves meaning, and the M5-024 closures (no default
  actor, no phantom actor_1, no fallback beats) are enforced by
  compiler errors, not notes. A future meaning-changing repair has
  a typed home (`forbiddenSemanticRepair`) that routes to
  clarification/regeneration, never to silent application.
- `shafinMultitoolTests/SceneRepairBoundaryTests.swift`: 4/4 PASS on
  permitted iPhone 17e (`/private/tmp/m5027-tests.xcresult`) —
  forbidden set empty, registry covers all production codes via a
  note-context source scan (suffixed codes normalized, v8 constant
  codes pinned), compiler downgrade preserves actor/beat structure,
  validator rejects what repair must not fix (dangling target).

## Audit method

Registry cross-checked against `grep -rho` production literals plus
constant-carried v8 codes: 66/66 match, 0 missing, 0 extra. The
in-test source scan fails on any future unregistered repair note.
