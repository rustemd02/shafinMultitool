# M2-022 — Advice stability metrics

Task: Create one temporal advice stabilizer with dwell, hysteresis, cooldown, and
material-change semantics.
Owner boundary: `AdviceTemporalOwner`. Implementation: NEW AdviceStabilizer.swift — pure
temporal stabilizer over CameraPlannerDecision stream (M2-020), injected deterministic clock.

## Semantics

- **Dwell/hysteresis**: a NEW decision (different decision kind or action) publishes only
  after N=3 consecutive identical frames; identical published advice resets pending.
- **Cooldown**: after a published change, the next change is suppressed until the cooldown
  window (default 3 s, configurable) expires from the last change.
- **Non-correction passthrough**: WAIT/ABSTAIN/SELECT_SUBJECT publish immediately when nothing
  is published (honest states, not advice) — but still participate in hysteresis once advice
  exists.
- **Material change**: `invalidate(frameID:reason:)` (M2-011 causes, safety contradiction)
  removes the published advice IMMEDIATELY, bypassing dwell/cooldown, and clears cooldown
  debt — a fresh episode publishes after hysteresis only.

## Tests (AdviceStabilizerTests 7/7 PASS; xcresult /private/tmp/shafin-m2-022.xcresult)

1. First CORRECT needs 3 hysteresis frames (2 suppressed, 3rd publishes).
2. Non-correction publishes immediately when nothing published.
3. Brief jitter (2 frames) does not flicker published advice.
4. Change at most once per cooldown: flip to "b" happens only after the 10 s window expires
   (latch verified over a 12 s sustained sequence).
5. Material change removes advice immediately, bypassing a 60 s cooldown.
6. Fresh episode after invalidation publishes without cooldown debt.
7. Scene-change sequence end-to-end: publish A → jitter B suppressed → sustained B flips →
   scene cut removes → nil.
