# Camera Analysis Eval Summary

Run:
- bundle: `camera_analysis_eval_v1_demo`
- baseline: `legacy_suggestion_engine`
- candidate: `camera_analysis_v1_core`

## Strengths

- Candidate learned to explicitly confirm a good frame instead of inventing corrective advice.
- Strength detection is now aligned with structured semantics on clean single-subject shots.
- Summary blocks stay consistent with `CritiqueReport.verdict` and linked strengths.

## Issues

- Legacy baseline still misses multi-factor failures like `edge pressure + backlight`.
- Weak-signal live cases are fragile: this bucket needs more sequence coverage before merge-heavy rollout.
- Region grounding is not yet scored in `v1`; add IoU once overlay geometry stabilizes.

## Actions

- Candidate improved `primary_action_match_rate` from `0.00` to `0.67`.
- `good_frame_confirmation_rate` improved from `0.00` to `1.00`.
- `fallback_policy_accuracy` improved from `0.33` to `1.00`, which is especially important for moving-camera live UX.

## Explanation Faithfulness

- `explanation_faithfulness_score` improved from `0.21` to `0.87`.
- Every winning candidate case had a valid `observation -> interpretation -> recommendation` chain.
- No unsupported claim regressions were observed in this demo bundle.

## Release / Merge Recommendation

Status: `pass`

Why:
- no regression on core detection/action metrics;
- critical buckets improved;
- candidate is much safer on `good frame` and `weak signal fallback` behavior.

Next actions:
- add at least one `dialogue_look_space` sequence case;
- add overlay-region gold boxes for `region_grounding_iou_mean`;
- expand `moody_backlight_exception` coverage before reasoning-layer rollout.
