# V9.2 -> V9.3 Runtime Fallback Audit

## Verdict

The main V9.2 fallback problem was not model quality. It was mostly a stale V7/V8 mirror runtime policy rejecting semantically correct V9 event-table outputs.

Two concrete issues caused the inflated fallback/noise:

1. `stand` was treated as a target-required action in the SGv7 eval/runtime mirror. This made targetless standing invalid even though `stand` is a pose/state action and should not require `target`.
2. `pred_confidence_below_rule` compared V9's count-based reconstructed confidence against the old rule parser confidence. This rejected compact but correct V9 scripts after they had already passed object/action/dangling-target safety checks.

## Evidence

Frozen prediction file:

`experiments/sc_benchmark/dataset_v9_2_event_sft_seed42.event_predictions.jsonl`

Before V9.3 policy fix:

| Metric | Value |
|---|---:|
| Cases | 262 |
| Runtime accepts | 152 |
| Runtime rejects | 110 |
| `pred_confidence_below_rule` rejects | 109 |
| Schema-valid cases | 159 |
| Strict-success cases | 146 |
| Semantic gates all pass | 254 |
| Semantic gates all pass but rejected | 108 |

After V9.3 policy fix:

| Metric | Value |
|---|---:|
| Cases | 262 |
| Runtime accepts | 261 |
| Runtime rejects | 1 |
| Schema-valid cases | 262 |
| Strict-success cases | 254 |
| Semantic gates all pass | 254 |
| Semantic gates all pass but rejected | 0 |

The previous 103 schema-invalid cases were all caused by targetless `stand`.

## Benchmark Delta

Python benchmark output:

`docs/SGv9pipeline/runs/v9_2_seed42/from_user_predictions_policy_v93/benchmark_results_seed42/aggregate/scientific_report.md`

Key overall values for `dataset_v9_2_event_sft_policy_v93`:

| Metric | Value |
|---|---:|
| `json_valid_rate` | `1.0000` |
| `schema_valid_rate` | `1.0000` |
| `ordinal_actor_binding_accuracy` | `1.0000` |
| `target_resolution_accuracy` | `0.9812` |
| `chronology_phase_accuracy` | `0.9695` |
| `action_recall` | `0.9846` |
| `runtime_fallback_rate` | `0.0038` |
| `case_strict_success_rate` | `0.9695` |

## Remaining Real Failures

Only 8 non-strict cases remain after policy correction:

- `syn-0030::dialogue_then_put_down_object__base__s895761__deabe8d2`
- `hard-0021::ordinal_first_second_third__base__s186111__fc469b85`
- `hard-0031::ordinal_first_second_third__base__s273779__ade20c14`
- `hard-0039::ordinal_first_second_third__base__s432755__bdefbf8d`
- `hard-0064::ordinal_first_second_third__base__s715625__f19c8451`
- `hard-0065::ordinal_first_second_third__base__s720754__d5a760e4`
- `hard-0080::ordinal_first_second_third__base__s914834__e5f83825`
- `rt-0001::pref-rtf-rejected-dialogue_then_pick_up_object_then_give_to_third_actor__base__s225349__eea4feb1`

These are genuine model/compiler quality targets: one missed `put_down`, several three-actor ordinal/target issues, and one real-runtime three-beat failure.

## Implementation Notes

Changed files:

- `docs/SGv7pipeline/eval/runtime_policy.py`
- `docs/SGv7pipeline/eval/tests/test_eval_harness.py`
- `experiments/sc_benchmark/generate_predictions_from_endpoint.py`

Policy changes:

- Removed `stand` from target-required actions.
- Replaced relative `pred_confidence_below_rule` fallback with a critical low-confidence guard.
- Added regression tests for targetless `stand` and safe-script confidence gaps.

## Next V9.3 Work

The next data/model step should focus narrowly on the 8 remaining failures, not on generic fallback:

- three-actor ordinal scenes: first/second/third bindings plus `give`/`pick_up` target and held-object continuity;
- dialogue plus object manipulation: especially missing `put_down`;
- real-runtime three-beat scenes with dialogue -> pick_up -> give_to_third.

