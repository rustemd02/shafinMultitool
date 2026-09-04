# M2-015 — Motion/stability state calibration: metrics and tests

Task: Calibrate motion/stability state used by WAIT, stabilization advice, and before/after
capture.
Owner boundary: `TechnicalFeatureOwner`. Implementation: MotionGate.swift extensions —
MotionTransition records, injectable deterministic clock, bounded timeline (32), dwell
measurement. The existing still/moving/panning hysteresis (enter/exit thresholds + 8–12
sample commits) was preserved unchanged.

## Metrics exposed

- `MotionTransition(state, timestamp, shakeLevel)` — committed transitions only (hysteresis
  commits), retained oldest-first, bounded to 32.
- `timeline()` — full retained history for WAIT gating and before/after capture.
- `stateStartTimestamp()` / `dwellSeconds(asOf:)` — current-state age for WAIT and verifier
  windows.
- DEBUG `init(startMotionUpdates:clock:)` — synthetic traces under a deterministic clock
  (ScriptedClock stepping 1/60s or 1s).

## Tests (MotionGateTimelineTests 6/6 PASS; xcresult /private/tmp/shafin-m2-015.xcresult)

1. Brief noise (5 samples) does not flicker .still and records no transition.
2. Sustained motion (10 samples) commits .moving with a timestamped transition ≥ test start.
3. still→moving→still: both transitions retained in order with ascending timestamps.
4. Dwell measured for .panning after a 12-sample commit (0 ≤ dwell ≤ 13s).
5. Dwell nil when asOf precedes the state start (fail closed).
6. Panning requires low accel and survives brief gyro dips via hysteresis.

Implementation attempt: hysteresis decays the gyro EMA over the still burst — the commit
threshold is met only in the burst tail; the test burst was extended to 20 samples instead of
weakening the production thresholds.
