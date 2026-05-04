# Camera Analysis Eval Summary

Run:
- bundle: `camera_analysis_eval_v1_demo`
- baseline: `legacy_suggestion_engine`
- candidate: `camera_analysis_v1_core`

## Strengths
- `issue_f1`: `0.89` -> `1.00`
- `primary_action_match_rate`: `0.67` -> `1.00`
- `good_frame_confirmation_rate`: `1.00` -> `1.00`

## Issues
- `unsupported_claim_rate`: `0.00` -> `0.00`
- `hint_visibility_policy_accuracy`: `1.00` -> `1.00`
- `hint_jitter_rate`: n/a

## Actions
- `fallback_policy_accuracy`: `0.67` -> `1.00`
- `summary_consistency_rate`: `0.33` -> `0.67`

## Explanation Faithfulness
- `explanation_faithfulness_score`: `0.78` -> `0.95`

## Release / Merge Recommendation

Status: `pass`

Why:
- no critical regression on issue_f1
- no critical regression on primary_action_match_rate
- good frame confirmation did not regress
- unsupported claims did not increase
- critical buckets improved in at least two categories
