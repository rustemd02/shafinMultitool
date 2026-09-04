# M2-010 — Temporal subject tracking: state traces

Task: Implement temporal tracking for selected/auto subject with periodic redetection and
explicit loss.
Owner boundary: `SubjectTrackingOwner`. Implementation: NEW SubjectTracker.swift (pure,
scripted-sequence driven; AnalysisPipeline integration consumes it per frame).

## Mechanism

- Re-association by IoU ≥ 0.3 between the tracked region and candidates → same
  SubjectTrackIdentity persists (moderate motion, partial occlusion).
- Identity-swap guard: a matched candidate whose center jumped > 0.4 from the tracked center is
  rejected (treated as a miss) — no silent identity swap; tracked region stays put.
- Explicit loss: consecutive misses ≥ 10 → phase `.lost` with `lostSinceFrameID`;
  `markLost(frameID:)` for immediate invalidation (route exit, lens change — M2-011).
- Reconciliation: after loss, a candidate consistent with the remembered region re-activates the
  SAME identity (reconciliations+1); a distant candidate does not adopt the old identity.
- Periodic redetection: counter of frames since last full redetection; at the interval the
  `redetectionDue` flag rises and LATCHES until the pipeline calls `noteRedetectionPerformed()`
  (associations do not reset the cadence — only the actual pass does).

## Track state traces (SubjectTrackerTests 10/10 PASS; xcresult /private/tmp/shafin-m2-010.xcresult)

1. Moderate motion f1–f4: trackID constant, phase active.
2. Occlusion f1–f9 (misses < limit): active; reappearance f10: same identity, missed 0.
3. Misses f1–f11: lost at f10 (lostSinceFrameID=f10).
4. markLost immediate: lost, lostSinceFrameID=fX.
5. Lost → candidate near remembered region: active, same identity, reconciliations=1.
6. Lost → distant candidate: stays lost, no identity adoption.
7. Jump guard: oversized overlapping candidate rejected as miss, region unchanged.
8. Redetection cadence: false f1–f4, true at f5, latches f6, cleared by
   noteRedetectionPerformed, restarts.
9. Unknown resolution: no track, observe returns nil.
10. Reset clears tracking.

Implementation attempts: redetection cadence was reset by every association (flag never rose) —
separated the cadence counter from associations; latch requires reconstructing the immutable
state (let fields).
