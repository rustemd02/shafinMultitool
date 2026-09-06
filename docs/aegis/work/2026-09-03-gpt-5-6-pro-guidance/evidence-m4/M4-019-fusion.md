# M4-019 — neural-deterministic fusion

Status: **verified on the current store; one targeted test added, no
production change required**.

## Verified contract

- Deterministic: tie-breaks fall back to original index, decisions sort by
  decisionId, identical inputs produce identical outputs
  (`testExactSeverityTieStaysDeterministicWhenFusionDoesNotApply`).
- Material when calibrated: the new
  `testCalibratedNeuralReordersTiedRankingWithoutTouchingSeverity` proves
  calibrated neural evidence reorders an exact-severity tie
  (tied-b over tied-a) while the major issue stays first — fusion affects
  ranking, never severity order.
- Cannot bypass constraints: fusion output feeds `CameraAdviceSafetyGate`
  (evaluated after fusion in the pipeline) → `CameraBoundedActionPlanner` →
  `ActionVerifier`; forbidden gates, identity, motion, and verifier
  constraints are pinned by their own green suites (40/40 combined run).
  An ineligible neural snapshot (frame/mode mismatch) preserves the
  critique exactly.

## Verification

Fusion 8/8 + safety 12/12 + planner 10/10 + calibrator 10/10 (40/40) on
permitted iPhone 17e (`/private/tmp/m4-019-tests.xcresult`,
`/private/tmp/m4-019-tests-r2.xcresult`).
