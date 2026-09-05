# M5-018 — accepted/leader motion

Status: **implemented, reviewed and verified in the isolated M5-018 lane**.

## Behavior delivered

- The leader countdown is request-owned: one event ID
  `generator.leader.<request UUID>.<epoch>` consumed through the existing
  `SETMotionEventLedger`; a clarification continuation reusing the same
  UUID+epoch cannot replay or replace the projection
  (`testingBeginGenerationLeader` returns false, presentation revision
  unchanged).
- Reduce Motion starts at the immediate `.action` state with the 0.12 s
  crossfade and no travel/countdown steps; the view emits no SwiftUI state
  during the body/update pass (fixture moved to `.task` after route entry).
- Rotation/re-render cannot replay the leader: the overlay is keyed by the
  event ID and the ledger pins one consumption per request.
- The DEBUG-only UI fixture launches with `-SHAFIN_GENERATOR_LEADER_FIXTURE`
  and holds the action phase 30 s so rotation/ownership probes can inspect
  the projection without racing the 0.45 s retire; unit tests never launch
  with the argument and keep production timing.

## Integration fixes during coordinator review

- Two pre-existing generator unit tests used fixed 100-yield spins for
  `.reading`; the leader legitimately delays parsing by ~1.4 s (3×0.32+0.45).
  Both now use a bounded 5 s poll. (Clarification trace, unresolved binding.)
- The two new leader UI tests raced the retire timing; fixed through the
  DEBUG fixture hold above.

## Pre-existing store failures (classified, not M5-018)

`testARFailureMessageUsesContainerPresentationLocale`,
`testDemoScenarioProviderPathRepairsTransferObjectsAndSourceOrder`,
`testDecisionTraceFixtureRUAndENReduceMotion`,
`testGeneratorENErrorBandUsesProductionLocale` — reproduced failing on plain
`store` (store-baseline build, `/private/tmp/m518-store-baseline3.log`,
`/private/tmp/m518-store-ui-baseline.log`). Registered in the ledger; out of
M5-018 scope.

## Verification

Final lane on permitted iPhone 17e: **100/104** — the 4 failures are exactly
the pre-existing store set above; all leader/clarification/binding tests and
both leader UI tests pass
(`/private/tmp/m518-final.xcresult`, fixes `/private/tmp/m518-fixes-r2.xcresult`).
`git diff --check` clean.

## Honest boundary

The committed simulator motion video is simulator evidence; physical-device
motion playback remains M10/M13 work.
