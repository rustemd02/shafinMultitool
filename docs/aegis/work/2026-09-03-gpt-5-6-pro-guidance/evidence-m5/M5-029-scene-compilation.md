# M5-029 — scene compilation evidence

Status: CLOSED on the current store.

## Delivered

`shafinMultitoolTests/ScenePlanCompilerContinuityTests.swift` — 5/5
PASS on permitted iPhone 17e (`/private/tmp/m5029-tests.xcresult`):

- multi-actor/multi-object plan compiles with every action
  actor/target/holding reference resolved (asserted across the whole
  script) and the result passes the M5-026 response validator clean;
- unknown actor ref yields typed `ScenePlanCompilerError.missingActorRef`
  naming the ghost ref; unknown holding ref yields
  `missingObjectRef` — no silent placeholder substitution;
- static object-only scene compiles honestly (objects kept, no
  phantom actor, no fabricated beat) — the M5-024 posture holds at
  the compiler;
- the M5-025 client bridge round-trip: a compiled script projected
  back through the bridge plan recompiles to an identical script —
  continuity across the remote seam with zero semantic drift.

## Canonical conventions pinned by fixtures

- actor IDs map ref→ordinal (`first`→`actor_1`); object IDs become
  ordinal `object_N` with type/order as surviving identity;
- beats keep their refs; relations resolve both endpoints or skip
  with the v8 note.

## Boundaries

No production change: the compiler already enforced every acceptance
point; this task pins them with typed-failure and continuity fixtures.
