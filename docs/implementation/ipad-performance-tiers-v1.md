# ipad-performance-tiers-v1 — M10-021 locked tier matrix

Status: **locked matrix (v1). Simulator/device execution of the matrix is
M13; the budgets below are the enforced code values, not aspirations.**

## Tiers

| Tier | Representative hardware | Governor behavior |
|---|---|---|
| A12-class (oldest supported) | A12 iPad (8th gen baseline) | `constrained` budget at nominal thermals; heavy models off under any thermal pressure (`eco`) |
| Compact A15-class | iPad mini (A15) | nominal budget at nominal thermals; `constrained` under fair, `eco` under serious/critical |
| M-series regular-width | M-chip iPad Air/Pro | nominal budget up to serious; `eco` only at critical |

## Budget coverage per subsystem

- **Camera neural**: `heavyModelsEnabled` gates DETR/neural evidence
  (`Budget.nominal` true; constrained/eco false); cadence via
  high/medium/low frequencies.
- **AR**: frame processing interval follows the same tier; relocalization
  work is bounded by the scheduler budget.
- **Recording**: writer backpressure policy (M7-011) is tier-independent;
  thermal posture is recorded per take (M7-030).
- **Generator UI**: overlay recomposition follows `effectivePerformance`;
  Reduce Motion keeps steady states.
- **Storyboard**: beat reflow/re-render is main-actor work bounded by the
  same scheduler cadence; no per-frame timers exist.

Tiers are selected by the `ThermalGovernor` from live thermal state and
battery level — never from a device-name allowlist, so a future device
falls into the correct tier by behavior.
